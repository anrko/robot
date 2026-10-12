#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 BSP_ROOT OUTPUT_FILE" >&2
    exit 2
fi
BSP_ROOT=$(realpath "$1")
OUTPUT_FILE=$2
CC="$BSP_ROOT/work/buildroot/host/bin/aarch64-buildroot-linux-gnu-gcc"
SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ -x "$CC" ]] || { echo "Missing cross compiler: $CC" >&2; exit 2; }
"$CC" -O2 -Wall -Wextra -Werror \
    "$SOURCE_DIR/rk3588_udp_wifi_relay.c" -o "$OUTPUT_FILE"
file "$OUTPUT_FILE"
