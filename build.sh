#!/usr/bin/env bash
# Builds a self-contained wish (Tcl/Tk statically linked) plus the Tcl and Tk script libraries
# with `zig cc`, for Pure Data's editor. Usage: build.sh <target>
set -euo pipefail

target=$1
name="tcltk-$target"
root=$(pwd)
work="$root/build/$target"
pkg="$root/dist/$name"
version=8.6.18
tcl_sha256=14f9af32b1767ff718477a8f974ad03c34341097e6b43f4ce54644ee974e268e
tk_sha256=95cd528a80f5e4bdb557af9b14a7197d6860793a3894e25e7c9fad2ed05d4c3c
# The compiled-in library path must not exist on users' machines, so wish falls back to
# <exe>/../lib/tcl8.6 and <exe>/../lib/tk8.6.
prefix=/nonexistent/tcltk

case "$target" in
  linux-x86_64)   zig_target=x86_64-linux-gnu.2.28; host=x86_64-pc-linux-gnu; dir=unix ;;
  macos-aarch64)  zig_target=aarch64-macos.14.0;    host=;                    dir=unix ;;
  windows-x86_64) zig_target=x86_64-windows-gnu;    host=x86_64-w64-mingw32;  dir=win ;;
  *) echo "unknown target $target" >&2; exit 1 ;;
esac

rm -rf "$work" "$pkg" "dist/$name.tar.gz"
mkdir -p "$work/tools" "$pkg/bin" "$pkg/lib" "$pkg/licenses"

# zig needs the macOS SDK or the Linux sysroot spelled out.
case "$target" in
  macos-*)
    sdk=$(xcrun --show-sdk-path)
    sdk_flags="-F$sdk/System/Library/Frameworks -isystem $sdk/usr/include -L$sdk/usr/lib"
    ;;
  linux-*)
    sysroot="$work/sysroot"
    "$root/sysroot.sh" "$sysroot"
    sdk_flags="-isystem $sysroot/usr/include -L$sysroot/usr/lib/x86_64-linux-gnu"
    ;;
  *) sdk_flags= ;;
esac
# zig rejects the repeated -framework flags Tk's configure emits, and ignores MinGW's -mwindows.
for tool in cc c++; do
  cat > "$work/tools/$tool" <<EOF
#!/usr/bin/env bash
args=()
frameworks=" "
while [ \$# -gt 0 ]; do
  case "\$1" in
    -framework)
      case "\$frameworks" in *" \$2 "*) ;; *) frameworks="\$frameworks\$2 "; args+=(-framework "\$2") ;; esac
      shift 2 ;;
    -mwindows) args+=(-Wl,--subsystem,windows); shift ;;
    *) args+=("\$1"); shift ;;
  esac
done
exec zig $tool -target $zig_target -g0 $sdk_flags "\${args[@]}"
EOF
done
for tool in ar ranlib; do
  printf '#!/bin/sh\nexec zig %s "$@"\n' "$tool" > "$work/tools/$tool"
done
case "$target" in
  # configure branches on `uname`, so a cross build from macOS must answer as Linux.
  # Tk's configure asks xft-config for the Xft flags; answer for the sysroot instead of the host.
  linux-*)
    printf '#!/bin/sh\ncase "$1" in -r) echo 5.15.0 ;; -m|-p) echo x86_64 ;; *) echo Linux ;; esac\n' \
      > "$work/tools/uname"
    printf '#!/bin/sh\ncase "$1" in --cflags) echo "-I%s/usr/include/freetype2" ;; *) echo -lXft ;; esac\n' \
      "$sysroot" > "$work/tools/xft-config"
    ;;
  # windres compiles the .rc resources (icon, manifest): translate its flags for `zig rc`.
  windows-*)
    cat > "$work/tools/windres" <<'EOF'
#!/usr/bin/env bash
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o) args+=(/fo "$2"); shift 2 ;;
    --define|-D) args+=(/d "$2"); shift 2 ;;
    --include|-I|--include-dir) args+=(/i "$2"); shift 2 ;;
    -D*) args+=(/d "${1#-D}"); shift ;;
    *) input=$1; shift ;;
  esac
done
exec zig rc /:output-format coff /:auto-includes gnu "${args[@]}" -- "$input"
EOF
    ;;
esac
chmod +x "$work/tools/"*
export PATH="$work/tools:$PATH"

for p in tcl tk; do
  tarball="$p$version-src.tar.gz"
  sha256_var="${p}_sha256"
  [ -f "$root/build/$tarball" ] || curl -sfL -o "$root/build/$tarball" \
    "https://prdownloads.sourceforge.net/tcl/$tarball"
  echo "${!sha256_var}  $root/build/$tarball" | shasum -a 256 -c -
  tar -xzf "$root/build/$tarball" -C "$work"
done
tcl_src="$work/tcl$version"
tk_src="$work/tk$version"

configure_flags=(--prefix="$prefix" --disable-shared --enable-threads ${host:+--host=$host})
case "$target" in
  macos-*) tk_flags=(--enable-aqua) ;;
  linux-*) tk_flags=(--with-x --enable-xft --disable-xss --x-includes="$sysroot/usr/include"
             --x-libraries="$sysroot/usr/lib/x86_64-linux-gnu") ;;
  windows-*) configure_flags+=(--enable-64bit); tk_flags=() ;;
esac
export CC=cc CXX=c++ AR=ar RANLIB=ranlib RC=windres
jobs=$(getconf _NPROCESSORS_ONLN)

(
  cd "$tcl_src/$dir"
  ./configure "${configure_flags[@]}" > "$work/tcl-configure.log"
  make -j"$jobs" binaries > "$work/tcl-build.log"
  make install-binaries install-libraries INSTALL_ROOT="$work/install" > "$work/tcl-install.log"
)
(
  cd "$tk_src/$dir"
  ./configure "${configure_flags[@]}" "${tk_flags[@]}" --with-tcl="$tcl_src/$dir" \
    > "$work/tk-configure.log"
  case "$target" in
    linux-*) grep -q HAVE_XFT Makefile || { echo "Tk configure did not find Xft" >&2; exit 1; } ;;
  esac
  make -j"$jobs" binaries > "$work/tk-build.log"
  make install-binaries install-libraries INSTALL_ROOT="$work/install" > "$work/tk-install.log"
)

# lib/tcl8 holds Tcl modules such as msgcat, which Tk requires.
lib="$work/install$prefix/lib"
cp -R "$lib/tcl8.6" "$lib/tk8.6" "$lib/tcl8" "$pkg/lib/"
case "$target" in
  # Static Windows builds still ship registry (used by Pd) and dde as stub-enabled DLL packages.
  windows-*)
    cp "$work/install$prefix/bin/wish86s.exe" "$pkg/bin/wish86.exe"
    cp -R "$lib/reg1.3" "$lib/dde1.4" "$pkg/lib/"
    rm "$pkg"/lib/*/*.dll.a
    ;;
  *) cp "$work/install$prefix/bin/wish8.6" "$pkg/bin/wish" ;;
esac
cp "$tcl_src/license.terms" "$pkg/licenses/tcl.txt"
cp "$tk_src/license.terms" "$pkg/licenses/tk.txt"
printf 'tcl %s\ntk %s\nzig %s %s\n' "$version" "$version" "$(zig version)" "$zig_target" > "$pkg/VERSION"

# COPYFILE_DISABLE keeps macOS tar from adding AppleDouble `._*` files.
COPYFILE_DISABLE=1 tar -czf "dist/$name.tar.gz" -C dist "$name"
