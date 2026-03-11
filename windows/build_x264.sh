#!/bin/bash
set -e

# -- locate script directory (follows symlinks) --
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# -- default paths (relative to script directory) --
SRC_DIR="${SCRIPT_DIR}/x264"
BUILD_DIR="${SCRIPT_DIR}/build-x264"
PREFIX=""   # set after BUILD_DIR is finalised (see below)

# -- parse command-line arguments --
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-dir)
            SRC_DIR="$2"; shift 2 ;;
        --build-dir)
            BUILD_DIR="$2"; shift 2 ;;
        --prefix)
            PREFIX="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--src-dir DIR] [--build-dir DIR] [--prefix DIR]"
            echo "  --src-dir   x264 source directory    (default: \${SCRIPT_DIR}/x264)"
            echo "  --build-dir Build output directory   (default: \${SCRIPT_DIR}/build-x264)"
            echo "  --prefix    Install prefix           (default: \${BUILD_DIR}/install)"
            exit 0 ;;
        *)
            echo "[WARN] Unknown argument: $1"; shift ;;
    esac
done

# -- use MinGW-w64 toolchain (not Cygwin GCC) --
# Required packages (install once inside any MSYS2 shell):
#   pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-make
export PATH="/mingw64/bin:$PATH"

# -- resolve PREFIX default after BUILD_DIR is known --
[[ -z "$PREFIX" ]] && PREFIX="${BUILD_DIR}/install"

echo "===== x264 build (MSYS2/MinGW-w64) ====="
echo "[INFO] Source dir  : $SRC_DIR"
echo "[INFO] Build dir   : $BUILD_DIR"
echo "[INFO] Install dir : $PREFIX"

# -- check gcc --
if ! command -v gcc &>/dev/null; then
    echo "[ERROR] gcc not found. Install the MinGW-w64 toolchain:"
    echo "  pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-make"
    exit 1
fi

echo "[INFO] Compiler    : $(gcc --version | head -1)"

# -- check nasm (required for x264 assembly optimisations) --
if ! command -v nasm &>/dev/null; then
    echo "[ERROR] nasm not found in PATH."
    echo "        Install via MSYS2:  pacman -S nasm"
    echo "        Or download from https://www.nasm.us/ and add to PATH."
    exit 1
fi

echo "[INFO] NASM        : $(nasm --version)"

# -- verify source directory --
if [[ ! -f "$SRC_DIR/configure" ]]; then
    echo "[ERROR] x264 configure not found: $SRC_DIR/configure"
    echo "        Clone the source:"
    echo "          git clone https://code.videolan.org/videolan/x264.git $SRC_DIR"
    exit 1
fi

# -- remove stale in-tree config files that block out-of-tree builds --
for f in config.h x264_config.h; do
    if [[ -f "$SRC_DIR/$f" ]]; then
        echo "[INFO] Removing stale $f from source dir ..."
        rm -f "$SRC_DIR/$f"
    fi
done

# -- create and enter the out-of-tree build directory --
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo ""
echo "[INFO] Running configure ..."
"$SRC_DIR/configure" \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-cli \
    --bit-depth=all \
    --chroma-format=all \
    --extra-cflags="-O2" \
    --extra-ldflags=""

echo ""
echo "[INFO] Building ($(nproc) jobs) ..."
make -j"$(nproc)"

echo ""
echo "[INFO] Installing ..."
make install

echo ""
echo "[OK] x264 built and installed."
echo "     Headers : ${PREFIX}/include"
echo "     Lib     : ${PREFIX}/lib"
echo "     DLL     : ${PREFIX}/bin/libx264-*.dll"
echo ""
echo "To use with FFmpeg configure, pass:"
echo "  --enable-libx264 --extra-cflags=\"-I${PREFIX}/include\" --extra-ldflags=\"-L${PREFIX}/lib\""
