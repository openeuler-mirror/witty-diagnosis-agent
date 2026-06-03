FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    gcc \
    gdb \
    strace \
    lsof \
    procps \
    psmisc \
    iproute2 \
    netcat-openbsd \
    util-linux \
    file \
    stress-ng \
    fuse3 \
    libfuse3-dev \
    python3 \
    python3-pip \
    nfs-common \
    nfs-kernel-server \
    rpcbind \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /workspace
