#!/bin/bash

################################################################################
# EasyOpenVPN installer - curl | bash OpenVPN server setup
#
# Description:
#   Automated installer that provisions a complete OpenVPN server with
#   self-signed certificates, web portal, and client management.
#
# Usage:
#   curl -fsSL https://your-domain.com/install.sh | bash
#   OR
#   wget -qO- https://your-domain.com/install.sh | bash
#   OR
#   bash install.sh (if downloaded locally)
#
# Requirements:
#   - Ubuntu 22.04+ or Debian 11+
#   - Run as root
#   - Internet connectivity
#
# What it does:
#   1. Detects OS and verifies compatibility
#   2. Installs OpenVPN and Easy-RSA packages
#   3. Generates PKI (certificates and keys)
#   4. Configures OpenVPN server
#   5. Sets up firewall rules
#   6. Creates web portal for client management
#
################################################################################

# Error handling setup
set -e           # Exit on any error
set -o pipefail  # Catch pipeline failures

# Variable declarations
OPENVPN_DIR="/etc/openvpn/server"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CLIENT_DIR="/root/openvpn-clients"
LOG_FILE="/var/log/openvpn-install.log"

# Error handling function
error_exit() {
    echo "Error: $1" >&2
    exit "${2:-1}"
}

# Cleanup function for temp files
cleanup() {
    # Remove any temporary files created during installation
    # This will be expanded as needed
    :
}
trap cleanup EXIT

################################################################################
# Pre-flight checks
################################################################################

# Root check
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root. Please use sudo or run as root user."
fi

# OS detection
if [[ ! -f /etc/os-release ]]; then
    error_exit "Cannot detect operating system. /etc/os-release not found."
fi

# Source OS release file
source /etc/os-release

# Verify supported OS
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    error_exit "Unsupported OS: $ID. This script supports Ubuntu and Debian only."
fi

echo "Detected OS: $ID $VERSION_ID"

# Store version for later use
OS_VERSION="$VERSION_ID"

# Detect if this is an update/re-run
if systemctl is-active --quiet openvpn-server@server 2>/dev/null; then
    echo "═══════════════════════════════════════════════════════════════"
    echo "Detected existing OpenVPN installation"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "This script is idempotent - it will:"
    echo "  ✓ Update components that need updating"
    echo "  ✓ Skip components that are already configured"
    echo "  ✓ Preserve existing clients and certificates"
    echo ""
    IS_UPDATE=true
else
    echo "═══════════════════════════════════════════════════════════════"
    echo "Fresh installation detected"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    IS_UPDATE=false
fi

################################################################################
# Docker Installation
################################################################################

install_docker() {
    echo "Checking Docker installation..."

    # Check if Docker is installed
    if ! command -v docker &>/dev/null; then
        echo "Installing Docker Engine..."
        curl -fsSL https://get.docker.com -o get-docker.sh || error_exit "Failed to download Docker installation script"
        sh get-docker.sh || error_exit "Docker installation failed"
        rm get-docker.sh
        echo "✓ Docker installed successfully"
    else
        echo "✓ Docker already installed ($(docker --version))"
    fi

    # Check if Docker daemon is running
    if ! systemctl is-active --quiet docker; then
        echo "Starting Docker daemon..."
        systemctl start docker || error_exit "Failed to start Docker daemon"
        systemctl enable docker || error_exit "Failed to enable Docker daemon"
        echo "✓ Docker daemon started"
    else
        echo "✓ Docker daemon is running"
    fi
}

# Run Docker installation
install_docker

################################################################################
# Docker Compose v2 and TUN Module Verification
################################################################################

verify_docker_prerequisites() {
    echo "Verifying Docker prerequisites..."

    # Verify Docker Compose v2 is available
    if docker compose version &>/dev/null; then
        COMPOSE_VERSION=$(docker compose version --short)
        echo "✓ Docker Compose v2 available ($COMPOSE_VERSION)"
    else
        error_exit "Docker Compose v2 not available. Docker installation may have failed."
    fi

    # Check if TUN module is loaded
    if ! lsmod | grep -q "^tun"; then
        echo "Loading TUN kernel module..."
        modprobe tun || error_exit "Failed to load TUN kernel module"
        # Make persistent across reboots
        echo "tun" > /etc/modules-load.d/tun.conf || error_exit "Failed to configure TUN module persistence"
        echo "✓ TUN module loaded"
    else
        echo "✓ TUN module already loaded"
    fi

    # Verify /dev/net/tun exists
    if ! test -c /dev/net/tun; then
        error_exit "TUN device /dev/net/tun not available. Cannot proceed with VPN setup."
    fi
    echo "✓ TUN device available: /dev/net/tun"
}

# Run Docker prerequisites verification
verify_docker_prerequisites

################################################################################
# Main installation starts here
################################################################################

echo "═══════════════════════════════════════════════════════════════"
echo "EasyOpenVPN Installer"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "This will install OpenVPN server on $ID $VERSION_ID"
echo ""

################################################################################
# Package installation
################################################################################

install_packages() {
    echo "Installing OpenVPN and Easy-RSA..."

    # Check if already installed (idempotency)
    if dpkg -s openvpn &>/dev/null && dpkg -s easy-rsa &>/dev/null; then
        echo "✓ Packages already installed, skipping"
        return 0
    fi

    # Update package lists
    apt-get update || error_exit "Failed to update package lists"

    # Install packages
    apt-get install -y openvpn easy-rsa || error_exit "Failed to install packages"

    # Verify installation
    command -v openvpn >/dev/null || error_exit "OpenVPN not found after installation"

    # Check Easy-RSA location and store it
    if [[ -d /usr/share/easy-rsa ]]; then
        EASYRSA_PKG_DIR="/usr/share/easy-rsa"
    else
        error_exit "Easy-RSA package directory not found at /usr/share/easy-rsa"
    fi

    echo "✓ Packages installed successfully"
    echo "  - OpenVPN: $(openvpn --version | head -n1)"
    echo "  - Easy-RSA: $EASYRSA_PKG_DIR"
}

# Run package installation
install_packages

################################################################################
# Web Portal Dependencies
################################################################################

install_web_dependencies() {
    echo "Installing web portal dependencies..."

    # Check if Flask is already installed (idempotency)
    if python3 -c "import flask" &>/dev/null; then
        echo "✓ Flask already installed, skipping"
        python3 -c "import flask; print('  - Flask version:', flask.__version__)"
        return 0
    fi

    # Install Python3 and Flask packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3 \
        python3-pip \
        python3-flask \
        python3-werkzeug || error_exit "Failed to install web dependencies"

    # Verify Flask is importable
    if ! python3 -c "import flask" &>/dev/null; then
        error_exit "Flask module not importable after installation"
    fi

    # Display installed version
    echo "✓ Web dependencies installed successfully"
    echo "  - Python3: $(python3 --version)"
    python3 -c "import flask; print('  - Flask version:', flask.__version__)"
}

# Run web dependencies installation
install_web_dependencies

################################################################################
# Web Portal SSL Certificate
################################################################################

generate_portal_ssl() {
    echo "Generating self-signed SSL certificate for web portal..."

    # Create portal SSL directory
    PORTAL_SSL_DIR="/etc/openvpn/portal"
    mkdir -p "$PORTAL_SSL_DIR" || error_exit "Failed to create portal SSL directory"

    # Check if certificate already exists (idempotency)
    if [[ -f "$PORTAL_SSL_DIR/portal.crt" && -f "$PORTAL_SSL_DIR/portal.key" ]]; then
        echo "✓ Portal SSL certificate already exists, skipping generation"
        # Verify existing certificate
        if openssl x509 -in "$PORTAL_SSL_DIR/portal.crt" -text -noout | grep -q "CN.*OpenVPN Portal"; then
            echo "  - Certificate verified"
            return 0
        else
            echo "  - Warning: Existing certificate may be invalid, regenerating..."
        fi
    fi

    # Generate self-signed certificate (10-year validity)
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$PORTAL_SSL_DIR/portal.key" \
        -out "$PORTAL_SSL_DIR/portal.crt" \
        -subj "/CN=OpenVPN Portal" || error_exit "Failed to generate portal SSL certificate"

    # Set correct permissions
    chmod 600 "$PORTAL_SSL_DIR/portal.key" || error_exit "Failed to set portal.key permissions"
    chmod 644 "$PORTAL_SSL_DIR/portal.crt" || error_exit "Failed to set portal.crt permissions"

    # Verify certificate generation
    [[ -f "$PORTAL_SSL_DIR/portal.crt" ]] || error_exit "Portal certificate not found after generation"
    [[ -f "$PORTAL_SSL_DIR/portal.key" ]] || error_exit "Portal private key not found after generation"

    # Verify certificate content
    if ! openssl x509 -in "$PORTAL_SSL_DIR/portal.crt" -text -noout &>/dev/null; then
        error_exit "Portal certificate validation failed"
    fi

    echo "✓ Portal SSL certificate generated successfully"
    echo "  - Certificate: $PORTAL_SSL_DIR/portal.crt"
    echo "  - Private key: $PORTAL_SSL_DIR/portal.key"
}

# Run portal SSL generation
generate_portal_ssl

################################################################################
# Public IP detection
################################################################################

detect_public_ip() {
    echo "Detecting public IP address..."

    # Primary method - DNS-based (most reliable)
    PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)

    # If dig fails, try HTTP fallback
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    fi

    # If both fail, try second HTTP fallback
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s --max-time 5 icanhazip.com 2>/dev/null)
    fi

    # If all methods fail
    if [[ -z "$PUBLIC_IP" ]]; then
        error_exit "Could not detect public IP address. Please check network connectivity."
    fi

    # Validate IP format
    if ! [[ "$PUBLIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error_exit "Detected IP '$PUBLIC_IP' is not valid IPv4 format"
    fi

    echo "✓ Detected public IP: $PUBLIC_IP"
}

# Run public IP detection
detect_public_ip

################################################################################
# PKI Setup
################################################################################

setup_pki() {
    echo "Setting up PKI infrastructure..."

    # Create Easy-RSA directory
    mkdir -p "$EASYRSA_DIR" || error_exit "Failed to create Easy-RSA directory"

    # Copy Easy-RSA files from package location (idempotent - will overwrite)
    # Easy-RSA package installs to /usr/share/easy-rsa/
    if [[ -d /usr/share/easy-rsa ]]; then
        cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR/" || error_exit "Failed to copy Easy-RSA files"
    else
        error_exit "Easy-RSA not found in /usr/share/easy-rsa/"
    fi

    # Make easyrsa executable
    chmod +x "$EASYRSA_DIR/easyrsa" || error_exit "Failed to make easyrsa executable"

    # Initialize PKI structure (idempotent check)
    cd "$EASYRSA_DIR" || error_exit "Failed to change to Easy-RSA directory"

    if [[ -d pki ]] && [[ -f pki/ca.crt ]]; then
        echo "✓ PKI already initialized, skipping"
    else
        echo "  Initializing PKI structure..."
        ./easyrsa init-pki || error_exit "Failed to initialize PKI"

        # Build Certificate Authority
        # Use EASYRSA_BATCH=1 to avoid interactive prompts
        # Use nopass to avoid password prompt (required for automated installer)
        echo "  Building Certificate Authority..."
        EASYRSA_BATCH=1 ./easyrsa build-ca nopass || error_exit "Failed to build CA"

        # Verify CA created
        [[ -f pki/ca.crt ]] || error_exit "CA certificate not found after generation"
        [[ -f pki/private/ca.key ]] || error_exit "CA private key not found after generation"

        echo "✓ PKI initialized and CA generated"
    fi
}

# Run PKI setup
setup_pki

################################################################################
# Server Certificate Generation
################################################################################

generate_server_certs() {
    echo "Generating server certificates..."

    # Change to Easy-RSA directory
    cd "$EASYRSA_DIR" || error_exit "Failed to change to Easy-RSA directory"

    # Generate server certificate and key (idempotent check)
    if [[ -f pki/issued/server.crt ]] && [[ -f pki/private/server.key ]]; then
        echo "✓ Server certificate already exists, skipping"
    else
        echo "  Generating server certificate..."
        EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass || error_exit "Failed to generate server certificate"

        # Verify server certificate created
        [[ -f pki/issued/server.crt ]] || error_exit "Server certificate not found"
        [[ -f pki/private/server.key ]] || error_exit "Server private key not found"
        echo "✓ Server certificate generated"
    fi

    # Generate DH parameters (2048-bit) - idempotent check
    # This takes 2-5 minutes - inform user
    if [[ -f pki/dh.pem ]]; then
        echo "✓ DH parameters already exist, skipping"
    else
        echo "  Generating DH parameters (this may take several minutes)..."
        ./easyrsa gen-dh || error_exit "Failed to generate DH parameters"

        # Verify DH params created
        [[ -f pki/dh.pem ]] || error_exit "DH parameters not found"
        echo "✓ DH parameters generated"
    fi

    # Generate tls-crypt key (idempotent check)
    if [[ -f pki/tc.key ]]; then
        echo "✓ tls-crypt key already exists, skipping"
    else
        echo "  Generating tls-crypt key..."
        # Use openvpn --genkey command (standard method)
        openvpn --genkey secret "$EASYRSA_DIR/pki/tc.key" || error_exit "Failed to generate tls-crypt key"

        # Verify tls-crypt key created
        [[ -f pki/tc.key ]] || error_exit "tls-crypt key not found"
        echo "✓ tls-crypt key generated"
    fi

    # Copy certificates to OpenVPN server directory (idempotent - will overwrite)
    mkdir -p "$OPENVPN_DIR" || error_exit "Failed to create OpenVPN directory"

    cp pki/ca.crt "$OPENVPN_DIR/" || error_exit "Failed to copy CA certificate"
    cp pki/issued/server.crt "$OPENVPN_DIR/" || error_exit "Failed to copy server certificate"
    cp pki/private/server.key "$OPENVPN_DIR/" || error_exit "Failed to copy server key"
    cp pki/dh.pem "$OPENVPN_DIR/" || error_exit "Failed to copy DH parameters"
    cp pki/tc.key "$OPENVPN_DIR/" || error_exit "Failed to copy tls-crypt key"

    # Generate initial CRL for certificate revocation (idempotent check)
    if [[ -f pki/crl.pem ]]; then
        echo "✓ CRL already exists, updating..."
        ./easyrsa gen-crl || error_exit "Failed to update CRL"
    else
        echo "  Generating initial CRL..."
        ./easyrsa gen-crl || error_exit "Failed to generate initial CRL"
    fi
    cp pki/crl.pem "$OPENVPN_DIR/" || error_exit "Failed to copy CRL"
    chmod 644 "$OPENVPN_DIR/crl.pem" || error_exit "Failed to set CRL permissions"

    # Set correct permissions
    chmod 600 "$OPENVPN_DIR/server.key" || error_exit "Failed to set server key permissions"
    chmod 600 "$OPENVPN_DIR/tc.key" || error_exit "Failed to set tls-crypt key permissions"

    echo "✓ Server certificates installed"
}

# Run server certificate generation
generate_server_certs

################################################################################
# Server Configuration
################################################################################

create_server_config() {
    echo "Creating OpenVPN server configuration..."

    # Create server.conf in /etc/openvpn/server/
    cat > "$OPENVPN_DIR/server.conf" <<EOF
# Network configuration
port 1194
proto udp
dev tun
server 10.8.0.0 255.255.255.0

# Certificate and key files
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-crypt tc.key

# Certificate Revocation List
crl-verify crl.pem

# Security settings
cipher AES-128-GCM
auth SHA256
tls-version-min 1.2

# Networking
keepalive 10 120
persist-key
persist-tun

# DNS - push Google DNS to clients
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Logging
status /var/log/openvpn/openvpn-status.log
verb 3
mute 20
explicit-exit-notify 1
EOF

    # Create log directory
    mkdir -p /var/log/openvpn || error_exit "Failed to create log directory"

    # Verify config created
    [[ -f "$OPENVPN_DIR/server.conf" ]] || error_exit "Server config not created"

    echo "✓ Server configuration created"
}

# Run server configuration
create_server_config

################################################################################
# Firewall Configuration
################################################################################

configure_firewall() {
    echo "Configuring firewall and networking..."

    # Get interface with default route
    NET_INTERFACE=$(ip route show default | awk '{print $5; exit}')
    [[ -z "$NET_INTERFACE" ]] && error_exit "Could not detect network interface"
    echo "Detected network interface: $NET_INTERFACE"

    # Enable IP forwarding in sysctl.conf
    # Check if already enabled (idempotency)
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi

    # Apply immediately
    sysctl -p || error_exit "Failed to apply sysctl settings"

    # Set DEFAULT_FORWARD_POLICY to ACCEPT
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

    # Insert NAT rules in /etc/ufw/before.rules
    # Check if already present (idempotency)
    if ! grep -q "openvpn" /etc/ufw/before.rules; then
        # Find line with *filter and insert NAT rules before it
        sed -i "/^\*filter/i # NAT table rules for OpenVPN\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.8.0.0/24 -o $NET_INTERFACE -j MASQUERADE\nCOMMIT\n" /etc/ufw/before.rules
    fi

    # Allow OpenVPN port through UFW
    ufw allow 1194/udp comment 'OpenVPN server' || error_exit "Failed to allow OpenVPN port"

    # Enable UFW if not already enabled
    # Check if UFW is active
    if ! ufw status | grep -q "Status: active"; then
        echo "y" | ufw enable || error_exit "Failed to enable UFW"
    else
        # Reload to apply new rules
        ufw reload || error_exit "Failed to reload UFW"
    fi

    # Verify IP forwarding enabled
    [[ "$(cat /proc/sys/net/ipv4/ip_forward)" == "1" ]] || error_exit "IP forwarding not enabled"

    echo "✓ Firewall configured with NAT/masquerading"
}

# Run firewall configuration
configure_firewall

################################################################################
# Service Management
################################################################################

start_openvpn_service() {
    echo "Starting OpenVPN service..."

    # Reload systemd daemon
    systemctl daemon-reload || error_exit "Failed to reload systemd daemon"

    # Enable OpenVPN service to start on boot
    systemctl enable openvpn-server@server || error_exit "Failed to enable OpenVPN service"

    # Start or restart OpenVPN service (idempotent)
    if systemctl is-active --quiet openvpn-server@server; then
        echo "  Service already running, restarting to apply any changes..."
        systemctl restart openvpn-server@server || error_exit "Failed to restart OpenVPN service"
    else
        echo "  Starting service for the first time..."
        systemctl start openvpn-server@server || error_exit "Failed to start OpenVPN service"
    fi

    # Wait 2 seconds for service to initialize
    sleep 2

    # Verify service is running
    if ! systemctl is-active --quiet openvpn-server@server; then
        error_exit "OpenVPN service failed to start. Check: journalctl -u openvpn-server@server -n 50"
    fi

    # Verify TUN interface created
    if ! ip link show tun0 &>/dev/null; then
        error_exit "TUN interface not created. Check: journalctl -u openvpn-server@server -n 50"
    fi

    # Display service status
    echo "✓ OpenVPN service started successfully"
    systemctl status openvpn-server@server --no-pager | head -10

    echo "✓ OpenVPN server running on UDP port 1194"
}

# Run service management
start_openvpn_service

################################################################################
# Client Certificate Generation
################################################################################

generate_client_cert() {
    CLIENT_NAME="${1:-client1}"

    # Ensure client name is alphanumeric with dashes/underscores only
    if ! [[ "$CLIENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_exit "Invalid client name. Use only letters, numbers, dashes, and underscores."
    fi

    echo "Generating client certificate for '$CLIENT_NAME'..."

    cd "$EASYRSA_DIR" || error_exit "Failed to change to Easy-RSA directory"

    # Check if client already exists (idempotency)
    if [[ -f "pki/issued/${CLIENT_NAME}.crt" ]]; then
        echo "Client certificate for '$CLIENT_NAME' already exists, skipping generation"
        return 0
    fi

    # Generate client certificate and key
    EASYRSA_BATCH=1 ./easyrsa build-client-full "$CLIENT_NAME" nopass || error_exit "Failed to generate client certificate for $CLIENT_NAME"

    # Verify client certificate created
    [[ -f "pki/issued/${CLIENT_NAME}.crt" ]] || error_exit "Client certificate not found after generation"
    [[ -f "pki/private/${CLIENT_NAME}.key" ]] || error_exit "Client private key not found after generation"

    # Create client config directory
    mkdir -p "$CLIENT_DIR" || error_exit "Failed to create client directory"

    echo "✓ Client certificate generated"
}

################################################################################
# Client Configuration File Generation
################################################################################

create_client_ovpn() {
    CLIENT_NAME="${1:-client1}"
    OVPN_FILE="$CLIENT_DIR/${CLIENT_NAME}.ovpn"

    echo "Creating client configuration file..."

    # Create base client configuration
    cat > "$OVPN_FILE" <<EOF
# EasyOpenVPN client configuration for $CLIENT_NAME
client
dev tun
proto udp
remote $PUBLIC_IP 1194

# Security
cipher AES-128-GCM
auth SHA256
tls-version-min 1.2

# Connection
resolv-retry infinite
nobind
persist-key
persist-tun

# Logging
verb 3
mute 20
EOF

    # Append inline CA certificate
    echo "<ca>" >> "$OVPN_FILE"
    cat "$OPENVPN_DIR/ca.crt" >> "$OVPN_FILE"
    echo "</ca>" >> "$OVPN_FILE"

    # Append inline client certificate
    echo "<cert>" >> "$OVPN_FILE"
    # Extract certificate part only (skip bag attributes and key)
    openssl x509 -in "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt" >> "$OVPN_FILE" || error_exit "Failed to extract client certificate"
    echo "</cert>" >> "$OVPN_FILE"

    # Append inline client private key
    echo "<key>" >> "$OVPN_FILE"
    cat "$EASYRSA_DIR/pki/private/${CLIENT_NAME}.key" >> "$OVPN_FILE"
    echo "</key>" >> "$OVPN_FILE"

    # Append inline tls-crypt key
    echo "<tls-crypt>" >> "$OVPN_FILE"
    cat "$OPENVPN_DIR/tc.key" >> "$OVPN_FILE"
    echo "</tls-crypt>" >> "$OVPN_FILE"

    # Set file permissions
    chmod 600 "$OVPN_FILE" || error_exit "Failed to set permissions on client config"

    # Verify config file created
    [[ -f "$OVPN_FILE" ]] || error_exit "Client config file not created"

    echo "✓ Client configuration created: $OVPN_FILE"
    echo "  Download this file and import it into your OpenVPN client"
}

################################################################################
# Client Deletion Function
################################################################################

delete_client() {
    CLIENT_NAME="${1}"

    # Validate client name is provided
    if [[ -z "$CLIENT_NAME" ]]; then
        error_exit "Client name is required for deletion"
    fi

    # Validate client name format (same regex as generate_client_cert)
    if ! [[ "$CLIENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_exit "Invalid client name. Use only letters, numbers, dashes, and underscores."
    fi

    echo "Deleting client '$CLIENT_NAME'..."

    # Check if client certificate exists
    if [[ ! -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt" ]]; then
        error_exit "Client certificate for '$CLIENT_NAME' not found"
    fi

    # Change to Easy-RSA directory
    cd "$EASYRSA_DIR" || error_exit "Failed to change to Easy-RSA directory"

    # Revoke client certificate
    echo "Revoking certificate..."
    # Use 'yes' to auto-confirm revocation
    EASYRSA_BATCH=1 ./easyrsa revoke "$CLIENT_NAME" || error_exit "Failed to revoke certificate for $CLIENT_NAME"

    # Regenerate CRL
    echo "Regenerating CRL..."
    ./easyrsa gen-crl || error_exit "Failed to regenerate CRL"

    # Copy updated CRL to OpenVPN directory
    cp pki/crl.pem "$OPENVPN_DIR/crl.pem" || error_exit "Failed to copy updated CRL"
    chmod 644 "$OPENVPN_DIR/crl.pem" || error_exit "Failed to set CRL permissions"

    # Remove client configuration file
    if [[ -f "$CLIENT_DIR/${CLIENT_NAME}.ovpn" ]]; then
        rm -f "$CLIENT_DIR/${CLIENT_NAME}.ovpn" || error_exit "Failed to remove client configuration file"
        echo "✓ Removed client configuration file"
    fi

    # Remove certificate files (optional - keep for audit trail, but noted in plan to remove)
    if [[ -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt" ]]; then
        rm -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt"
        echo "✓ Removed client certificate"
    fi

    if [[ -f "$EASYRSA_DIR/pki/private/${CLIENT_NAME}.key" ]]; then
        rm -f "$EASYRSA_DIR/pki/private/${CLIENT_NAME}.key"
        echo "✓ Removed client private key"
    fi

    # Restart OpenVPN service to reload CRL
    echo "Restarting OpenVPN service..."
    systemctl restart openvpn-server@server || error_exit "Failed to restart OpenVPN service"

    # Wait for service to restart
    sleep 2

    # Verify service is running
    if ! systemctl is-active --quiet openvpn-server@server; then
        error_exit "OpenVPN service failed to restart after client deletion"
    fi

    echo "✓ Client '$CLIENT_NAME' deleted successfully"
    return 0
}

################################################################################
# Client Listing Function
################################################################################

list_clients() {
    # Create client directory if it doesn't exist
    mkdir -p "$CLIENT_DIR" || return 1

    # Find all .ovpn files in CLIENT_DIR
    # Use pure bash JSON output to avoid jq dependency
    for ovpn in "$CLIENT_DIR"/*.ovpn; do
        # Check if file exists (handles case when no .ovpn files exist)
        [[ -f "$ovpn" ]] || continue

        # Extract filename and client name
        basename="${ovpn##*/}"
        name="${basename%.ovpn}"

        # Get file size (Linux stat format)
        size=$(stat -c%s "$ovpn" 2>/dev/null || echo "0")

        # Output JSON line
        echo "{\"name\":\"$name\",\"file\":\"$ovpn\",\"size\":$size}"
    done

    return 0
}

################################################################################
# Generate First Client
################################################################################

# Generate first client certificate and configuration
generate_client_cert "client1"
create_client_ovpn "client1"

################################################################################
# Web Portal Service
################################################################################

create_portal_service() {
    echo "Creating web portal systemd service..."

    SERVICE_FILE="/etc/systemd/system/openvpn-portal.service"

    # Check if service file already exists (idempotency)
    if [[ -f "$SERVICE_FILE" ]]; then
        echo "✓ Portal service file already exists, skipping creation"
        return 0
    fi

    # Create portal app directory
    mkdir -p /opt/openvpn-portal || error_exit "Failed to create portal app directory"

    # Create systemd service file
    cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=EasyOpenVPN Web Portal
After=network.target openvpn-server@server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/openvpn-portal
ExecStart=/usr/bin/python3 /opt/openvpn-portal/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # Verify service file created
    [[ -f "$SERVICE_FILE" ]] || error_exit "Portal service file not created"

    # Reload systemd daemon to recognize new service
    systemctl daemon-reload || error_exit "Failed to reload systemd daemon"

    # Note: We don't enable or start the service yet - app.py doesn't exist yet
    # That will happen in Plan 2

    echo "✓ Portal service created and loaded by systemd"
    echo "  - Service file: $SERVICE_FILE"
    echo "  - App directory: /opt/openvpn-portal"
    echo "  - Note: Service will be enabled and started in next phase (after app.py is created)"
}

# Run portal service creation
create_portal_service

################################################################################
# Flask Application Creation (Task 1)
################################################################################

create_flask_app() {
    echo "Creating Flask application..."

    APP_DIR="/opt/openvpn-portal"
    APP_FILE="$APP_DIR/app.py"

    # Create directory structure
    mkdir -p "$APP_DIR/templates" || error_exit "Failed to create templates directory"
    mkdir -p "$APP_DIR/static" || error_exit "Failed to create static directory"

    # Check if app.py already exists (idempotency)
    if [[ -f "$APP_FILE" ]]; then
        echo "✓ Flask app already exists, skipping creation"
        return 0
    fi

    # Generate unique secret key
    SECRET_KEY=$(python3 -c "import os; print(os.urandom(24).hex())")

    # Create Flask application
    cat > "$APP_FILE" <<EOF
#!/usr/bin/env python3
from flask import Flask, session, redirect, render_template, request, url_for, jsonify, send_file, abort
import bcrypt
import os
import subprocess
import re
import json
from pathlib import Path

app = Flask(__name__)
app.secret_key = '$SECRET_KEY'
app.config['PERMANENT_SESSION_LIFETIME'] = 3600

# Login required decorator
def login_required(f):
    from functools import wraps
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('authenticated'):
            return jsonify({'error': 'Authentication required'}), 401
        return f(*args, **kwargs)
    return decorated_function

@app.route('/')
def index():
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        password = request.form.get('password', '')

        # Read bcrypt hash from auth file
        try:
            with open('/etc/openvpn/portal/auth.txt', 'r') as f:
                password_hash = f.read().strip()

            # Verify password
            if bcrypt.checkpw(password.encode(), password_hash.encode()):
                session['authenticated'] = True
                session.permanent = True
                return redirect(url_for('dashboard'))
            else:
                error = 'Invalid password'
        except Exception as e:
            error = 'Authentication error'

    return render_template('login.html', error=error)

@app.route('/dashboard')
def dashboard():
    if not session.get('authenticated'):
        return redirect(url_for('login'))

    # Read server IP
    try:
        with open('/root/.openvpn-server-ip', 'r') as f:
            server_ip = f.read().strip()
    except:
        server_ip = 'Unknown'

    return render_template('dashboard.html', server_ip=server_ip)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/api/clients/create', methods=['POST'])
@login_required
def create_client():
    try:
        client_name = request.json.get('client_name', '').strip()

        # Validate client name (alphanumeric with dashes/underscores only)
        if not client_name:
            return jsonify({'error': 'Client name is required'}), 400

        if not re.match(r'^[a-zA-Z0-9_-]+$', client_name):
            return jsonify({'error': 'Invalid client name. Use only letters, numbers, dashes, and underscores.'}), 400

        # Check if client already exists
        client_file = f'/root/openvpn-clients/{client_name}.ovpn'
        if os.path.exists(client_file):
            return jsonify({'error': f'Client {client_name} already exists'}), 400

        # Call generate_client_cert function
        result = subprocess.run(
            ['/bin/bash', '-c', f'source /root/install.sh && generate_client_cert "{client_name}"'],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            return jsonify({'error': f'Failed to generate client certificate: {result.stderr}'}), 500

        # Call create_client_ovpn function
        result = subprocess.run(
            ['/bin/bash', '-c', f'source /root/install.sh && create_client_ovpn "{client_name}"'],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            return jsonify({'error': f'Failed to create client configuration: {result.stderr}'}), 500

        # Verify client file was created
        if not os.path.exists(client_file):
            return jsonify({'error': 'Client file not created'}), 500

        return jsonify({
            'success': True,
            'message': f'Client {client_name} created successfully',
            'client_name': client_name,
            'file': client_file
        }), 200

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Client creation timed out'}), 500
    except Exception as e:
        return jsonify({'error': f'Internal server error: {str(e)}'}), 500

@app.route('/api/clients/list', methods=['GET'])
@login_required
def list_clients():
    try:
        # Call list_clients bash function
        result = subprocess.run(
            ['/bin/bash', '-c', 'source /root/install.sh && list_clients'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            return jsonify({'error': f'Failed to list clients: {result.stderr}'}), 500

        # Parse JSON output from bash function (one JSON object per line)
        clients = []
        for line in result.stdout.strip().split('\n'):
            if line:
                clients.append(json.loads(line))

        return jsonify({'clients': clients}), 200

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Client listing timed out'}), 500
    except Exception as e:
        return jsonify({'error': f'Internal server error: {str(e)}'}), 500

@app.route('/api/clients/delete', methods=['POST'])
@login_required
def delete_client():
    try:
        client_name = request.json.get('client_name', '').strip()

        # Validate client name
        if not client_name:
            return jsonify({'error': 'Client name is required'}), 400

        if not re.match(r'^[a-zA-Z0-9_-]+$', client_name):
            return jsonify({'error': 'Invalid client name'}), 400

        # Check if client exists
        client_file = f'/root/openvpn-clients/{client_name}.ovpn'
        if not os.path.exists(client_file):
            return jsonify({'error': f'Client {client_name} does not exist'}), 400

        # Call delete_client bash function
        result = subprocess.run(
            ['/bin/bash', '-c', f'source /root/install.sh && delete_client "{client_name}"'],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            return jsonify({'error': f'Failed to delete client: {result.stderr}'}), 500

        return jsonify({
            'success': True,
            'message': f'Client {client_name} deleted successfully'
        }), 200

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Client deletion timed out'}), 500
    except Exception as e:
        return jsonify({'error': f'Internal server error: {str(e)}'}), 500

@app.route('/download/<client_name>')
@login_required
def download_client(client_name):
    try:
        # Validate client_name format to prevent path traversal
        if not re.match(r'^[a-zA-Z0-9_-]+$', client_name):
            abort(400)

        # Construct safe file path
        client_dir = Path('/root/openvpn-clients')
        client_file = client_dir / f'{client_name}.ovpn'

        # Verify file exists
        if not client_file.exists():
            abort(404)

        # Verify the resolved path is still within client_dir (prevent traversal)
        if not str(client_file.resolve()).startswith(str(client_dir.resolve())):
            abort(403)

        # Send file with proper headers
        return send_file(
            str(client_file),
            mimetype='application/x-openvpn-profile',
            as_attachment=True,
            download_name=f'{client_name}.ovpn'
        )

    except Exception as e:
        abort(500)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8443,
            ssl_context=('/etc/openvpn/portal/portal.crt',
                        '/etc/openvpn/portal/portal.key'))
EOF

    # Make app.py executable
    chmod +x "$APP_FILE" || error_exit "Failed to make app.py executable"

    # Verify Python syntax
    if ! python3 -m py_compile "$APP_FILE" &>/dev/null; then
        error_exit "Flask app has syntax errors"
    fi

    echo "✓ Flask application created successfully"
    echo "  - App file: $APP_FILE"
    echo "  - Secret key generated"
}

# Run Flask app creation
create_flask_app

################################################################################
# Password Authentication Setup (Task 2)
################################################################################

setup_portal_auth() {
    echo "Setting up portal authentication..."

    AUTH_FILE="/etc/openvpn/portal/auth.txt"

    # Install python3-bcrypt if not present
    if ! python3 -c "import bcrypt" &>/dev/null; then
        echo "Installing bcrypt module..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3-bcrypt || error_exit "Failed to install python3-bcrypt"
    fi

    # Check if auth file already exists (idempotency - preserve password)
    if [[ -f "$AUTH_FILE" ]]; then
        echo "✓ Portal password already configured, skipping"
        # Read existing password if stored separately, or skip displaying
        return 0
    fi

    # Generate random password
    PORTAL_PASSWORD=$(openssl rand -base64 16)

    # Generate bcrypt hash and store
    python3 -c "import bcrypt; print(bcrypt.hashpw('$PORTAL_PASSWORD'.encode(), bcrypt.gensalt()).decode())" > "$AUTH_FILE" || error_exit "Failed to generate password hash"

    # Set restrictive permissions
    chmod 600 "$AUTH_FILE" || error_exit "Failed to set auth.txt permissions"

    # Store password for display at end (temporary)
    echo "$PORTAL_PASSWORD" > /root/.openvpn-portal-password
    chmod 600 /root/.openvpn-portal-password

    echo "✓ Portal authentication configured"
    echo "  - Password hash stored in: $AUTH_FILE"

    # Create login.html template
    cat > /opt/openvpn-portal/templates/login.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenVPN Portal - Login</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .login-container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            width: 100%;
            max-width: 400px;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            color: #555;
            font-weight: 500;
        }
        input[type="password"] {
            width: 100%;
            padding: 12px;
            border: 2px solid #ddd;
            border-radius: 5px;
            font-size: 16px;
            transition: border-color 0.3s;
        }
        input[type="password"]:focus {
            outline: none;
            border-color: #667eea;
        }
        button {
            width: 100%;
            padding: 12px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 5px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s;
        }
        button:hover {
            transform: translateY(-2px);
        }
        .error {
            background-color: #fee;
            color: #c33;
            padding: 12px;
            border-radius: 5px;
            margin-bottom: 20px;
            border-left: 4px solid #c33;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <h1>OpenVPN Portal</h1>
        <p class="subtitle">Enter your password to access the dashboard</p>

        {% if error %}
        <div class="error">{{ error }}</div>
        {% endif %}

        <form method="POST" action="/login">
            <div class="form-group">
                <label for="password">Password</label>
                <input type="password" id="password" name="password" required autofocus>
            </div>
            <button type="submit">Login</button>
        </form>
    </div>
</body>
</html>
EOF

    echo "✓ Login page created"
}

# Run portal authentication setup
setup_portal_auth

################################################################################
# Dashboard Creation and Service Startup (Task 3)
################################################################################

finalize_portal() {
    echo "Finalizing web portal setup..."

    # Store server IP for dashboard display
    echo "$PUBLIC_IP" > /root/.openvpn-server-ip
    chmod 644 /root/.openvpn-server-ip

    # Create dashboard.html template
    cat > /opt/openvpn-portal/templates/dashboard.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenVPN Portal - Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: #f5f7fa;
            min-height: 100vh;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px 40px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        h1 {
            font-size: 24px;
        }
        .logout-link {
            color: white;
            text-decoration: none;
            padding: 8px 20px;
            border: 2px solid white;
            border-radius: 5px;
            transition: all 0.3s;
        }
        .logout-link:hover {
            background: white;
            color: #667eea;
        }
        .container {
            max-width: 1200px;
            margin: 40px auto;
            padding: 0 20px;
        }
        .card {
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.08);
            margin-bottom: 20px;
        }
        .card h2 {
            color: #333;
            margin-bottom: 15px;
            font-size: 20px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .info-item {
            padding: 15px;
            background: #f8f9fa;
            border-radius: 5px;
        }
        .info-label {
            color: #666;
            font-size: 14px;
            margin-bottom: 5px;
        }
        .info-value {
            color: #333;
            font-size: 18px;
            font-weight: 600;
            font-family: monospace;
        }
        .client-list-table {
            width: 100%;
            margin-top: 20px;
            border-collapse: collapse;
        }
        .client-list-table th {
            background: #f8f9fa;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #555;
            border-bottom: 2px solid #ddd;
        }
        .client-list-table td {
            padding: 12px;
            border-bottom: 1px solid #eee;
        }
        .client-list-table tbody tr:hover {
            background: #f8f9fa;
        }
        .btn {
            padding: 8px 16px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.2s;
            margin-right: 8px;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(102, 126, 234, 0.3);
        }
        .btn-download {
            background: #28a745;
            color: white;
        }
        .btn-download:hover {
            background: #218838;
        }
        .btn-delete {
            background: #dc3545;
            color: white;
        }
        .btn-delete:hover {
            background: #c82333;
        }
        .form-group {
            margin-bottom: 20px;
        }
        .form-group label {
            display: block;
            margin-bottom: 8px;
            color: #555;
            font-weight: 500;
        }
        .form-group input {
            width: 100%;
            max-width: 400px;
            padding: 12px;
            border: 2px solid #ddd;
            border-radius: 5px;
            font-size: 16px;
            transition: border-color 0.3s;
        }
        .form-group input:focus {
            outline: none;
            border-color: #667eea;
        }
        .form-group input.error {
            border-color: #dc3545;
        }
        .error-message {
            color: #dc3545;
            font-size: 14px;
            margin-top: 5px;
        }
        .success-message {
            background: #d4edda;
            color: #155724;
            padding: 12px 15px;
            border-radius: 5px;
            border-left: 4px solid #28a745;
            margin-bottom: 20px;
        }
        .alert-error {
            background: #f8d7da;
            color: #721c24;
            padding: 12px 15px;
            border-radius: 5px;
            border-left: 4px solid #dc3545;
            margin-bottom: 20px;
        }
        .empty-state {
            text-align: center;
            padding: 40px 20px;
            color: #666;
        }
        .empty-state-icon {
            font-size: 48px;
            margin-bottom: 16px;
        }
        .loading {
            text-align: center;
            padding: 20px;
            color: #666;
        }
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>OpenVPN Portal Dashboard</h1>
        <a href="/logout" class="logout-link">Logout</a>
    </div>

    <div class="container">
        <div id="message-container"></div>

        <div class="card">
            <h2>Server Information</h2>
            <div class="info-grid">
                <div class="info-item">
                    <div class="info-label">Public IP Address</div>
                    <div class="info-value">{{ server_ip }}</div>
                </div>
                <div class="info-item">
                    <div class="info-label">OpenVPN Port</div>
                    <div class="info-value">1194 UDP</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Portal Port</div>
                    <div class="info-value">8443 HTTPS</div>
                </div>
            </div>
        </div>

        <div class="card">
            <h2>VPN Clients</h2>
            <div id="client-list-container">
                <div class="loading">Loading clients...</div>
            </div>
        </div>

        <div class="card">
            <h2>Create New Client</h2>
            <form id="create-client-form">
                <div class="form-group">
                    <label for="client-name">Client Name</label>
                    <input
                        type="text"
                        id="client-name"
                        name="client_name"
                        pattern="[a-zA-Z0-9_-]+"
                        title="Only letters, numbers, dashes, and underscores allowed"
                        required
                        placeholder="e.g., laptop-john, phone-mary"
                    >
                    <div id="client-name-error" class="error-message hidden"></div>
                </div>
                <button type="submit" class="btn btn-primary">Create Client</button>
            </form>
        </div>
    </div>

    <script>
        // Format file size in human-readable format
        function formatFileSize(bytes) {
            if (bytes < 1024) return bytes + ' B';
            if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
            return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        }

        // Show message to user
        function showMessage(message, type = 'success') {
            const container = document.getElementById('message-container');
            const className = type === 'success' ? 'success-message' : 'alert-error';
            container.innerHTML = `<div class="${className}">${message}</div>`;
            setTimeout(() => {
                container.innerHTML = '';
            }, 5000);
        }

        // Load client list from API
        async function loadClients() {
            const container = document.getElementById('client-list-container');

            try {
                const response = await fetch('/api/clients/list');

                if (response.status === 401) {
                    window.location.href = '/login';
                    return;
                }

                if (!response.ok) {
                    throw new Error('Failed to load clients');
                }

                const data = await response.json();
                const clients = data.clients || [];

                if (clients.length === 0) {
                    container.innerHTML = `
                        <div class="empty-state">
                            <div class="empty-state-icon">📋</div>
                            <p>No VPN clients yet. Create one below to get started.</p>
                        </div>
                    `;
                } else {
                    let tableHtml = `
                        <table class="client-list-table">
                            <thead>
                                <tr>
                                    <th>Client Name</th>
                                    <th>File Size</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                    `;

                    clients.forEach(client => {
                        tableHtml += `
                            <tr>
                                <td>${client.name}</td>
                                <td>${formatFileSize(client.size)}</td>
                                <td>
                                    <button class="btn btn-download" onclick="downloadClient('${client.name}')">Download</button>
                                    <button class="btn btn-delete" onclick="deleteClient('${client.name}')">Delete</button>
                                </td>
                            </tr>
                        `;
                    });

                    tableHtml += `
                            </tbody>
                        </table>
                    `;
                    container.innerHTML = tableHtml;
                }
            } catch (error) {
                container.innerHTML = `<div class="alert-error">Error loading clients: ${error.message}</div>`;
            }
        }

        // Download client configuration
        function downloadClient(clientName) {
            window.location.href = `/download/${clientName}`;
        }

        // Delete client with confirmation
        async function deleteClient(clientName) {
            if (!confirm(`Are you sure you want to delete client "${clientName}"? This will revoke the certificate and remove the configuration file.`)) {
                return;
            }

            try {
                const response = await fetch('/api/clients/delete', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ client_name: clientName })
                });

                if (response.status === 401) {
                    window.location.href = '/login';
                    return;
                }

                const data = await response.json();

                if (!response.ok) {
                    showMessage(data.error || 'Failed to delete client', 'error');
                    return;
                }

                showMessage(`Client "${clientName}" deleted successfully`, 'success');
                loadClients();
            } catch (error) {
                showMessage(`Error deleting client: ${error.message}`, 'error');
            }
        }

        // Handle create client form submission
        document.getElementById('create-client-form').addEventListener('submit', async (e) => {
            e.preventDefault();

            const clientNameInput = document.getElementById('client-name');
            const clientName = clientNameInput.value.trim();
            const errorDiv = document.getElementById('client-name-error');

            // Clear previous errors
            errorDiv.classList.add('hidden');
            clientNameInput.classList.remove('error');

            // Validate client name
            if (!clientName) {
                errorDiv.textContent = 'Client name is required';
                errorDiv.classList.remove('hidden');
                clientNameInput.classList.add('error');
                return;
            }

            if (!/^[a-zA-Z0-9_-]+$/.test(clientName)) {
                errorDiv.textContent = 'Invalid client name. Use only letters, numbers, dashes, and underscores.';
                errorDiv.classList.remove('hidden');
                clientNameInput.classList.add('error');
                return;
            }

            try {
                const response = await fetch('/api/clients/create', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ client_name: clientName })
                });

                if (response.status === 401) {
                    window.location.href = '/login';
                    return;
                }

                const data = await response.json();

                if (!response.ok) {
                    showMessage(data.error || 'Failed to create client', 'error');
                    return;
                }

                showMessage(`Client "${clientName}" created successfully`, 'success');
                clientNameInput.value = '';
                loadClients();
            } catch (error) {
                showMessage(`Error creating client: ${error.message}`, 'error');
            }
        });

        // Load clients on page load
        loadClients();
    </script>
</body>
</html>
EOF

    echo "✓ Dashboard page created"

    # Add UFW rule for web portal
    if ! ufw status | grep -q "8443/tcp"; then
        ufw allow 8443/tcp comment 'OpenVPN Web Portal' || error_exit "Failed to allow portal port"
        echo "✓ Firewall rule added for port 8443"
    else
        echo "✓ Firewall rule for port 8443 already exists"
    fi

    # Enable and start the portal service
    echo "Starting web portal service..."
    systemctl enable openvpn-portal || error_exit "Failed to enable portal service"

    # Start or restart portal service (idempotent)
    if systemctl is-active --quiet openvpn-portal; then
        echo "  Portal already running, restarting to apply changes..."
        systemctl restart openvpn-portal || error_exit "Failed to restart portal service"
    else
        echo "  Starting portal for the first time..."
        systemctl start openvpn-portal || error_exit "Failed to start portal service"
    fi

    # Wait for service to start
    sleep 3

    # Verify service is running
    if ! systemctl is-active --quiet openvpn-portal; then
        error_exit "Portal service failed to start. Check: journalctl -u openvpn-portal -n 50"
    fi

    echo "✓ Web portal service started successfully"

    # Verify port is listening
    if ss -tlnp | grep -q ":8443"; then
        echo "✓ Portal listening on port 8443"
    else
        echo "Warning: Port 8443 not detected (service may still be starting)"
    fi
}

# Run portal finalization
finalize_portal

################################################################################
# Installation complete
################################################################################

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ "$IS_UPDATE" == "true" ]]; then
    echo "EasyOpenVPN Update Complete!"
else
    echo "EasyOpenVPN Installation Complete!"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "OpenVPN Server: $PUBLIC_IP:1194"
echo ""
echo "Web Portal: https://$PUBLIC_IP:8443"

# Display portal password
if [[ -f /root/.openvpn-portal-password ]]; then
    if [[ "$IS_UPDATE" == "true" ]]; then
        echo "Password: (unchanged from previous installation)"
    else
        PORTAL_PASS=$(cat /root/.openvpn-portal-password)
        echo "Password: $PORTAL_PASS"
        echo ""
        echo "SAVE THIS PASSWORD - you'll need it to manage clients!"
    fi
fi

echo ""
echo "Client configuration: $CLIENT_DIR/client1.ovpn"
echo ""
echo "Download this file and import it into your OpenVPN client:"
echo "  - Windows/Mac/Linux: OpenVPN GUI or OpenVPN Connect"
echo "  - iOS/Android: OpenVPN Connect app"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
