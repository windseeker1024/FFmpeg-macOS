#!/bin/bash
set -e

# -- locate script directory (follows symlinks) --
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# -- default paths --
SRC_DIR="${SCRIPT_DIR}/nv-codec-headers"
PREFIX="/mingw64"

# -- parse command-line arguments --
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-dir)
            SRC_DIR="$2"; shift 2 ;;
        --prefix)
            PREFIX="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--src-dir DIR] [--prefix DIR]"
            echo "  --src-dir  nv-codec-headers source directory  (default: \${SCRIPT_DIR}/nv-codec-headers)"
            echo "  --prefix   Install prefix                     (default: /mingw64)"
            exit 0 ;;
        *)
            echo "[WARN] Unknown argument: $1"; shift ;;
    esac
done

export PATH="/mingw64/bin:$PATH"

echo "===== nv-codec-headers install ====="
echo "[INFO] Source dir  : $SRC_DIR"
echo "[INFO] Install dir : $PREFIX"

# -- verify source directory --
if [[ ! -f "$SRC_DIR/Makefile" ]]; then
    echo "[ERROR] nv-codec-headers source not found: $SRC_DIR/Makefile"
    echo "        Clone the source:"
    echo "          git clone https://github.com/FFmpeg/nv-codec-headers $SRC_DIR"
    exit 1
fi

make install PREFIX="$PREFIX" -C "$SRC_DIR"

echo ""
echo "[OK] nv-codec-headers installed to: $PREFIX/include/ffnvcodec/"
