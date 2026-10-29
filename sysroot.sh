#!/usr/bin/env bash
# Extracts the Ubuntu 18.04 X11/Xft headers and libraries Tk links against into a sysroot,
# so `zig cc` can cross-build linux-x86_64 from any host. Usage: sysroot.sh <dir>
set -euo pipefail

dir=$1
mirror=http://archive.ubuntu.com/ubuntu
# 18.04 (glibc 2.27) so the libraries need nothing newer than the glibc 2.28 wish targets.
debs="
pool/main/x/xorgproto/x11proto-dev_2018.4-4_all.deb 1797fb12c67d037fb530e7203bf38a2c94e1e239bf654432506181c9d43bda01
pool/main/libx/libx11/libx11-dev_1.6.4-3_amd64.deb 01ba623eb43abc7dc2a81fc2a9aa830e26c4d10f830c284a6f8801a7eaf8dab7
pool/main/libx/libx11/libx11-6_1.6.4-3_amd64.deb 1b17321e5743c9da26463193a1a0f7a76c11f5aa6a543ef0c444f169e88db550
pool/main/libx/libxrender/libxrender-dev_0.9.10-1_amd64.deb aeb7abe8409afbb484c06882c158e7e695743d678387064ef95bdb3d6edbce15
pool/main/libx/libxrender/libxrender1_0.9.10-1_amd64.deb bfda6dc44a39d6500ac2974b3113105477adce457699aadd99f022d5a4858c1c
pool/main/x/xft/libxft-dev_2.3.2-1_amd64.deb 9afdcd41fc1467e490dc7d6b7a881b9a61c694b32a854aa50723b03b7f876e1b
pool/main/x/xft/libxft2_2.3.2-1_amd64.deb 823ae2f0bb194376463fdf35518effc4c20a38120ed4b55b0b49440ec22a4075
pool/main/f/fontconfig/libfontconfig1-dev_2.12.6-0ubuntu2_amd64.deb ce4d63624128b06eef6ea0f2d04f0baa1cba22d7325fcbcce48ce5cbe2533b1a
pool/main/f/fontconfig/libfontconfig1_2.12.6-0ubuntu2_amd64.deb 647bb8f09e751a39d488b0260db6015ce1118c56114cc771dd5bf907180f0c80
pool/main/f/freetype/libfreetype6-dev_2.8.1-2ubuntu2_amd64.deb 6c68c863aa7a0499b8c58da4013b0864b15ea3dad0c1de401f2a8f40cd258d26
pool/main/f/freetype/libfreetype6_2.8.1-2ubuntu2_amd64.deb ffc48ddd362288e45525f12a9a84eae55243d45206ea4d904648d2d79b9e177a
"

mkdir -p "$dir/debs"
echo "$debs" | while read -r path sha256; do
  [ -n "$path" ] || continue
  deb="$dir/debs/$(basename "$path")"
  [ -f "$deb" ] || curl -sfL -o "$deb" "$mirror/$path"
  echo "$sha256  $deb" | shasum -a 256 -c - > /dev/null
  (cd "$dir/debs" && ar x "$deb" && tar -xf data.tar.* -C "$dir" && rm -f data.tar.* control.tar.* debian-binary)
done
