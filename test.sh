#!/usr/bin/env bash
# Runs an extracted archive's wish with no TCL_LIBRARY/TK_LIBRARY set and checks it loads its own
# script libraries and Tk. Usage: test.sh <target> (run on that target's OS, after extracting into dist/)
set -euo pipefail

target=$1
pkg="dist/tcltk-$target"
case "$target" in
  linux-*)   wish="$pkg/bin/wish";        expected=x11;   run=(xvfb-run -a) ;;
  macos-*)   wish="$pkg/bin/wish";        expected=aqua;  run=() ;;
  windows-*) wish="$pkg/bin/wish86.exe";  expected=win32; run=() ;;
  *) echo "unknown target $target" >&2; exit 1 ;;
esac

case "$target" in
  linux-*) ldd "$wish" ;;
  macos-*)
    otool -L "$wish"
    if otool -L "$wish" | tail -n +2 | grep -v -e '^[[:space:]]*/usr/lib/' -e '^[[:space:]]*/System/Library/'; then
      echo "wish links non-system libraries" >&2; exit 1
    fi
    ;;
esac

# wish's stdout is not reliable on Aqua or Windows, so the probe writes to a file.
mkdir -p build
rm -f build/probe.out
cat > build/probe.tcl <<'EOF'
set f [open build/probe.out w]
puts $f "[info patchlevel] [tk windowingsystem]"
package require msgcat
if {$tcl_platform(platform) eq "windows"} {package require registry; puts $f registry}
close $f
exit
EOF
env -u TCL_LIBRARY -u TK_LIBRARY timeout 30 ${run[@]+"${run[@]}"} "$wish" build/probe.tcl
cat build/probe.out
version=$(sed -n 's/^tcl //p' "$pkg/VERSION")
grep -qx "$version $expected" build/probe.out
