const std = @import("std");
const builtin = @import("builtin");

var mutex = std.Thread.Mutex{};

pub fn syslog(err: anyerror) void {
    // 使用 stderr 输出错误信息，替代 C 的 syslog
    const stderr = std.fs.File.stderr();
    const msg = std.fmt.allocPrint(std.heap.page_allocator, "zhen: {s}\n", .{@errorName(err)}) catch return;
    defer std.heap.page_allocator.free(msg);
    stderr.writeAll(msg) catch {};
}

pub fn e(f: std.fs.File, err: anyerror) void {
    mutex.lock();
    defer mutex.unlock();
    const now = std.time.timestamp();
    const msg = std.fmt.allocPrint(std.heap.page_allocator, "{} {}\n", .{ now, err }) catch |err1| {
        syslog(err1);
        return;
    };
    defer std.heap.page_allocator.free(msg);
    f.writeAll(msg) catch |err1| {
        syslog(err1);
        return;
    };
    f.sync() catch |err1| {
        syslog(err1);
        return;
    };
}

pub fn getuid() std.posix.uid_t {
    return std.posix.getuid();
}

pub fn setsid() !std.posix.pid_t {
    // 对于 Linux musl 目标，std.posix.setsid 有类型转换问题，使用系统调用直接实现
    // 对于其他平台，使用标准库实现
    if (builtin.target.os.tag == .linux) {
        // Linux 系统调用：setsid
        const rc: isize = switch (builtin.target.cpu.arch) {
            .x86_64 => @as(isize, @bitCast(std.os.linux.syscall0(.setsid))),
            .aarch64 => @as(isize, @bitCast(std.os.linux.syscall0(.setsid))),
            else => return std.posix.setsid(), // 其他架构回退到标准库
        };
        if (rc == -1) {
            return error.SetsidFailed;
        }
        return @intCast(rc);
    } else {
        // 其他平台使用标准库实现
        return std.posix.setsid();
    }
}

pub fn getdtablesize() c_int {
    // 这个函数在 Zig 中没有直接对应，但可以通过其他方式获取
    // 如果不需要可以删除，或者使用 std.posix.getrlimit
    _ = std.posix.getrlimit(.NOFILE) catch return 1024;
    return 1024; // 默认值
}

pub fn umask(mask: std.posix.mode_t) std.posix.mode_t {
    // 对于 Linux musl 目标，使用系统调用直接实现
    // 对于 macOS 和其他平台，umask 不是必需的，可以忽略或使用系统调用
    if (builtin.target.os.tag == .linux) {
        // Linux 系统调用：umask
        const old_mask: std.posix.mode_t = switch (builtin.target.cpu.arch) {
            .x86_64, .aarch64 => {
                const mask_usize: usize = @intCast(mask);
                const result = std.os.linux.syscall1(.umask, mask_usize);
                return @as(std.posix.mode_t, @intCast(result));
            },
            else => mask, // 其他架构回退
        };
        return old_mask;
    } else {
        // macOS 和其他平台：umask 主要用于设置文件创建权限掩码
        // 在 daemon 进程中，通常设置为 0 以允许所有权限
        // 这里我们简单地返回 0，因为在实际使用中，文件权限由创建时指定
        // 如果需要真正的 umask 功能，可以使用系统调用或链接系统库
        // 注意：mask 参数在 Linux 分支中已使用，这里不需要使用它
        return 0; // 返回 0 表示没有之前的掩码限制
    }
}

// setenv 函数已移除，环境变量通过 std.process.EnvMap 传递给子进程
// 如果需要设置当前进程的环境变量，可以使用系统调用实现

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) !?struct { b: []u8, n: usize } {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == std.fs.File.OpenError.FileNotFound) {
            return null;
        }
        return err;
    };
    defer file.close();
    var b = try allocator.alloc(u8, 1024 * 4);
    errdefer allocator.free(b);
    var l: usize = 0;
    while (true) {
        const n = try file.read(b[l..]);
        if (n == 0) {
            break;
        }
        l += n;
        if (b.len == l) {
            const ok = allocator.resize(b, b.len + 1024 * 4);
            if (ok) {
                b.len = b.len + 1024 * 4;
                continue;
            }
            var b1 = try allocator.alloc(u8, b.len + 1024 * 4);
            @memcpy(b1[0..b.len], b);
            allocator.free(b);
            b = b1;
        }
    }
    return .{ .b = b, .n = l };
}

pub fn testNetwork(dns: []const u8) !void {
    const addr = try std.net.Address.parseIp6(dns, 53);
    const s = try std.posix.socket(std.posix.AF.INET6, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
    defer std.posix.close(s);
    try std.posix.connect(s, &addr.any, addr.getOsSockLen());
    const in = .{ 0x67, 0x88, 0x1, 0x0, 0x0, 0x1, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xa, 0x74, 0x78, 0x74, 0x68, 0x69, 0x6e, 0x6b, 0x69, 0x6e, 0x67, 0x3, 0x63, 0x6f, 0x6d, 0x0, 0x0, 0x1c, 0x0, 0x1 };
    _ = try std.posix.send(s, &in, 0);
    var fds = [_]std.posix.pollfd{.{ .fd = s, .events = std.posix.POLL.IN, .revents = 0 }};
    const rc = try std.posix.poll(&fds, 3000);
    if (rc == 0) return error.Timeout;
    var b: [4 * 1024]u8 = undefined;
    _ = try std.posix.recv(s, &b, 0);
}
