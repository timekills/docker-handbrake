#
# handbrake Dockerfile
#
# Original sourrce: https://github.com/jlesage/docker-handbrake
#

# Pull base image.
FROM jlesage/baseimage-gui:ubuntu-18.04

# Define software versions.
# NOTE: x264 version 20171224 is the most recent one that doesn't crash.
ARG HANDBRAKE_VERSION=1.2.0
ARG X264_VERSION=20171224
ARG LIBVA_VERSION=2.3.0
ARG INTEL_VAAPI_DRIVER_VERSION=2.3.0
ARG GMMLIB_VERSION=18.3.0
ARG INTEL_MEDIA_DRIVER_VERSION=18.3.0
ARG INTEL_MEDIA_SDK_VERSION=18.3.1

# Define software download URLs.
ARG HANDBRAKE_URL=https://download.handbrake.fr/releases/${HANDBRAKE_VERSION}/HandBrake-${HANDBRAKE_VERSION}-source.tar.bz2
ARG X264_URL=https://download.videolan.org/pub/videolan/x264/snapshots/x264-snapshot-${X264_VERSION}-2245-stable.tar.bz2
ARG LIBVA_URL=https://github.com/intel/libva/releases/download/2.3.0/libva-${LIBVA_VERSION}.tar.bz2
ARG INTEL_VAAPI_DRIVER_URL=https://github.com/intel/intel-vaapi-driver/releases/download/${INTEL_VAAPI_DRIVER_VERSION}/intel-vaapi-driver-${INTEL_VAAPI_DRIVER_VERSION}.tar.bz2
ARG GMMLIB_URL=https://github.com/intel/gmmlib/archive/intel-gmmlib-${GMMLIB_VERSION}.tar.gz
ARG INTEL_MEDIA_DRIVER_URL=https://github.com/intel/media-driver/archive/intel-media-${INTEL_MEDIA_DRIVER_VERSION}.tar.gz
ARG INTEL_MEDIA_SDK_URL=https://github.com/Intel-Media-SDK/MediaSDK/archive/intel-mediasdk-${INTEL_MEDIA_SDK_VERSION}.tar.gz

# Other build arguments.

# Set to 'max' to keep debug symbols.
ARG HANDBRAKE_DEBUG_MODE=none

# Define working directory.
WORKDIR /root

# Add repository for Handbrake Ubuntu.
RUN \
    apt-get update && \
    echo "Installing Ubuntu HandBrake repositories..." && \
    apt -y install software-properties-common \
   # dirmngr apt-transport-https lsb-release ca-certificates 
    && \
    add-apt-repository ppa:stebbins/handbrake-releases && \
    apt install -y ubuntu-restricted-addons && \
    apt update && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -q -y -u  -o \
    Dpkg::Options::="--force-confdef" --allow-downgrades --allow-remove-essential --allow-change-held-packages --allow-change-held-packages --allow-unauthenticated

# Define working directory.
WORKDIR /tmp

# Compile HandBrake, libva and Intel Media SDK.
RUN \
    echo "installing dependancies..." && \
    apt update && \
    apt install -y autoconf automake build-essential \
    cmake git libass-dev libbz2-dev libfontconfig1-dev libfreetype6-dev \
    libfribidi-dev libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev \
    libogg-dev libopus-dev libsamplerate-dev libspeex-dev libtheora-dev \
    libtool libtool-bin libvorbis-dev libx264-dev libxml2-dev m4 make nasm \
    patch pkg-config python tar yasm zlib1g-dev && \
    apt install -y gstreamer1.0-libav intltool libappindicator-dev \
    libdbus-glib-1-dev libglib2.0-dev libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev libgtk-3-dev libgudev-1.0-dev \
    libnotify-dev libwebkitgtk-3.0-dev && \
   # Install Intel i965 driver
    apt install -y i965-va-driver && \
   # Download patches.
    echo "Downloading patches..." && \
    mkdir HandBrake && \
    mkdir HandBrakeCLI && \
    mkdir MediaSDK && \
    #curl -# -L -o HandBrake/A00-hb-video-preset.patch https://raw.githubusercontent.com/jlesage/docker-handbrake/master/A00-hb-video-preset.patch && \
    curl -# -L -o MediaSDK/intel-media-sdk-debug-no-assert.patch https://raw.githubusercontent.com/jlesage/docker-handbrake/master/intel-media-sdk-debug-no-assert.patch && \
   # Install HandBrake.
    echo "Installing HandBrake for Ubuntu..." && \
    git clone https://github.com/HandBrake/HandBrake.git && \
    cd HandBrake && \
   # patch -p1 < A00-hb-video-preset.patch && \
    ./configure --prefix=/usr \
                --debug=$HANDBRAKE_DEBUG_MODE \
                --disable-gtk-update-checks \
                --enable-fdk-aac \
                --enable-x265 \
                --enable-qsv \
                --launch-jobs=$(nproc) \
                --launch \
                && \
    make --directory=build install && \
    # Download helper.
    echo "Downloading helpers..." && \
    curl -# -L -o /tmp/run_cmd https://raw.githubusercontent.com/jlesage/docker-mgmt-tools/master/run_cmd && \
    chmod +x /tmp/run_cmd && \
    # Compile Intel Media SDK.
    echo "Compiling Intel Media SDK..." && \
    cd MediaSDK && \
    patch -p1 < intel-media-sdk-debug-no-assert.patch && \
    mkdir build && \
    cd build && \
    if [ "${HANDBRAKE_DEBUG_MODE}" = "none" ]; then \
        INTEL_MEDIA_SDK_BUILD_TYPE=RELEASE; \
    else \
        INTEL_MEDIA_SDK_BUILD_TYPE=DEBUG; \
    fi && \
    cmake \
        -DCMAKE_BUILD_TYPE=$INTEL_MEDIA_SDK_BUILD_TYPE \
        # HandBrake's libfmx is looking at /opt/intel/mediasdk/plugins for MFX plugins.
        -DMFX_PLUGINS_DIR=/opt/intel/mediasdk/plugins \
        -DMFX_PLUGINS_CONF_DIR=/opt/intel/mediasdk/plugins \
        -DENABLE_OPENCL=OFF \
        -DENABLE_X11_DRI3=OFF \
        -DENABLE_WAYLAND=OFF \
        -DBUILD_DISPATCHER=ON \
        -DENABLE_ITT=OFF \
        -DENABLE_TEXTLOG=OFF \
        -DENABLE_STAT=OFF \
        -DBUILD_SAMPLES=OFF \
        .. && \
    make -j$(nproc) install && \
    cd .. && \
    cd .. && \
    # Strip symbols.
    if [ "${HANDBRAKE_DEBUG_MODE}" = "none" ]; then \
        find /usr/lib -type f -name "libva*.so*" -exec strip -s {} ';'; \
        find /opt/intel/mediasdk -type f -name "*.so*" -exec strip -s {} ';'; \
        strip -s /usr/bin/ghb; \
        strip -s /usr/bin/HandBrakeCLI; \
  #  fi && \
        && \
    # Cleanup.
    del-pkg build-dependencies && \
    rm -r \
        /usr/lib/libva*.la \
        /opt/intel/mediasdk/include \
        /opt/intel/mediasdk/lib64/pkgconfig \
        /opt/intel/mediasdk/lib64/*.a \
        /opt/intel/mediasdk/lib64/*.la \
        # HandBrake already include a statically-linked version of libmfx.
        /opt/intel/mediasdk/lib64/libmfx.* \
        /usr/lib/pkgconfig \
        /usr/include \
        && \
    rm -rf /tmp/* /tmp/.[!.]*

# Install dependencies.
RUN \
    apt add \
        gtk+3.0 \
        libgudev \
        dbus-glib \
        libnotify \
        libsamplerate \
        libass \
        jansson \
        xz \
        # Media codecs:
        libtheora \
        lame \
        opus \
        libvorbis \
        speex \
        # To read encrypted DVDs
        libdvdcss \
        # For main, big icons:
        librsvg \
        # For all other small icons:
        adwaita-icon-theme \
        # For optical drive listing:
        lsscsi \
        # For watchfolder
        findutils \
        expect

# Adjust the openbox config.
RUN \
    # Maximize only the main/initial window.
    sed-patch 's/<application type="normal">/<application type="normal" title="HandBrake">/' \
        /etc/xdg/openbox/rc.xml && \
    # Make sure the main window is always in the background.
    sed-patch '/<application type="normal" title="HandBrake">/a \    <layer>below</layer>' \
        /etc/xdg/openbox/rc.xml

# Generate and install favicons.
RUN \
    APP_ICON_URL=https://raw.githubusercontent.com/jlesage/docker-templates/master/jlesage/images/handbrake-icon.png && \
    install_app_icon.sh "$APP_ICON_URL"

# Add files.
COPY rootfs/ /

# Set environment variables.
ENV APP_NAME="HandBrake" \
    AUTOMATED_CONVERSION_PRESET="Very Fast 1080p30" \
    AUTOMATED_CONVERSION_FORMAT="mp4"

# Define mountable directories.
VOLUME ["/config"]
VOLUME ["/storage"]
VOLUME ["/output"]
VOLUME ["/watch"]

# Metadata.
LABEL \
      org.label-schema.name="handbrake" \
      org.label-schema.description="Docker container for HandBrake" \
      org.label-schema.version="unknown" \
      org.label-schema.vcs-url="https://github.com/timekills/docker-handbrake" \
      org.label-schema.schema-version="1.0"
