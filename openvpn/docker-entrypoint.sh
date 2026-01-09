#!/bin/bash
set -e

echo "🚀 Starting OpenVPN container initialization..."

# Configuration from environment variables
VPN_PORT="${VPN_PORT:-1194}"
VPN_PROTOCOL="${VPN_PROTOCOL:-udp}"
VPN_SUBNET="${VPN_SUBNET:-10.8.0.0}"
VPN_NETMASK="${VPN_NETMASK:-255.255.255.0}"
DNS_SERVER="${DNS_SERVER:-8.8.8.8}"

# Easy-RSA paths
EASYRSA_DIR="/usr/share/easy-rsa"
PKI_DIR="/etc/openvpn/easy-rsa/pki"
SERVER_CONF="/etc/openvpn/server/server.conf"

# Check if PKI already exists (idempotency)
if [ ! -f "${PKI_DIR}/ca.crt" ]; then
    echo "📋 PKI not found, initializing Easy-RSA..."

    # Initialize Easy-RSA
    cd /etc/openvpn/easy-rsa
    cp -r ${EASYRSA_DIR}/* .

    echo "🔑 Initializing PKI..."
    ./easyrsa init-pki

    echo "🔐 Building CA certificate..."
    ./easyrsa --batch build-ca nopass

    echo "🔑 Generating server certificate..."
    ./easyrsa --batch build-server-full server nopass

    echo "🔢 Generating DH parameters (this may take a while)..."
    ./easyrsa gen-dh

    echo "🔒 Generating TLS auth key..."
    openvpn --genkey secret ${PKI_DIR}/ta.key

    echo "✅ PKI initialization complete"
else
    echo "✅ PKI already exists, skipping initialization"
fi

# Set PKI directory permissions for shared access with portal container
# Group 1000 matches the vpnuser GID in portal container
echo "🔐 Setting PKI directory permissions for shared access..."
chgrp -R 1000 /etc/openvpn/easy-rsa/pki
chmod -R g+rwX /etc/openvpn/easy-rsa/pki

# Restrict server private key to root only (portal doesn't need it)
chmod 600 /etc/openvpn/easy-rsa/pki/private/server.key
chown root:root /etc/openvpn/easy-rsa/pki/private/server.key
echo "✅ PKI permissions configured (server.key restricted to root)"

# Generate OpenVPN server configuration
echo "📝 Generating OpenVPN server configuration..."
cat > ${SERVER_CONF} <<EOF
# OpenVPN Server Configuration
port ${VPN_PORT}
proto ${VPN_PROTOCOL}
dev tun
topology subnet

# SSL/TLS certificates and keys
ca ${PKI_DIR}/ca.crt
cert ${PKI_DIR}/issued/server.crt
key ${PKI_DIR}/private/server.key
dh ${PKI_DIR}/dh.pem
tls-auth ${PKI_DIR}/ta.key 0
crl-verify ${PKI_DIR}/crl.pem

# Network configuration
server ${VPN_SUBNET} ${VPN_NETMASK}
ifconfig-pool-persist /var/log/openvpn/ipp.txt

# Push routes to clients
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${DNS_SERVER}"

# Connection settings
keepalive 10 120
cipher AES-256-GCM
auth SHA256

# Privilege settings
user nobody
group nogroup
persist-key
persist-tun

# Logging
status /var/log/openvpn/status.log
verb 3
EOF

echo "✅ Server configuration generated"

# Enable IP forwarding (may fail in container if not privileged - that's OK if host has it enabled)
echo "🌐 Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 || echo "⚠ Could not set IP forwarding (requires host-level configuration)"

# Set up iptables NAT for VPN subnet
echo "🔥 Configuring iptables NAT..."
# Detect the default route interface (internet-facing interface)
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
if [ -z "$DEFAULT_IFACE" ]; then
    echo "⚠ Could not detect default network interface, using eth0"
    DEFAULT_IFACE="eth0"
fi
echo "  Using interface: $DEFAULT_IFACE"
iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}/24 -o $DEFAULT_IFACE -j MASQUERADE

echo "✅ OpenVPN initialization complete, starting server..."

# Execute the command (start OpenVPN)
exec "$@"
