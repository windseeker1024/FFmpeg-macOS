#!/bin/bash
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
    echo "        Build x264 first:  bash ${SCRIPT_DIR}/build-x264.sh"
    echo "        Or specify:        --x264-prefix /path/to/x264/install"
    exit 1
fi

echo "[INFO] x264 found  : $(ls $X264_PREFIX/bin/libx264-*.dll 2>/dev/null | head -1 || echo '(import lib only)')"

# -- verify x265 prefix --
if [[ ! -f "$X265_PREFIX/include/x265.h" ]]; then
    echo "[ERROR] x265 headers not found: $X265_PREFIX/include/x265.h"
    echo "        Build x265 first:  bash ${SCRIPT_DIR}/build-x265.sh"
    echo "        Or specify:        --x265-prefix /path/to/x265/install"
    exit 1
fi

echo "[INFO] x265 found  : $(ls $X265_PREFIX/bin/libx265*.dll 2>/dev/null | head -1 || echo '(import lib only)')"

# -- verify opus prefix --
if [[ ! -f "$OPUS_PREFIX/include/opus/opus.h" ]]; then
    echo "[ERROR] opus headers not found: $OPUS_PREFIX/include/opus/opus.h"
    echo "        Build opus first:  bash ${SCRIPT_DIR}/build-opus.sh"
    echo "        Or specify:        --opus-prefix /path/to/opus/install"
    exit 1
fi

echo "[INFO] opus found  : $(ls $OPUS_PREFIX/bin/libopus-*.dll 2>/dev/null | head -1 || echo '(import lib only)')"

# -- add x264, x265 and opus to pkg-config search path --
export PKG_CONFIG_PATH="${X264_PREFIX}/lib/pkgconfig:${X265_PREFIX}/lib/pkgconfig:${OPUS_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"

# -- create and enter the out-of-tree build directory --
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "[INFO] Running configure ..."
"$SRC_DIR/configure" \
  --prefix=$PREFIX \
  --arch=x86_64 \
  --target-os=mingw32 \
  --enable-gpl \
  --enable-version3 \
  --enable-shared \
  --disable-static \
  --disable-everything \
  --disable-doc \
  --disable-htmlpages \
  --disable-manpages \
  --disable-podpages \
  --disable-txtpages \
  --disable-debug \
  --disable-indevs \
  --disable-outdevs \
  --enable-optimizations \
  --enable-runtime-cpudetect \
  "--extra-cflags=-O2 -I${X264_PREFIX}/include -I${X265_PREFIX}/include -I${OPUS_PREFIX}/include" \
  "--extra-ldflags=-L${X264_PREFIX}/lib -L${X265_PREFIX}/lib -L${OPUS_PREFIX}/lib" \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libvpx \
  --enable-libopus \
  --enable-libmp3lame \
  --enable-libvorbis \
  --enable-nvenc \
  --enable-amf \
  --enable-mediafoundation \
  --enable-d3d11va \
  --enable-dxva2 \
  --enable-decoder=h264 \
  --enable-decoder=hevc \
  --enable-decoder=vp8 \
  --enable-decoder=vp9 \
  --enable-decoder=av1 \
  --enable-decoder=mpeg4 \
  --enable-decoder=mpeg2video \
  --enable-decoder=mpeg1video \
  --enable-decoder=mjpeg \
  --enable-decoder=png \
  --enable-decoder=gif \
  --enable-decoder=webp \
  --enable-decoder=bmp \
  --enable-decoder=tiff \
  --enable-decoder=rawvideo \
  --enable-decoder=theora \
  --enable-decoder=wmv1 \
  --enable-decoder=wmv2 \
  --enable-decoder=wmv3 \
  --enable-decoder=msmpeg4v3 \
  --enable-decoder=flv \
  --enable-decoder=h263 \
  --enable-encoder=libx264 \
  --enable-encoder=libx265 \
  --enable-encoder=libvpx_vp8 \
  --enable-encoder=libvpx_vp9 \
  --enable-encoder=libsvtav1 \
  --enable-encoder=mpeg4 \
  --enable-encoder=mpeg2video \
  --enable-encoder=mjpeg \
  --enable-encoder=png \
  --enable-encoder=gif \
  --enable-encoder=bmp \
  --enable-encoder=tiff \
  --enable-encoder=rawvideo \
  --enable-encoder=h264_amf \
  --enable-encoder=hevc_amf \
  --enable-encoder=h264_nvenc \
  --enable-encoder=hevc_nvenc \
  --enable-encoder=av1_nvenc \
  --enable-encoder=h264_qsv \
  --enable-encoder=hevc_qsv \
  --enable-decoder=aac \
  --enable-decoder=aac_latm \
  --enable-decoder=mp3 \
  --enable-decoder=mp3float \
  --enable-decoder=opus \
  --enable-decoder=vorbis \
  --enable-decoder=flac \
  --enable-decoder=alac \
  --enable-decoder=ac3 \
  --enable-decoder=eac3 \
  --enable-decoder=dca \
  --enable-decoder=truehd \
  --enable-decoder=wmav2 \
  --enable-decoder=wmapro \
  --enable-decoder=pcm_s16le \
  --enable-decoder=pcm_s24le \
  --enable-decoder=pcm_s32le \
  --enable-decoder=pcm_f32le \
  --enable-decoder=pcm_u8 \
  --enable-decoder=adpcm_ima_wav \
  --enable-decoder=adpcm_ms \
  --enable-decoder=speex \
  --enable-decoder=amrnb \
  --enable-decoder=amrwb \
  --enable-decoder=mp2 \
  --enable-decoder=mp2float \
  --enable-encoder=aac \
  --enable-encoder=libmp3lame \
  --enable-encoder=libopus \
  --enable-encoder=libvorbis \
  --enable-encoder=flac \
  --enable-encoder=alac \
  --enable-encoder=ac3 \
  --enable-encoder=eac3 \
  --enable-encoder=pcm_s16le \
  --enable-encoder=pcm_s24le \
  --enable-encoder=pcm_s32le \
  --enable-encoder=pcm_f32le \
  --enable-encoder=mp2 \
  --enable-encoder=wmav2 \
  --enable-muxer=mp4 \
  --enable-muxer=matroska \
  --enable-muxer=webm \
  --enable-muxer=avi \
  --enable-muxer=mov \
  --enable-muxer=flv \
  --enable-muxer=mpegts \
  --enable-muxer=hls \
  --enable-muxer=dash \
  --enable-muxer=mp3 \
  --enable-muxer=ogg \
  --enable-muxer=opus \
  --enable-muxer=flac \
  --enable-muxer=wav \
  --enable-muxer=adts \
  --enable-muxer=null \
  --enable-muxer=rawvideo \
  --enable-muxer=image2 \
  --enable-muxer=gif \
  --enable-muxer=mp2 \
  --enable-muxer=ac3 \
  --enable-muxer=ass \
  --enable-muxer=srt \
  --enable-muxer=webvtt \
  --enable-muxer=tee \
  --enable-muxer=segment \
  --enable-muxer=stream_segment \
  --enable-muxer=ismv \
  --enable-muxer=latm \
  --enable-muxer=nut \
  --enable-demuxer=mov \
  --enable-demuxer=matroska \
  --enable-demuxer=avi \
  --enable-demuxer=flv \
  --enable-demuxer=mpegts \
  --enable-demuxer=mpegps \
  --enable-demuxer=mp3 \
  --enable-demuxer=ogg \
  --enable-demuxer=flac \
  --enable-demuxer=wav \
  --enable-demuxer=aiff \
  --enable-demuxer=rm \
  --enable-demuxer=asf \
  --enable-demuxer=hls \
  --enable-demuxer=dash \
  --enable-demuxer=image2 \
  --enable-demuxer=gif \
  --enable-demuxer=rawvideo \
  --enable-demuxer=h264 \
  --enable-demuxer=hevc \
  --enable-demuxer=mpegvideo \
  --enable-demuxer=aac \
  --enable-demuxer=ac3 \
  --enable-demuxer=dts \
  --enable-demuxer=truehd \
  --enable-demuxer=eac3 \
  --enable-demuxer=srt \
  --enable-demuxer=ass \
  --enable-demuxer=webvtt \
  --enable-demuxer=sup \
  --enable-demuxer=concat \
  --enable-demuxer=data \
  --enable-demuxer=live_flv \
  --enable-demuxer=amr \
  --enable-demuxer=nut \
  --enable-demuxer=mjpeg \
  --enable-demuxer=loas \
  --enable-demuxer=m4v \
  --enable-demuxer=mxf \
  --enable-demuxer=vc1 \
  --enable-protocol=file \
  --enable-protocol=pipe \
  --enable-protocol=http \
  --enable-protocol=https \
  --enable-protocol=tcp \
  --enable-protocol=udp \
  --enable-protocol=rtmp \
  --enable-protocol=rtmps \
  --enable-protocol=rtp \
  --enable-protocol=hls \
  --enable-protocol=data \
  --enable-protocol=cache \
  --enable-protocol=crypto \
  --enable-protocol=tee \
  --enable-protocol=fd \
  --enable-protocol=ftp \
  --enable-protocol=concat \
  --enable-protocol=subfile \
  --enable-parser=h264 \
  --enable-parser=hevc \
  --enable-parser=av1 \
  --enable-parser=vp8 \
  --enable-parser=vp9 \
  --enable-parser=mpeg4video \
  --enable-parser=mpegvideo \
  --enable-parser=aac \
  --enable-parser=aac_latm \
  --enable-parser=mpegaudio \
  --enable-parser=opus \
  --enable-parser=vorbis \
  --enable-parser=flac \
  --enable-parser=ac3 \
  --enable-parser=dca \
  --enable-parser=png \
  --enable-parser=mjpeg \
  --enable-parser=gif \
  --enable-parser=h263 \
  --enable-parser=vc1 \
  --enable-bsf=aac_adtstoasc \
  --enable-bsf=h264_mp4toannexb \
  --enable-bsf=hevc_mp4toannexb \
  --enable-bsf=mpeg4_unpack_bframes \
  --enable-bsf=vp9_superframe \
  --enable-bsf=vp9_superframe_split \
  --enable-bsf=extract_extradata \
  --enable-bsf=dump_extradata \
  --enable-bsf=noise \
  --enable-bsf=null \
  --enable-bsf=remove_extradata \
  --enable-bsf=av1_frame_merge \
  --enable-bsf=av1_frame_split \
  --enable-bsf=av1_metadata \
  --enable-bsf=h264_metadata \
  --enable-bsf=hevc_metadata \
  --enable-bsf=opus_metadata \
  --enable-filter=scale \
  --enable-filter=crop \
  --enable-filter=pad \
  --enable-filter=trim \
  --enable-filter=overlay \
  --enable-filter=concat \
  --enable-filter=fps \
  --enable-filter=setpts \
  --enable-filter=eq \
  --enable-filter=hflip \
  --enable-filter=vflip \
  --enable-filter=rotate \
  --enable-filter=transpose \
  --enable-filter=hue \
  --enable-filter=colorchannelmixer \
  --enable-filter=curves \
  --enable-filter=unsharp \
  --enable-filter=boxblur \
  --enable-filter=noise \
  --enable-filter=yadif \
  --enable-filter=bwdif \
  --enable-filter=thumbnail \
  --enable-filter=select \
  --enable-filter=drawtext \
  --enable-filter=drawbox \
  --enable-filter=subtitles \
  --enable-filter=format \
  --enable-filter=colorspace \
  --enable-filter=split \
  --enable-filter=null \
  --enable-filter=copy \
  --enable-filter=setsar \
  --enable-filter=setdar \
  --enable-filter=setfield \
  --enable-filter=negate \
  --enable-filter=waveform \
  --enable-filter=histogram \
  --enable-filter=vectorscope \
  --enable-filter=showinfo \
  --enable-filter=signalstats \
  --enable-filter=idet \
  --enable-filter=blackdetect \
  --enable-filter=scdet \
  --enable-filter=fade \
  --enable-filter=zoompan \
  --enable-filter=hstack \
  --enable-filter=vstack \
  --enable-filter=blend \
  --enable-filter=alphaextract \
  --enable-filter=alphamerge \
  --enable-filter=premultiply \
  --enable-filter=colorkey \
  --enable-filter=chromakey \
  --enable-filter=lut \
  --enable-filter=lut3d \
  --enable-filter=hwdownload \
  --enable-filter=hwupload \
  --enable-filter=hwupload_cuda \
  --enable-filter=scale_cuda \
  --enable-filter=scale_qsv \
  --enable-filter=aresample \
  --enable-filter=atrim \
  --enable-filter=volume \
  --enable-filter=loudnorm \
  --enable-filter=dynaudnorm \
  --enable-filter=aecho \
  --enable-filter=afade \
  --enable-filter=amix \
  --enable-filter=amerge \
  --enable-filter=pan \
  --enable-filter=channelmap \
  --enable-filter=channelsplit \
  --enable-filter=aformat \
  --enable-filter=asplit \
  --enable-filter=anull \
  --enable-filter=asetpts \
  --enable-filter=adelay \
  --enable-filter=agate \
  --enable-filter=compand \
  --enable-filter=highpass \
  --enable-filter=lowpass \
  --enable-filter=equalizer \
  --enable-filter=treble \
  --enable-filter=bass \
  --enable-filter=flanger \
  --enable-filter=chorus \
  --enable-filter=silencedetect \
  --enable-filter=silenceremove \
  --enable-filter=apad \
  --enable-filter=concat \
  --enable-filter=acopy \
  --enable-filter=areverse \
  --enable-filter=atempo \
  --enable-filter=asetrate \
  --enable-filter=rubberband

echo ""
echo "[INFO] configure done. Building ..."
make -j$(nproc)

echo ""
echo "[INFO] Installing ..."
make install

echo ""
echo "===== Build successful ====="
