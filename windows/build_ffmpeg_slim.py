#!/usr/bin/env python3
r"""
FFmpeg slim build script (Windows, MSYS2 + MinGW-w64)
Only keeps common codecs, muxers, filters and protocols to reduce binary size.

Requirements:
  - MSYS2 (https://www.msys2.org/), default install path C:\msys64
  - Inside any MSYS2 shell, install the MinGW-w64 toolchain once:
      pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-make
  - Additional build tools:
      pacman -S --needed yasm diffutils make pkg-config

Usage:
  python build_ffmpeg_slim.py              # generate scripts only, do not build
  python build_ffmpeg_slim.py --run        # generate and run inside MSYS2
  python build_ffmpeg_slim.py --list       # list all enabled components
  python build_ffmpeg_slim.py --run --src-dir C:\ffmpeg_src --build-dir C:\ffmpeg_out
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# Components to enable (everything is disabled first via --disable-everything)
# ─────────────────────────────────────────────────────────────────────────────

# Video decoders
VIDEO_DECODERS = [
    "h264",          # AVC / H.264
    "hevc",          # HEVC / H.265
    "vp8",           # VP8 (WebM)
    "vp9",           # VP9 (WebM/YouTube)
    "av1",           # AV1
    "mpeg4",         # MPEG-4 Part 2 (DivX/Xvid)
    "mpeg2video",    # MPEG-2 Video (DVD/broadcast)
    "mpeg1video",    # MPEG-1 Video
    "mjpeg",         # Motion JPEG
    "png",           # PNG (video stream)
    "gif",           # GIF
    "webp",          # WebP
    "bmp",           # BMP
    "tiff",          # TIFF
    "rawvideo",      # Raw video
    "theora",        # Theora (OGV)
    "wmv1",          # Windows Media Video 7
    "wmv2",          # Windows Media Video 8
    "wmv3",          # Windows Media Video 9
    "msmpeg4v3",     # MS MPEG-4 v3 (legacy AVI)
    "flv",           # Sorenson Spark (FLV)
    "h263",          # H.263
]

# Video encoders
VIDEO_ENCODERS = [
    "libx264",       # H.264 (requires --enable-libx264)
    "libx265",       # H.265 (requires --enable-libx265)
    "libvpx_vp8",    # VP8 (requires --enable-libvpx)
    "libvpx_vp9",    # VP9 (requires --enable-libvpx)
    "libsvtav1",     # AV1 (requires --enable-libsvtav1)
    "mpeg4",         # MPEG-4 Part 2
    "mpeg2video",    # MPEG-2 Video
    "mjpeg",         # Motion JPEG
    "png",           # PNG
    "gif",           # GIF
    "bmp",           # BMP
    "tiff",          # TIFF
    "rawvideo",      # Raw video
    "h264_amf",      # AMD AMF H.264 hardware encoder
    "hevc_amf",      # AMD AMF HEVC hardware encoder
    "h264_nvenc",    # NVIDIA NVENC H.264
    "hevc_nvenc",    # NVIDIA NVENC HEVC
    "av1_nvenc",     # NVIDIA NVENC AV1
    "h264_qsv",      # Intel QSV H.264
    "hevc_qsv",      # Intel QSV HEVC
]

# Audio decoders
AUDIO_DECODERS = [
    "aac",           # AAC
    "aac_latm",      # AAC LATM
    "mp3",           # MP3
    "mp3float",      # MP3 (float)
    "opus",          # Opus (WebM/Discord)
    "vorbis",        # Vorbis (OGG)
    "flac",          # FLAC lossless
    "alac",          # Apple ALAC lossless
    "ac3",           # Dolby AC-3
    "eac3",          # Dolby E-AC-3 (Dolby Digital Plus)
    "dca",           # DTS
    "truehd",        # Dolby TrueHD
    "wmav2",         # Windows Media Audio v2
    "wmapro",        # Windows Media Audio Pro
    "pcm_s16le",     # PCM 16-bit LE (WAV)
    "pcm_s24le",     # PCM 24-bit LE
    "pcm_s32le",     # PCM 32-bit LE
    "pcm_f32le",     # PCM 32-bit float LE
    "pcm_u8",        # PCM unsigned 8-bit
    "adpcm_ima_wav", # ADPCM IMA WAV
    "adpcm_ms",      # ADPCM Microsoft
    "speex",         # Speex
    "amrnb",         # AMR-NB (mobile voice)
    "amrwb",         # AMR-WB
    "mp2",           # MP2
    "mp2float",      # MP2 (float)
]

# Audio encoders
AUDIO_ENCODERS = [
    "aac",           # AAC (built-in)
    "libmp3lame",    # MP3 (requires --enable-libmp3lame)
    "libopus",       # Opus (requires --enable-libopus)
    "libvorbis",     # Vorbis (requires --enable-libvorbis)
    "flac",          # FLAC
    "alac",          # ALAC
    "ac3",           # AC-3
    "eac3",          # E-AC-3
    "pcm_s16le",     # PCM 16-bit LE
    "pcm_s24le",     # PCM 24-bit LE
    "pcm_s32le",     # PCM 32-bit LE
    "pcm_f32le",     # PCM 32-bit float LE
    "mp2",           # MP2
    "wmav2",         # Windows Media Audio v2
]

# Muxers (output containers)
MUXERS = [
    "mp4",           # MP4
    "matroska",      # MKV
    "webm",          # WebM
    "avi",           # AVI
    "mov",           # QuickTime MOV
    "flv",           # FLV
    "mpegts",        # MPEG-TS (live/broadcast)
    "hls",           # HLS (HTTP Live Streaming)
    "dash",          # MPEG-DASH
    "mp3",           # MP3
    "ogg",           # OGG
    "opus",          # Opus
    "flac",          # FLAC
    "wav",           # WAV
    "adts",          # AAC ADTS (raw stream)
    "null",          # Null (testing/discard)
    "rawvideo",      # Raw video
    "image2",        # Image sequence
    "gif",           # GIF
    "mp2",           # MP2
    "ac3",           # AC-3
    "ass",           # ASS subtitles
    "srt",           # SRT subtitles
    "webvtt",        # WebVTT subtitles
    "tee",           # Tee (multi-output)
    "segment",       # Segment output
    "stream_segment",
    "ismv",          # Smooth Streaming (IIS)
    "latm",          # LATM
    "nut",           # NUT
]

# Demuxers (input containers)
DEMUXERS = [
    "mov",           # MP4 / M4A / MOV / QuickTime
    "matroska",      # MKV / WebM
    "avi",           # AVI
    "flv",           # FLV
    "mpegts",        # MPEG-TS
    "mpegps",        # MPEG PS (DVD VOB)
    "mp3",           # MP3
    "ogg",           # OGG
    "flac",          # FLAC
    "wav",           # WAV
    "aiff",          # AIFF
    "rm",            # RealMedia
    "asf",           # ASF / WMV / WMA
    "hls",           # HLS (M3U8)
    "dash",          # DASH
    "image2",        # Image sequence
    "gif",           # GIF
    "rawvideo",      # Raw video
    "h264",          # H.264 raw stream
    "hevc",          # HEVC raw stream
    "mpegvideo",     # MPEG-ES
    "aac",           # AAC
    "ac3",           # AC-3
    "dts",           # DTS
    "truehd",        # TrueHD
    "eac3",          # E-AC-3
    "srt",           # SRT subtitles
    "ass",           # ASS subtitles
    "webvtt",        # WebVTT subtitles
    "sup",           # PGS subtitles
    "concat",        # File list
    "data",          # Generic data stream
    "live_flv",      # Live FLV
    "amr",           # AMR
    "nut",           # NUT
    "mjpeg",         # MJPEG
    "loas",          # LATM/LOAS
    "m4v",           # M4V
    "mxf",           # MXF (broadcast)
    "vc1",           # VC-1
]

# Protocols
PROTOCOLS = [
    "file",          # Local file
    "pipe",          # Pipe
    "http",          # HTTP
    "https",         # HTTPS
    "tcp",           # TCP raw stream
    "udp",           # UDP raw stream
    "rtmp",          # RTMP (live push)
    "rtmps",         # RTMPS
    "rtp",           # RTP
    "hls",           # HLS
    "data",          # Data URI
    "cache",         # Local cache
    "crypto",        # AES encryption
    "tee",           # Tee protocol
    "fd",            # File descriptor
    "ftp",           # FTP
    "concat",        # File concatenation
    "subfile",       # Sub-file range
]

# Parsers (stream analysis)
PARSERS = [
    "h264",
    "hevc",
    "av1",
    "vp8",
    "vp9",
    "mpeg4video",
    "mpegvideo",
    "aac",
    "aac_latm",
    "mpegaudio",
    "opus",
    "vorbis",
    "flac",
    "ac3",
    "dca",
    "png",
    "mjpeg",
    "gif",
    "h263",
    "vc1",
]

# Bitstream filters (BSF)
BSFS = [
    "aac_adtstoasc",     # ADTS -> MPEG-4 ASC (required for MP4 muxing)
    "h264_mp4toannexb",  # H.264 MP4 -> Annex B (required for TS muxing)
    "hevc_mp4toannexb",  # HEVC MP4 -> Annex B
    "mpeg4_unpack_bframes",
    "vp9_superframe",
    "vp9_superframe_split",
    "extract_extradata",
    "dump_extradata",
    "noise",
    "null",
    "remove_extradata",
    "av1_frame_merge",
    "av1_frame_split",
    "av1_metadata",
    "h264_metadata",
    "hevc_metadata",
    "opus_metadata",
]

# Common video filters
VIDEO_FILTERS = [
    "scale",         # Resize
    "crop",          # Crop
    "pad",           # Pad with black borders
    "trim",          # Trim by time
    "overlay",       # Overlay / watermark
    "concat",        # Concatenate
    "fps",           # Force frame rate
    "setpts",        # Modify timestamps
    "eq",            # Brightness/contrast/saturation
    "hflip",         # Horizontal flip
    "vflip",         # Vertical flip
    "rotate",        # Rotate
    "transpose",     # Transpose (rotate 90 deg)
    "hue",           # Hue
    "colorchannelmixer",
    "curves",        # Color curves
    "unsharp",       # Sharpen/blur
    "boxblur",       # Box blur
    "noise",         # Add noise
    "yadif",         # Yet Another Deinterlacing Filter
    "bwdif",         # Bob Weave Deinterlacing Filter
    "thumbnail",     # Thumbnail
    "select",        # Frame select
    "drawtext",      # Text overlay (requires --enable-libfreetype)
    "drawbox",       # Draw rectangle
    "subtitles",     # Subtitle rendering (requires --enable-libass)
    "format",        # Pixel format conversion
    "colorspace",    # Color space conversion
    "split",         # Split stream
    "null",          # Pass-through
    "copy",          # Copy frame
    "setsar",        # Set SAR
    "setdar",        # Set DAR
    "setfield",
    "negate",        # Negate colors
    "waveform",
    "histogram",
    "vectorscope",
    "showinfo",      # Frame info
    "signalstats",
    "idet",          # Interlace detection
    "blackdetect",   # Black frame detection
    "scdet",         # Scene change detection
    "fade",          # Fade in/out
    "zoompan",       # Zoom and pan
    "hstack",
    "vstack",
    "blend",         # Blend
    "alphaextract",
    "alphamerge",
    "premultiply",
    "colorkey",      # Color key (green screen)
    "chromakey",     # Chroma key
    "lut",           # Lookup table
    "lut3d",         # 3D LUT (color grading)
    "hwdownload",    # GPU -> CPU
    "hwupload",      # CPU -> GPU
    "hwupload_cuda", # CUDA upload
    "scale_cuda",    # CUDA scale
    "scale_qsv",     # QSV scale
]

# Common audio filters
AUDIO_FILTERS = [
    "aresample",     # Resample
    "atrim",         # Trim by time
    "volume",        # Volume
    "loudnorm",      # Loudness normalization
    "dynaudnorm",    # Dynamic loudness normalization
    "aecho",         # Echo
    "afade",         # Fade in/out
    "amix",          # Mix audio streams
    "amerge",        # Merge channels
    "pan",           # Channel routing
    "channelmap",    # Channel map
    "channelsplit",  # Split channels
    "aformat",       # Audio format conversion
    "asplit",        # Split audio stream
    "anull",         # Pass-through
    "asetpts",       # Modify timestamps
    "adelay",        # Delay
    "agate",         # Noise gate
    "compand",       # Compand (compress/expand)
    "highpass",      # High-pass filter
    "lowpass",       # Low-pass filter
    "equalizer",     # Equalizer
    "treble",        # Treble
    "bass",          # Bass
    "flanger",       # Flanger
    "chorus",        # Chorus
    "silencedetect", # Silence detection
    "silenceremove", # Silence removal
    "apad",          # Pad with silence
    "concat",        # Concatenate audio
    "acopy",         # Copy
    "areverse",      # Reverse playback
    "atempo",        # Time-stretch (pitch-preserved)
    "asetrate",      # Set sample rate
    "rubberband",    # High-quality time-stretch/pitch (requires --enable-librubberband)
]

# ─────────────────────────────────────────────────────────────────────────────
# Third-party library switches (set True/False based on what you have installed)
# ─────────────────────────────────────────────────────────────────────────────
THIRD_PARTY_LIBS = {
    # Codec libraries
    "libx264":         True,   # H.264 encoding (GPL)
    "libx265":         True,   # H.265 encoding (GPL)
    "libvpx":          True,   # VP8/VP9 encoding
    "libopus":         True,   # Opus encoding
    "libmp3lame":      True,   # MP3 encoding
    "libvorbis":       True,   # Vorbis encoding
    "libsvtav1":       False,  # AV1 encoding (large, optional)
    # Subtitle / font rendering
    "libass":          False,  # ASS subtitle rendering
    "libfreetype":     False,  # Required for drawtext filter
    "libfontconfig":   False,
    # Network / TLS
    "openssl":         False,  # HTTPS (use schannel on Windows instead)
    "gnutls":          False,  # HTTPS alternative
    # Hardware acceleration
    "nvenc":           True,   # NVIDIA hardware encoding (needs CUDA SDK headers)
    "amf":             True,   # AMD AMF hardware encoding
    "mediafoundation": True,   # Windows Media Foundation
    "d3d11va":         True,   # DirectX 11 hardware decoding
    "dxva2":           True,   # DirectX 9 hardware decoding
}

# ─────────────────────────────────────────────────────────────────────────────
# Build configuration
# ─────────────────────────────────────────────────────────────────────────────

def build_configure_args() -> list[str]:
    args = ["./configure"]

    # -- install prefix (resolved at runtime by the $PREFIX shell variable) --
    args += ["--prefix=$PREFIX"]

    # -- target architecture --
    args += [
        "--arch=x86_64",
        "--target-os=mingw32",
    ]

    # -- License (libx264/265 require GPL) --
    if THIRD_PARTY_LIBS.get("libx264") or THIRD_PARTY_LIBS.get("libx265"):
        args += ["--enable-gpl", "--enable-version3"]
    else:
        args += ["--enable-lgpl"]

    # -- shared / static --
    args += ["--enable-shared", "--disable-static"]

    # -- disable everything, then selectively enable --
    args += ["--disable-everything"]

    # -- disable unneeded large modules --
    args += [
        "--disable-doc",
        "--disable-htmlpages",
        "--disable-manpages",
        "--disable-podpages",
        "--disable-txtpages",
        "--disable-debug",
        "--disable-indevs",
        "--disable-outdevs",
        "--enable-optimizations",
        "--enable-runtime-cpudetect",
        '"--extra-cflags=-O2 -I${X264_PREFIX}/include -I${X265_PREFIX}/include -I${OPUS_PREFIX}/include"',
        '"--extra-ldflags=-L${X264_PREFIX}/lib -L${X265_PREFIX}/lib -L${OPUS_PREFIX}/lib"',
    ]

    # -- NASM is auto-detected; no --enable-nasm needed --

    # -- third-party libraries --
    for lib, enabled in THIRD_PARTY_LIBS.items():
        if enabled:
            args.append(f"--enable-{lib}")

    # -- components --
    for dec in VIDEO_DECODERS:
        args.append(f"--enable-decoder={dec}")
    for enc in VIDEO_ENCODERS:
        args.append(f"--enable-encoder={enc}")
    for dec in AUDIO_DECODERS:
        args.append(f"--enable-decoder={dec}")
    for enc in AUDIO_ENCODERS:
        args.append(f"--enable-encoder={enc}")
    for mux in MUXERS:
        args.append(f"--enable-muxer={mux}")
    for demux in DEMUXERS:
        args.append(f"--enable-demuxer={demux}")
    for proto in PROTOCOLS:
        args.append(f"--enable-protocol={proto}")
    for parser in PARSERS:
        args.append(f"--enable-parser={parser}")
    for bsf in BSFS:
        args.append(f"--enable-bsf={bsf}")
    for flt in VIDEO_FILTERS:
        args.append(f"--enable-filter={flt}")
    for flt in AUDIO_FILTERS:
        args.append(f"--enable-filter={flt}")

    return args


def find_msys2() -> Path:
    """Find the MSYS2 installation path."""
    candidates = [
        Path(r"C:\msys64"),
        Path(r"C:\msys32"),
        Path(r"D:\msys64"),
        Path(os.environ.get("MSYS2_PATH", "C:\\msys64")),
    ]
    for p in candidates:
        if (p / "usr" / "bin" / "bash.exe").exists():
            return p
    return None



def generate_msys2_script(configure_args: list[str]) -> str:
    """Generate the MSYS2 shell script with runtime --src-dir / --build-dir / --prefix support."""
    # Replace "./configure" with "$SRC_DIR/configure"
    conf_args = list(configure_args)
    conf_args[0] = '"$SRC_DIR/configure"'
    cmd_line = " \\\n  ".join(conf_args)

    script = r"""#!/bin/bash
set -e

# -- locate script directory (follows symlinks) --
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# -- default paths (relative to script directory) --
SRC_DIR="${SCRIPT_DIR}/ffmpeg"
BUILD_DIR="${SCRIPT_DIR}/build-ffmpeg"
PREFIX=""   # set after BUILD_DIR is finalised (see below)
X264_PREFIX="${SCRIPT_DIR}/build-x264/install"  # default: sibling build-x264/install
X265_PREFIX="${SCRIPT_DIR}/build-x265/install"  # default: sibling build-x265/install
OPUS_PREFIX="${SCRIPT_DIR}/build-opus/install"  # default: sibling build-opus/install

# -- parse command-line arguments --
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-dir)
            SRC_DIR="$2"; shift 2 ;;
        --build-dir)
            BUILD_DIR="$2"; shift 2 ;;
        --prefix)
            PREFIX="$2"; shift 2 ;;
        --x264-prefix)
            X264_PREFIX="$2"; shift 2 ;;
        --x265-prefix)
            X265_PREFIX="$2"; shift 2 ;;
        --opus-prefix)
            OPUS_PREFIX="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--src-dir DIR] [--build-dir DIR] [--prefix DIR] [--x264-prefix DIR] [--x265-prefix DIR] [--opus-prefix DIR]"
            echo "  --src-dir      FFmpeg source directory  (default: \${SCRIPT_DIR}/ffmpeg)"
            echo "  --build-dir    Build output directory   (default: \${SCRIPT_DIR}/build-ffmpeg)"
            echo "  --prefix       Install prefix           (default: \${BUILD_DIR}/install)"
            echo "  --x264-prefix  x264 install prefix      (default: \${SCRIPT_DIR}/build-x264/install)"
            echo "  --x265-prefix  x265 install prefix      (default: \${SCRIPT_DIR}/build-x265/install)"
            echo "  --opus-prefix  opus install prefix      (default: \${SCRIPT_DIR}/build-opus/install)"
            exit 0 ;;
        *)
            echo "[WARN] Unknown argument: $1"; shift ;;
    esac
done

# -- resolve PREFIX default after BUILD_DIR is known --
[[ -z "$PREFIX" ]] && PREFIX="${BUILD_DIR}/install"

# -- use MinGW-w64 toolchain (not Cygwin GCC) --
# Required packages (install once inside any MSYS2 shell):
#   pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-make
#   pacman -S --needed mingw-w64-x86_64-pkg-config
# Third-party libraries used by this build:
#   pacman -S --needed mingw-w64-x86_64-lame        # libmp3lame  (--enable-libmp3lame)
#   pacman -S --needed mingw-w64-x86_64-libvpx      # libvpx      (--enable-libvpx)
#   pacman -S --needed mingw-w64-x86_64-libvorbis   # libvorbis   (--enable-libvorbis)
#   pacman -S --needed mingw-w64-x86_64-amf-headers # AMD AMF     (--enable-amf)
# Hardware encoding SDK headers (headers only, no runtime needed):
#   make install PREFIX=/mingw64 -C /c/ffmpeg-build/nv-codec-headers  # NVENC (--enable-nvenc)
# (x264 is built separately via build-x264.sh)
# (x265 is built separately via build-x265.sh)
# (opus is built separately via build-opus.sh)
export PATH="/mingw64/bin:$PATH"

""" + f"""
echo "===== FFmpeg slim build (MSYS2/MinGW-w64) ====="
echo "[INFO] Source dir  : $SRC_DIR"
echo "[INFO] Build dir   : $BUILD_DIR"
echo "[INFO] Install dir : $PREFIX"
echo "[INFO] x264 prefix : $X264_PREFIX"
echo "[INFO] x265 prefix : $X265_PREFIX"
echo "[INFO] opus prefix : $OPUS_PREFIX"

# -- check gcc --
if ! command -v gcc &>/dev/null; then
    echo "[ERROR] gcc not found. Install the MinGW-w64 toolchain:"
    echo "  pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-make"
    exit 1
fi

echo "[INFO] Compiler : $(gcc --version | head -1)"

# -- verify source directory --
if [[ ! -f "$SRC_DIR/configure" ]]; then
    echo "[ERROR] FFmpeg source not found: $SRC_DIR/configure"
    exit 1
fi

# -- verify x264 prefix --
if [[ ! -f "$X264_PREFIX/include/x264.h" ]]; then
    echo "[ERROR] x264 headers not found: $X264_PREFIX/include/x264.h"
    echo "        Build x264 first:  bash ${{SCRIPT_DIR}}/build-x264.sh"
    echo "        Or specify:        --x264-prefix /path/to/x264/install"
    exit 1
fi

echo "[INFO] x264 found  : $(ls $X264_PREFIX/bin/libx264-*.dll 2>/dev/null | head -1 || echo '(import lib only)')"

# -- verify x265 prefix --
if [[ ! -f "$X265_PREFIX/include/x265.h" ]]; then
    echo "[ERROR] x265 headers not found: $X265_PREFIX/include/x265.h"
    echo "        Build x265 first:  bash ${{SCRIPT_DIR}}/build-x265.sh"
    echo "        Or specify:        --x265-prefix /path/to/x265/install"
    exit 1
fi

echo "[INFO] x265 found  : $(ls $X265_PREFIX/bin/libx265*.dll 2>/dev/null | head -1 || echo '(import lib only)')"

# -- verify opus prefix --
if [[ ! -f "$OPUS_PREFIX/include/opus/opus.h" ]]; then
    echo "[ERROR] opus headers not found: $OPUS_PREFIX/include/opus/opus.h"
    echo "        Build opus first:  bash ${{SCRIPT_DIR}}/build-opus.sh"
    echo "        Or specify:        --opus-prefix /path/to/opus/install"
    exit 1
fi

echo "[INFO] opus found  : $(ls $OPUS_PREFIX/bin/libopus-*.dll 2>/dev/null | head -1 || echo '(import lib only)')"

# -- add x264, x265 and opus to pkg-config search path --
export PKG_CONFIG_PATH="${{X264_PREFIX}}/lib/pkgconfig:${{X265_PREFIX}}/lib/pkgconfig:${{OPUS_PREFIX}}/lib/pkgconfig:${{PKG_CONFIG_PATH}}"

# -- create and enter the out-of-tree build directory --
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "[INFO] Running configure ..."
{cmd_line}

echo ""
echo "[INFO] configure done. Building ..."
make -j$(nproc)

echo ""
echo "[INFO] Installing ..."
make install

echo ""
echo "===== Build successful ====="
"""
    return script


def print_component_summary():
    """Print a summary of enabled components."""
    print("\n" + "=" * 60)
    print("  Enabled components")
    print("=" * 60)
    print(f"  Video decoders : {len(VIDEO_DECODERS)}")
    print(f"  Video encoders : {len(VIDEO_ENCODERS)}")
    print(f"  Audio decoders : {len(AUDIO_DECODERS)}")
    print(f"  Audio encoders : {len(AUDIO_ENCODERS)}")
    print(f"  Muxers         : {len(MUXERS)}")
    print(f"  Demuxers       : {len(DEMUXERS)}")
    print(f"  Protocols      : {len(PROTOCOLS)}")
    print(f"  Parsers        : {len(PARSERS)}")
    print(f"  BSFs           : {len(BSFS)}")
    print(f"  Video filters  : {len(VIDEO_FILTERS)}")
    print(f"  Audio filters  : {len(AUDIO_FILTERS)}")
    print("=" * 60)
    enabled_libs = [k for k, v in THIRD_PARTY_LIBS.items() if v]
    print(f"  Third-party libs enabled: {', '.join(enabled_libs) or 'none'}")
    print("=" * 60 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Generate FFmpeg slim build configuration (Windows, MSYS2/MinGW-w64)"
    )
    parser.add_argument(
        "--run", action="store_true",
        help="run the build inside MSYS2 automatically (requires MSYS2)",
    )
    parser.add_argument(
        "--list", action="store_true",
        help="list all enabled components",
    )
    _here = Path(__file__).resolve().parent
    parser.add_argument(
        "--build-dir", default=str(_here / "build-ffmpeg"),
        help=r"build output directory (Windows path, default: <script dir>\build-ffmpeg)",
    )
    parser.add_argument(
        "--src-dir", default=str(_here / "ffmpeg"),
        help=r"FFmpeg source directory (Windows path, default: <script dir>\ffmpeg)",
    )
    args = parser.parse_args()

    if args.list:
        print_component_summary()
        print("--- Video decoders ---")
        for x in VIDEO_DECODERS:   print(f"  {x}")
        print("--- Video encoders ---")
        for x in VIDEO_ENCODERS:   print(f"  {x}")
        print("--- Audio decoders ---")
        for x in AUDIO_DECODERS:   print(f"  {x}")
        print("--- Audio encoders ---")
        for x in AUDIO_ENCODERS:   print(f"  {x}")
        print("--- Muxers ---")
        for x in MUXERS:           print(f"  {x}")
        print("--- Demuxers ---")
        for x in DEMUXERS:         print(f"  {x}")
        print("--- Protocols ---")
        for x in PROTOCOLS:        print(f"  {x}")
        print("--- Video filters ---")
        for x in VIDEO_FILTERS:    print(f"  {x}")
        print("--- Audio filters ---")
        for x in AUDIO_FILTERS:    print(f"  {x}")
        return

    _here = Path(__file__).resolve().parent
    configure_args = build_configure_args()
    build_script   = generate_msys2_script(configure_args)

    # Write the shell script next to build_slim.py
    script_path = _here / "build_ffmpeg.sh"
    script_path.write_text(build_script, encoding="utf-8", newline="\n")
    print(f"[OK] Shell script written : {script_path}")

    # Write the full configure argument list for inspection
    cmd_path = _here / "configure_cmd.txt"
    cmd_path.write_text("\n".join(configure_args), encoding="utf-8")
    print(f"[OK] Configure args saved : {cmd_path}")

    print_component_summary()

    print("Generated configure command (first 20 lines):")
    print("-" * 60)
    for line in configure_args[:20]:
        print(f"  {line}")
    if len(configure_args) > 20:
        print(f"  ... {len(configure_args)} args total (see configure_cmd.txt)")
    print("-" * 60)

    if args.run:
        msys2 = find_msys2()
        if not msys2:
            print("\n[ERROR] MSYS2 not found. Install MSYS2 or run build_ffmpeg.sh manually.")
            sys.exit(1)

        bash = msys2 / "usr" / "bin" / "bash.exe"

        # Convert Windows path to MSYS2 path
        def _win_to_msys(p: str) -> str:
            p = p.replace("\\", "/")
            if len(p) >= 2 and p[1] == ":":
                p = f"/{p[0].lower()}{p[2:]}"
            return p

        msys2_script  = _win_to_msys(str(script_path))
        msys2_src_dir = _win_to_msys(args.src_dir)
        msys2_bld_dir = _win_to_msys(args.build_dir)
        # Leave prefix empty so the sh script defaults to ${BUILD_DIR}/install
        msys2_prefix  = getattr(args, 'prefix', '')

        print(f"\n[INFO] MSYS2 path    : {msys2}")
        print(f"[INFO] Script        : {msys2_script}")
        print(f"[INFO] Source dir    : {msys2_src_dir}")
        print(f"[INFO] Build dir     : {msys2_bld_dir}")
        print(f"[INFO] Install dir   : {msys2_prefix or msys2_bld_dir + '/install'}")
        run_args = [str(bash), "--login", msys2_script,
                    "--src-dir", msys2_src_dir,
                    "--build-dir", msys2_bld_dir]
        if msys2_prefix:
            run_args += ["--prefix", msys2_prefix]
        result = subprocess.run(
            run_args,
            env={**os.environ, "MSYS2_PATH_TYPE": "inherit"},
        )
        sys.exit(result.returncode)
    else:
        print("\nHow to build:")
        print("  1. Open MSYS2 MinGW x64 shell (or UCRT64 shell)")
        print("  2. Run the generated script (uses default paths):")
        print("       bash /c/ffmpeg-build/build_ffmpeg.sh")
        print()
        print("  Optionally specify source, build, and install directories:")
        print("       bash /c/ffmpeg-build/build_ffmpeg.sh --src-dir /c/my/ffmpeg --build-dir /c/my/build")
        print("       bash /c/ffmpeg-build/build_ffmpeg.sh --src-dir /c/my/ffmpeg --build-dir /c/my/build --prefix /c/my/install")
        print()
        print("  Or use --run to build automatically:")
        print("       python build_ffmpeg_slim.py --run")
        print(f"       python build_ffmpeg_slim.py --run --src-dir {args.src_dir} --build-dir {args.build_dir}")


if __name__ == "__main__":
    main()
