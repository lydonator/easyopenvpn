FROM debian:bookworm-slim

# Install OpenVPN and Easy-RSA
RUN apt-get update && apt-get install -y \
    openvpn \
    easy-rsa \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /etc/openvpn/server /etc/openvpn/easy-rsa /var/log/openvpn

# Copy initialization script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose OpenVPN port
EXPOSE 1194/udp

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD pgrep -x openvpn || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["openvpn", "--config", "/etc/openvpn/server/server.conf"]
