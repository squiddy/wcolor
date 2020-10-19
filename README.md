# wcolor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**WORK IN PROGRESS!**

Simple color picker for Wayland. Pick any color on the screen using the mouse. This is basically the Wayland aquivalent to [xcolor](https://github.com/Soft/xcolor).

## Usage

Run `wcolor` and select a color. Its hexadecimal RGB representation will be
printed to standard output.

## Screenshot

![Preview](extras/screenshot.png)

## Setup

* `cd deps/zig-wayland/`
* `zig build`
* `./zig-cache/bin/scanner protocol/wayland.xml /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml ../wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml ../wlr-protocols/unstable/wlr-screencopy-unstable-v1.xml`

* `cd ..`
* `zig build`

## References

* https://github.com/ifreund/zig-wayland
* https://github.com/Soft/xcolor (the X11 version)
* https://github.com/emersion/grim
* https://github.com/emersion/slurp (consulting the source of grim and slurp helped a lot in understanding Wayland)