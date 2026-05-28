# ================================================================
# Dockerfile: strace-syscall-diagnosis Fault Injection Environment
# ================================================================
# Multi-stage build:
#   Stage 1: Build all C fault programs
#   Stage 2: Runtime image with tools (strace, ltrace) + binaries
# ================================================================

# ---- Stage 1: Builder ----
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    libpthread-stubs0-dev \
    libc6-dev-i386 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY src/ ./src/

RUN set -ex && \
    echo "Building branch_a_errors..." && \
    gcc -O2 -o /usr/local/bin/branch_a_errors src/branch_a_errors.c -lpthread -lrt && \
    echo "Building branch_b_slow..." && \
    gcc -O2 -o /usr/local/bin/branch_b_slow src/branch_b_slow.c -lpthread -lrt && \
    echo "Building branch_c_library..." && \
    gcc -O0 -g -o /usr/local/bin/branch_c_library src/branch_c_library.c -ldl -lrt && \
    echo "Building branch_d_leak..." && \
    gcc -O2 -o /usr/local/bin/branch_d_leak src/branch_d_leak.c -lpthread -lrt && \
    echo "Building branch_e_network..." && \
    gcc -O2 -o /usr/local/bin/branch_e_network src/branch_e_network.c -lpthread -lrt && \
    echo "Building branch_f_signal..." && \
    gcc -O2 -o /usr/local/bin/branch_f_signal src/branch_f_signal.c -lpthread -lrt && \
    echo "Building branch_g_lifecycle..." && \
    gcc -O2 -o /usr/local/bin/branch_g_lifecycle src/branch_g_lifecycle.c -lpthread -lrt && \
    echo "All binaries built successfully" && \
    ls -la /usr/local/bin/branch_*

# ---- Stage 2: Runtime ----
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    strace \
    ltrace \
    gdb \
    iproute2 \
    net-tools \
    iputils-ping \
    tcpdump \
    curl \
    procps \
    psmisc \
    lsof \
    bc \
    file \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binaries from builder
COPY --from=builder /usr/local/bin/branch_* /usr/local/bin/

# Create non-root user for permission-related tests (EACCES etc.)
RUN groupadd -r testuser && useradd -r -g testuser -m -s /bin/bash testuser

# Create output directory for strace logs
RUN mkdir -p /output && chmod 777 /output

# Working directory
WORKDIR /home

# Default entry point - show usage
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["echo 'Use: inject.sh <branch> <mode> [cycles]'; ls -la /usr/local/bin/branch_*"]

# Labels
LABEL description="strace-syscall-diagnosis Fault Injection Environment"
LABEL maintainer="Fault Injection Team"
LABEL version="1.0.0"
