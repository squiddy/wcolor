wlr-layer-shell-unstable-protocol.h:
	wayland-scanner client-header \
		protocols/wlr-layer-shell-unstable-v1.xml $@

wlr-layer-shell-unstable-protocol.c: wlr-layer-shell-unstable-protocol.h
	wayland-scanner private-code \
		protocols/wlr-layer-shell-unstable-v1.xml $@

wlr-screencopy-unstable-protocol.h:
	wayland-scanner client-header \
		protocols/wlr-screencopy-unstable-v1.xml $@

wlr-screencopy-unstable-protocol.c: wlr-screencopy-unstable-protocol.h
	wayland-scanner private-code \
		protocols/wlr-screencopy-unstable-v1.xml $@

xdg-shell-protocol.h:
	wayland-scanner client-header \
		protocols/xdg-shell.xml $@

xdg-shell-protocol.c: xdg-shell-protocol.h
	wayland-scanner private-code \
		protocols/xdg-shell.xml $@

wcolor: shm.c xdg-shell-protocol.c wlr-layer-shell-unstable-protocol.c wlr-screencopy-unstable-protocol.c main.c
	$(CC) $(CFLAGS) \
		-g -Werror -Iinclude/ \
		-lrt \
		-lwayland-client \
		-lcairo \
		-o $@ $^

clean:
	rm -f wcolor xdg-shell-protocol.* wlr-layer-shell-unstable-protocol.* wlr-screencopy-unstable-protocol.*

.DEFAULT_GOAL=wcolor
.PHONY: clean