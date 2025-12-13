# 🦅 NoC Raven - Telemetry Collection & Forwarding Appliance
# Multi-stage Docker build for lightweight, high-performance deployment
# Supports thousands of devices in venue environments

ARG ALPINE_VERSION=3.19
ARG GOLANG_VERSION=1.23-alpine3.19

# =============================================================================
# Build Stage: GoFlow2 Collector
# =============================================================================
FROM golang:${GOLANG_VERSION} AS goflow-builder
WORKDIR /build

# Install build dependencies
RUN apk add --no-cache git make gcc musl-dev

# Clone and build GoFlow2
RUN git clone https://github.com/netsampler/goflow2.git . && \
    go mod download && \
    go build -ldflags="-s -w" -o goflow2 ./cmd/goflow2

# =============================================================================
# Build Stage: Config Service (Go)
# =============================================================================
FROM golang:${GOLANG_VERSION} AS configsvc-builder
WORKDIR /app
COPY config-service/ ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$(go env GOARCH) go build -ldflags="-s -w" -o /out/config-service .

# =============================================================================
# Build Stage: Buffer Manager Service
# =============================================================================
FROM golang:${GOLANG_VERSION} AS buffer-builder
WORKDIR /app
RUN apk add --no-cache gcc musl-dev sqlite-dev
COPY buffer-service/ ./
RUN go mod tidy && \
    CGO_ENABLED=1 GOOS=linux GOARCH=$(go env GOARCH) go build -ldflags="-s -w" -o /out/buffer-manager .

# =============================================================================
# Build Stage: Web Control Panel
# =============================================================================
FROM node:18-alpine AS web-builder
WORKDIR /build

# Copy web application source
COPY web/package*.json ./
RUN npm install

COPY web/ .
RUN npm run build

# =============================================================================
# Build Stage: Terminal Menu Interface
# =============================================================================
FROM alpine:${ALPINE_VERSION} AS menu-builder
WORKDIR /build

# Install development tools for menu interface
RUN apk add --no-cache gcc musl-dev ncurses-dev make

# Copy terminal menu source and build
COPY scripts/terminal-menu/ .
RUN make clean && make

# =============================================================================
# Production Stage: Complete NoC Raven Appliance
# =============================================================================
FROM alpine:${ALPINE_VERSION}

# Metadata
LABEL maintainer="support@rectitude369.com"
LABEL version="1.0.0"
LABEL description="NoC Raven - High-performance telemetry collection and forwarding appliance"
LABEL org.label-schema.name="noc-raven"
LABEL org.label-schema.description="Turn-key telemetry collector for venue environments"
LABEL org.label-schema.version="1.0.0"
LABEL org.label-schema.vendor="Rectitude 369, LLC"

# Environment variables
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC \
    PERFORMANCE_PROFILE=balanced \
    BUFFER_SIZE=100GB \
    WEB_PORT=8080 \
    NOC_RAVEN_HOME=/opt/noc-raven \
    DATA_PATH=/data \
    CONFIG_PATH=/config

# Create system user and directories
RUN addgroup -g 1000 nocraven && \
    adduser -u 1000 -G nocraven -D -h ${NOC_RAVEN_HOME} nocraven && \
    mkdir -p ${NOC_RAVEN_HOME}/{bin,config,logs,web,scripts} \
             ${NOC_RAVEN_HOME}/logs/nginx_temp/{client_body,proxy,fastcgi,uwsgi,scgi} \
             ${DATA_PATH}/{syslog,flows,snmp,metrics,buffer,vector,logs} \
             ${CONFIG_PATH}/{vpn,collectors,network} \
             /var/log/noc-raven

# Add edge and testing repositories for latest packages
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories

# Install core system dependencies and telemetry services
RUN apk update && apk add --no-cache \
    # Core system and SSL/TLS
    ca-certificates \
    openssl \
    tzdata \
    curl \
    wget \
    jq \
    bash \
    musl \
    libc6-compat \
    # Network tools
    iputils \
    net-tools \
    iproute2 \
    tcpdump \
    nmap \
    netcat-openbsd \
    socat \
    # OpenVPN with authentication
    openvpn \
    expect \
    # Terminal interface
    ncurses \
    dialog \
    figlet \
    # Web server
    nginx \
    # Monitoring
    htop \
    iotop \
    # Process management
    supervisor \
    python3 \
    py3-pip \
    # Development/debugging
    strace \
    ngrep \
    # Database support
    sqlite \
    # Compression
    gzip \
    bzip2 \
    xz \
    # Telemetry services from Alpine packages
    fluent-bit \
    telegraf

# Disable IPv6 to force IPv4-only binding for telemetry services
RUN echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf && \
    echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf && \
    echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf

# =============================================================================
# Install Vector from GitHub releases (as it's not in Alpine repos)
# =============================================================================
RUN cd /tmp && \
    VECTOR_VERSION="0.41.1" && \
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then ARCH="aarch64-unknown-linux-musl"; fi && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="x86_64-unknown-linux-musl"; fi && \
    wget -O vector.tar.gz "https://github.com/vectordotdev/vector/releases/download/v${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${ARCH}.tar.gz" && \
    tar -xzf vector.tar.gz && \
    cp vector-*/bin/vector /usr/local/bin/vector && \
    mkdir -p /etc/vector && \
    cd / && rm -rf /tmp/vector*

# =============================================================================
# Create optimized system configuration for high-performance networking
# =============================================================================
RUN mkdir -p /etc/security && \
    echo "* soft nofile 1048576" >> /etc/security/limits.conf && \
    echo "* hard nofile 1048576" >> /etc/security/limits.conf && \
    echo "fs.file-max = 1048576" >> /etc/sysctl.conf && \
    echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf && \
    echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf && \
    echo "net.core.rmem_default = 8388608" >> /etc/sysctl.conf && \
    echo "net.core.wmem_default = 8388608" >> /etc/sysctl.conf && \
    echo "net.core.netdev_max_backlog = 10000" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_rmem = 4096 87380 134217728" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_wmem = 4096 65536 134217728" >> /etc/sysctl.conf

# Copy built binaries and applications
COPY --from=goflow-builder /build/goflow2 ${NOC_RAVEN_HOME}/bin/
COPY --from=configsvc-builder /out/config-service ${NOC_RAVEN_HOME}/bin/
COPY --from=buffer-builder /out/buffer-manager ${NOC_RAVEN_HOME}/bin/
COPY --from=web-builder /build/dist ${NOC_RAVEN_HOME}/web/
COPY --from=menu-builder /build/terminal-menu ${NOC_RAVEN_HOME}/bin/

# Copy OpenVPN profile
COPY DRT.ovpn ${NOC_RAVEN_HOME}/

# Copy configuration templates and scripts
COPY config/ ${NOC_RAVEN_HOME}/config/
COPY scripts/ ${NOC_RAVEN_HOME}/scripts/
COPY services/ /etc/supervisor/conf.d/

# Explicitly copy essential config files to ensure they're present
COPY config/parsers.conf ${NOC_RAVEN_HOME}/config/
COPY config/fluent-bit.conf ${NOC_RAVEN_HOME}/config/
COPY config/vector-minimal.toml ${NOC_RAVEN_HOME}/config/
COPY config/goflow2.yml ${NOC_RAVEN_HOME}/config/
COPY config/telegraf.conf ${NOC_RAVEN_HOME}/config/

# Copy startup and utility scripts
COPY scripts/entrypoint.sh ${NOC_RAVEN_HOME}/bin/
COPY scripts/boot-manager.sh ${NOC_RAVEN_HOME}/bin/
COPY scripts/network-tools.sh ${NOC_RAVEN_HOME}/bin/
COPY scripts/health-check.sh ${NOC_RAVEN_HOME}/bin/

# Make scripts executable
RUN chmod +x ${NOC_RAVEN_HOME}/bin/* && \
    chmod +x ${NOC_RAVEN_HOME}/scripts/*.sh

# Configure Nginx for web panel
COPY config/nginx.conf /etc/nginx/nginx.conf

# Configure Fluent Bit
COPY config/fluent-bit.conf /etc/fluent-bit/fluent-bit.conf

# Configure Telegraf
COPY config/telegraf.conf /etc/telegraf/telegraf.conf

# Configure Vector
COPY config/vector.toml /etc/vector/vector.toml

# Configure Supervisor for service orchestration
COPY config/supervisord.conf /etc/supervisord.conf

# Create systemctl replacement for container environment
COPY scripts/systemctl-replacement.sh /usr/local/bin/systemctl
RUN chmod +x /usr/local/bin/systemctl

# Set ownership and permissions
RUN chown -R nocraven:nocraven ${NOC_RAVEN_HOME} ${DATA_PATH} ${CONFIG_PATH} /var/log/noc-raven && \
    chmod -R 755 ${NOC_RAVEN_HOME}/scripts && \
    chmod -R 755 ${NOC_RAVEN_HOME}/config && \
    chmod -R 755 ${DATA_PATH} && \
    chmod -R 755 ${CONFIG_PATH}

# Expose ports
# Syslog: 1514/udp
# NetFlow: 2055/udp, 4739/udp
# sFlow: 6343/udp
# SNMP Traps: 162/udp
# Vector HTTP: 8084/tcp
# Web Panel: 8080/tcp
EXPOSE 1514/udp 2055/udp 4739/udp 6343/udp 162/udp 8084/tcp 8080/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ${NOC_RAVEN_HOME}/bin/health-check.sh

# Volume mounts for persistence
VOLUME ["${DATA_PATH}", "${CONFIG_PATH}", "/var/log/noc-raven"]

# Working directory
WORKDIR ${NOC_RAVEN_HOME}

# Switch to non-root user
USER nocraven

# Entry point
ENTRYPOINT ["./bin/entrypoint.sh"]
CMD ["--mode=web"]

# Build information
ARG BUILD_DATE
ARG VCS_REF
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.schema-version="1.0"
