#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 BSP_ROOT OUTPUT_FILE" >&2
    exit 2
fi

BSP_ROOT=$(realpath "$1")
OUTPUT_FILE=$2
HOST_DIR="$BSP_ROOT/work/buildroot/host"
CC="$HOST_DIR/bin/aarch64-buildroot-linux-gnu-gcc"
PKG_CONFIG="$HOST_DIR/bin/pkg-config"
SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

[[ -x "$CC" ]] || { echo "Missing cross compiler: $CC" >&2; exit 2; }
[[ -x "$PKG_CONFIG" ]] || { echo "Missing pkg-config: $PKG_CONFIG" >&2; exit 2; }

export PKG_CONFIG_SYSROOT_DIR="$HOST_DIR/aarch64-buildroot-linux-gnu/sysroot"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_SYSROOT_DIR/usr/lib/pkgconfig:$PKG_CONFIG_SYSROOT_DIR/usr/share/pkgconfig"

"$CC" -O2 -Wall -Wextra -Werror \
    "$SOURCE_DIR/recv_rgb565_wayland.c" \
    -o "$OUTPUT_FILE" \
    $("$PKG_CONFIG" --cflags --libs gstreamer-app-1.0)

file "$OUTPUT_FILE"
