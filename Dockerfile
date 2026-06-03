# Stage 1: Base image with apt packages
FROM ghcr.io/linuxserver/baseimage-kasmvnc:debianbullseye-8446af38-ls104 AS base

ENV TITLE=MetaTrader
ENV WINEARCH=win64
ENV WINEPREFIX="/config/.wine"
ENV DISPLAY=:0
ENV XDG_RUNTIME_DIR=/tmp/runtime-abc

# Ensure the directory exists with correct permissions
RUN mkdir -p /config/.wine && \
    mkdir -p /tmp/runtime-abc && \
    chown -R abc:abc /config/.wine /tmp/runtime-abc && \
    chmod -R 755 /config/.wine /tmp/runtime-abc

# Disable broken/stale apt sources bundled in the base image (backports, nodesource)
RUN sed -i 's/^[^#].*bullseye-backports/#&/' /etc/apt/sources.list 2>/dev/null || true && \
    find /etc/apt/sources.list.d/ -type f -exec sed -i 's/^[^#].*bullseye-backports/#&/' {} \; 2>/dev/null || true && \
    find /etc/apt/sources.list.d/ -type f -exec sed -i '/nodesource/s/^/#/' {} \; 2>/dev/null || true && \
    rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null || true && \
    apt-get update && \
    apt-get upgrade -y

# Install required packages
RUN apt-get install -y \
    dos2unix \
    python3-pip \
    wget \
    python3-pyxdg \
    netcat \
    unzip \
    && pip3 install --upgrade pip

# Add WineHQ repository key and APT source
RUN wget -q https://dl.winehq.org/wine-builds/winehq.key > /dev/null 2>&1\
    && apt-key add winehq.key \
    && add-apt-repository 'deb https://dl.winehq.org/wine-builds/debian/ bullseye main' \
    && rm winehq.key

# Add i386 architecture and update package lists
RUN dpkg --add-architecture i386 \
    && sed -i 's/^[^#].*bullseye-backports/#&/' /etc/apt/sources.list 2>/dev/null || true && \
    find /etc/apt/sources.list.d/ -type f -exec sed -i 's/^[^#].*bullseye-backports/#&/' {} \; 2>/dev/null || true && \
    find /etc/apt/sources.list.d/ -type f -exec sed -i '/nodesource/s/^/#/' {} \; 2>/dev/null || true && \
    rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null || true && \
    apt-get update

# Install WineHQ stable package and dependencies
RUN apt-get install --install-recommends -y \
    winehq-stable \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: Final image
FROM base

# Copy the scripts directory and convert start.sh to Unix format
COPY app /app
COPY scripts /scripts
RUN dos2unix /scripts/*.sh && \
    chmod +x /scripts/*.sh

# Pre-bake Wine Python (embed zip + pip) — copied into each worker prefix at runtime.
RUN /scripts/build-wine-python-template.sh

COPY /root /

# Create init script to run startup script automatically (runs as root during init)
RUN mkdir -p /etc/cont-init.d && \
    echo '#!/bin/bash' > /etc/cont-init.d/99-start-mt5.sh && \
    echo '/scripts/01-start.sh &' >> /etc/cont-init.d/99-start-mt5.sh && \
    chmod +x /etc/cont-init.d/99-start-mt5.sh && \
    (chmod +x /root/defaults/autostart 2>/dev/null || true)

RUN touch /var/log/mt5_setup.log && \
    chown abc:abc /var/log/mt5_setup.log && \
    chmod 644 /var/log/mt5_setup.log

EXPOSE 3000 5000 5001 8001 18812
VOLUME /config
