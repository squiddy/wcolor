FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y curl xz-utils && \
    curl https://ziglang.org/download/0.11.0/zig-linux-aarch64-0.11.0.tar.xz > zig.tar.xz && \
    tar -xf zig.tar.xz && \
    apt-get install -y wayland-utils wayland-protocols wayland-scanner++ \
                       pkg-config libwayland-dev libcairo2 libcairo2-dev

# RUN pkg-config --variable=pkgdatadir wayland-scanner
# RUN mkdir /opt/src
# WORKDIR /opt/src
# COPY . /opt/src/

# RUN /zig-linux-aarch64-0.11.0/zig build
