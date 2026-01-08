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

# Idempotency check - check if OpenVPN is already installed and running
if systemctl is-active --quiet openvpn-server@server 2>/dev/null; then
    echo "═══════════════════════════════════════════════════════════════"
    echo "OpenVPN server is already installed and running."
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "To manage clients, use the web portal or re-run this script"
    echo "to add additional functionality."
    echo ""
    exit 0
fi

IS_INSTALLED=false

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

    # Copy Easy-RSA files from package location
    # Easy-RSA package installs to /usr/share/easy-rsa/
    if [[ -d /usr/share/easy-rsa ]]; then
        cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR/" || error_exit "Failed to copy Easy-RSA files"
    else
        error_exit "Easy-RSA not found in /usr/share/easy-rsa/"
    fi

    # Make easyrsa executable
    chmod +x "$EASYRSA_DIR/easyrsa" || error_exit "Failed to make easyrsa executable"

    # Initialize PKI structure
    cd "$EASYRSA_DIR" || error_exit "Failed to change to Easy-RSA directory"
    ./easyrsa init-pki || error_exit "Failed to initialize PKI"

    # Build Certificate Authority
    # Use EASYRSA_BATCH=1 to avoid interactive prompts
    # Use nopass to avoid password prompt (required for automated installer)
    EASYRSA_BATCH=1 ./easyrsa build-ca nopass || error_exit "Failed to build CA"

    # Verify CA created
    [[ -f pki/ca.crt ]] || error_exit "CA certificate not found after generation"
    [[ -f pki/private/ca.key ]] || error_exit "CA private key not found after generation"

    echo "✓ PKI initialized and CA generated"
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

    # Generate server certificate and key
    EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass || error_exit "Failed to generate server certificate"

    # Verify server certificate created
    [[ -f pki/issued/server.crt ]] || error_exit "Server certificate not found"
    [[ -f pki/private/server.key ]] || error_exit "Server private key not found"

    # Generate DH parameters (2048-bit)
    # This takes 2-5 minutes - inform user
    echo "Generating DH parameters (this may take several minutes)..."
    ./easyrsa gen-dh || error_exit "Failed to generate DH parameters"

    # Verify DH params created
    [[ -f pki/dh.pem ]] || error_exit "DH parameters not found"

    # Generate tls-crypt key
    # Use openvpn --genkey command (standard method)
    openvpn --genkey secret "$EASYRSA_DIR/pki/tc.key" || error_exit "Failed to generate tls-crypt key"

    # Verify tls-crypt key created
    [[ -f pki/tc.key ]] || error_exit "tls-crypt key not found"

    # Copy certificates to OpenVPN server directory
    mkdir -p "$OPENVPN_DIR" || error_exit "Failed to create OpenVPN directory"

    cp pki/ca.crt "$OPENVPN_DIR/" || error_exit "Failed to copy CA certificate"
    cp pki/issued/server.crt "$OPENVPN_DIR/" || error_exit "Failed to copy server certificate"
    cp pki/private/server.key "$OPENVPN_DIR/" || error_exit "Failed to copy server key"
    cp pki/dh.pem "$OPENVPN_DIR/" || error_exit "Failed to copy DH parameters"
    cp pki/tc.key "$OPENVPN_DIR/" || error_exit "Failed to copy tls-crypt key"

    # Set correct permissions
    chmod 600 "$OPENVPN_DIR/server.key" || error_exit "Failed to set server key permissions"
    chmod 600 "$OPENVPN_DIR/tc.key" || error_exit "Failed to set tls-crypt key permissions"

    echo "✓ Server certificates generated and installed"
}

# Run server certificate generation
generate_server_certs

################################################################################
# Installation complete
################################################################################

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Certificate generation complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  - OS: $ID $OS_VERSION"
echo "  - OpenVPN: Installed"
echo "  - Easy-RSA: Installed ($EASYRSA_PKG_DIR)"
echo "  - Public IP: $PUBLIC_IP"
echo "  - PKI: Initialized with CA certificate"
echo "  - Server certificates: Generated and installed"
echo ""
echo "Next steps will configure OpenVPN server and networking..."
echo ""
