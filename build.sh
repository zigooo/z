#!/bin/bash

# if [ $# -ne 1 ]; then
#     echo "./build.sh version"
#     exit
# fi

rm -rf _
mkdir _
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
cp zig-out/bin/z _/z_linux_amd64

zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe
cp zig-out/bin/z _/z_linux_arm64

zig build -Dtarget=x86_64-macos-none -Doptimize=ReleaseSafe
cp zig-out/bin/z _/z_darwin_amd64

zig build -Dtarget=aarch64-macos-none -Doptimize=ReleaseSafe
cp zig-out/bin/z _/z_darwin_arm64
# nami release github.com/txthinking/z $1 _
# rm -rf _
