# =============================================================================
# 基础测试镜像 Dockerfile
# 构建方式: docker build -t netfilter-test:latest -f tests/Dockerfile .
# 构建上下文: 项目根目录（需包含 scripts/ 子目录）
# =============================================================================
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 安装 netfilter 工具集 + 网络工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables ipset conntrack nftables netcat-openbsd curl iproute2 python3 \
    python3-pip dnsutils iputils-ping tcpdump stress iperf3 hping3 \
    apache2-utils net-tools kmod \
    && rm -rf /var/lib/apt/lists/*

# 安装 scapy（构造特殊流量包）
RUN pip3 install scapy --break-system-packages 2>/dev/null || pip3 install scapy

# 复制诊断脚本
COPY scripts/ /scripts/

WORKDIR /

CMD ["/bin/bash", "-c", "trap 'exit 0' SIGTERM; while true; do sleep 3600; done"]
