"""
Configure & Make & Install FFmpeg (two-pass cross compile for macOS, per-arch install trees).

Full pipeline example (build a universal ~/ffmpeg; macOS floor defaults to 12.0):

    # 1. Two-pass compile (arm64 -> x86_64); omit --macos-min for the 12.0
    #    default, or pass e.g. 13.0 to raise the floor.
    python3 make_compile.py --ffmpeg_dir ffmpeg-8.1.3 --target_dir ffmpeg-build --macos-min 13.0

    # 2. Merge into universal binaries with lipo.
    python3 make_universal.py --dir ffmpeg-build

    # 3. One-shot deploy: copy to ~/ffmpeg (backs up any existing install),
    #    fix install names + pkgconfig prefixes, and verify. Optional args:
    #    [source_dir] [prefix_dir] (defaults shown below).
    bash install_to_prefix.sh   # ffmpeg-build/install_universal  $HOME/ffmpeg
"""
from argparse import ArgumentParser
from multiprocessing import cpu_count
import pathlib
import subprocess
import sys
import os


def execute(command: str, check: bool = True):
    print(f"Execute: {command}.")
    result = subprocess.run(command, shell=True)
    if check and result.returncode != 0:
        sys.exit(f"Command failed (exit {result.returncode}): {command}")


if __name__ == "__main__":
    parser = ArgumentParser(description="Configure & Make & Install FFmpeg.")
    parser.add_argument("--ffmpeg_dir", type=str, default=os.getcwd(), help='indicate FFmpeg dir.')
    parser.add_argument("--target_dir", type=str, default=os.getcwd(), help='indicate target dir.')
    parser.add_argument("--macos-min", type=str, default="12.0",
                        help='minimum supported macOS version (default: 12.0); '
                             'passed as -mmacosx-version-min and MACOSX_DEPLOYMENT_TARGET.')
    args = parser.parse_args()
    ffmpeg_dir = pathlib.Path(args.ffmpeg_dir).absolute()
    target_dir = pathlib.Path(args.target_dir).absolute()
    print(f"Compile... {ffmpeg_dir}")

    # Pin the macOS floor for both slices: the env var covers configure
    # probes and make, the explicit cc flag pins compile AND link deterministically.
    os.environ["MACOSX_DEPLOYMENT_TARGET"] = args.macos_min

    def clean():
        # Best-effort: distclean implies `make clean` and fails harmlessly
        # on a pristine (never configured) tree.
        print("Clean project.")
        execute(f"cd {ffmpeg_dir} && make distclean", check=False)


    def make(arch: str):
        n_cpu = cpu_count()
        print("Configure project.")
        # --disable-ffplay keeps both passes symmetric: SDL2 from brew is
        # detected in the native arm64 pass but not in the x86_64 cross
        # pass, so without this the arm64 tree gets an ffplay the x86_64
        # tree lacks, and the universal merge has no counterpart for it.
        execute(
            f"cd {ffmpeg_dir} && ./configure --enable-cross-compile "
            f"--prefix={target_dir / ('install_' + arch + '/')} "
            f"--enable-shared --disable-static --arch={arch} "
            f"--cc='clang -arch {arch} -mmacosx-version-min={args.macos_min}' --disable-x86asm --disable-doc "
            f"--disable-ffplay "
            f"--disable-devices --disable-xlib --disable-libxcb "
            f"--enable-videotoolbox --enable-audiotoolbox"
        )
        print(f"Make project ({n_cpu} threads).")
        execute(f"cd {ffmpeg_dir} && make -j{n_cpu}")
        print(f"Install project.")
        execute(f"cd {ffmpeg_dir} && make install")


    print("----------arm64----------")
    clean()
    make("arm64")
    print("----------x86_64----------")
    clean()
    make("x86_64")
