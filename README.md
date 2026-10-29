# tcltk-build

Prebuilt [Tcl/Tk](https://www.tcl-lang.org) 8.6.18 `wish` archives for Pure Data's editor, for
linux-x86_64, macos-aarch64 and windows-x86_64. Tcl and Tk are linked statically into `wish` and
compiled with `zig cc` (Zig 0.17.0) using Tcl/Tk's own configure and make.

`./build.sh <target>` builds `dist/tcltk-<target>.tar.gz`; `./test.sh <target>` runs the extracted
`wish` and checks it reports `8.6.18` and the expected windowing system. Push a `v*` tag to publish
a release.

Archive layout (`tcltk-<target>/`):

- `bin/wish` (`bin/wish86.exe` on Windows)
- `lib/tcl8.6/`, `lib/tk8.6/`, `lib/tcl8/` (Tcl modules such as msgcat)
- Windows only: `lib/reg1.3/`, `lib/dde1.4/` (the `registry` and `dde` packages, as DLLs)
- `licenses/`, `VERSION`

`wish` finds its libraries in `../lib` relative to itself, so keep `bin/` and `lib/` side by side
(e.g. `Pd.app/Contents/MacOS/Pd-wish` with `Pd.app/Contents/lib/`). `TCL_LIBRARY` and
`TK_LIBRARY` still override that when set.

## Targets

- macos-aarch64: Aqua Tk, built natively on macOS 14 against the SDK. Links only system
  frameworks. In an app bundle, wish runs `Contents/Resources/Scripts/AppMain.tcl`, as Pd expects.
- linux-x86_64: X11 Tk with Xft, glibc 2.28. Built against a sysroot of Ubuntu 18.04 `.deb`s
  (`sysroot.sh`), so it cross-builds from any host. At runtime it needs the system's libX11,
  libXft and libfontconfig (`libx11-6 libxft2 libfontconfig1` on Debian/Ubuntu).
- windows-x86_64: MinGW build (`x86_64-windows-gnu`), GUI subsystem, using the UCRT. Needs no
  DLLs beyond Windows' own.

Upstream code is unmodified. Licenses: Tcl and Tk BSD-style (`licenses/`).
