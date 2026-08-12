FROM debian:bookworm

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    pkg-config \
    git \
    ca-certificates \
    yasm \
    nasm \
    make \
    cmake \
    autoconf \
    automake \
    libtool \
    wget \
    xz-utils \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# Build static ARM ALSA
ARG ALSA_TAG=v1.2.14
RUN git clone --depth 1 --branch ${ALSA_TAG} https://github.com/alsa-project/alsa-lib.git /alsa-lib \
    && cd /alsa-lib \
    && autoreconf -fi \
    && ./configure \
       --host=arm-linux-gnueabihf \
       --prefix=/opt/vp \
       --enable-static \
       --disable-shared \
       --disable-python \
    && make -j$(nproc) \
    && make install

# Build static ARM FFmpeg
ARG FFMPEG_TAG=n7.1.1
RUN git clone --depth 1 --branch ${FFMPEG_TAG} https://github.com/FFmpeg/FFmpeg.git /ffmpeg \
    && cd /ffmpeg \
    && ./configure \
       --prefix=/opt/vp \
       --arch=arm \
       --target-os=linux \
       --enable-cross-compile \
       --cross-prefix=arm-linux-gnueabihf- \
       --disable-shared \
       --enable-static \
       --disable-programs \
       --disable-doc \
       --disable-debug \
       --disable-network \
       --disable-avdevice \
       --disable-postproc \
       --disable-everything \
       --enable-avformat \
       --enable-avcodec \
       --enable-avutil \
       --enable-swscale \
       --enable-swresample \
       --enable-protocol=file \
       --enable-demuxer=avi,mov,matroska,mpegvideo,mpegts,mpegps \
       --enable-parser=mpeg4video,h264,mpegaudio,aac,mpegvideo \
       --enable-decoder=mpeg4,h264,mpeg2video,mpeg1video,mp3,aac,pcm_s16le \
    && make -j$(nproc) \
    && make install

COPY . /work

RUN make clean \
    && make PREFIX=/opt/vp
