FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    nfs-kernel-server \
    rpcbind \
    iproute2 \
    iptables \
    net-tools \
    iputils-ping \
    procps \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /exports

COPY exports /etc/exports
COPY init.sh /init.sh
RUN chmod +x /init.sh

EXPOSE 2049/udp 2049/tcp 111/udp 111/tcp

CMD ["/init.sh"]
