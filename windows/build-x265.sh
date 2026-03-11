#!/bin/bash
set -e

# -- locate script directory (follows symlinks) --
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# -- default paths (relative to script directory) --
SRC_DIR="${SCRIPT_DIR}/x265"
BUILD_DIR="${SCRIPT_DIR}/build-x265"
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
            echo "  --src-dir   x265 source directory  (default: \${SCRIPT_DIR}/x265)"
            echo "  --build-dir Build output directory  (default: \${SCRIPT_DIR}/build-x265)"
            echo "  --prefix    Install prefix          (default: \${BUILD_DIR}/install)"
            exit 0 ;;
        *)
            echo "[WARN] Unknown argument: $1"; shift ;;
    esac
done

# -- resolve PREFIX default after BUILD_DIR is known --
[[ -z "$PREFIX" ]] && PREFIX="${BUILD_DIR}/install"

# -- use MinGW-w64 toolchain (not Cygwin GCC) --
# Required packages (install once inside any MSYS2 shell):
#   pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-make
#   pacman -S --needed mingw-w64-x86_64-cmake
export PATH="/mingw64/bin:$PATH"

echo "===== x265 build (MSYS2/MinGW-w64) ====="
echo "[INFO] Source dir  : ${SRC_DIR}/source"
echo "[INFO] Build dir   : $BUILD_DIR"
echo "[INFO] Install dir : $PREFIX"

# -- check gcc --
if ! command -v gcc &>/dev/null; then
    echo "[ERROR] gcc not found. Install the MinGW-w64 toolchain:"
    echo "  pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-make"
    exit 1
fi

echo "[INFO] Compiler : $(gcc --version | head -1)"

# -- check cmake --
if ! command -v cmake &>/dev/null; then
    echo "[ERROR] cmake not found. Install it:"
    echo "  pacman -S --needed mingw-w64-x86_64-cmake"
    exit 1
fi

echo "[INFO] CMake    : $(cmake --version | head -1)"

# -- verify source directory --
if [[ ! -f "${SRC_DIR}/source/CMakeLists.txt" ]]; then
    echo "[ERROR] x265 source not found: ${SRC_DIR}/source/CMakeLists.txt"
    echo "        Clone x265: git clone https://bitbucket.org/multicoreware/x265_git x265"
    exit 1
fi

# -- create and enter the out-of-tree build directory --
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "[INFO] Running cmake ..."
cmake -G "MSYS Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DENABLE_SHARED=ON \
    -DENABLE_CLI=OFF \
    -DENABLE_STATIC_LINKING=OFF \
    "${SRC_DIR}/source"

echo ""
echo "[INFO] Building ..."
make -j$(nproc)

echo ""
echo "[INFO] Installing ..."
make install

echo ""
echo "===== x265 build successful ====="
echo "[INFO] Installed to: $PREFIX"
