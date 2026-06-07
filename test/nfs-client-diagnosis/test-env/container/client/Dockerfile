FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    nfs-common \
    rpcbind \
    iproute2 \
    iptables \
    net-tools \
    iputils-ping \
    procps \
    lsof \
    bc \
    mtr-tiny \
    conntrack \
    stress-ng \
    netcat-openbsd \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# 创建 NFS 挂载目录
RUN mkdir -p /mnt/nfs-test /tmp/nfs-diag

COPY init.sh /init.sh
RUN chmod +x /init.sh

CMD ["/init.sh"]
