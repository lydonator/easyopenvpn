#!/bin/bash

################################################################################
# EasyOpenVPN Container Installer - curl | bash OpenVPN server setup
#
# Description:
#   Automated installer that deploys containerized OpenVPN server with
#   web portal using Docker Compose.
#
# Usage:
#   curl -fsSL https://your-domain.com/install.sh | bash
#   OR
#   bash install.sh (if downloaded locally)
#
# Requirements:
#   - Ubuntu 22.04+ or Debian 11+
#   - Run as root
#   - Internet connectivity
#
# What it does:
#   1. Installs Docker Engine and Docker Compose v2
#   2. Configures host networking (IP forwarding, firewall)
#   3. Detects public IP address
#   4. Prompts for portal password and generates environment variables
#   5. Deploys OpenVPN and portal containers using docker-compose
#
################################################################################

# Error handling setup
set -e           # Exit on any error
set -o pipefail  # Catch pipeline failures

# Error handling function
error_exit() {
    echo "Error: $1" >&2
    exit "${2:-1}"
}

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
# Host Network Configuration for Containers
################################################################################

configure_host_networking() {
    echo "Configuring host networking for containers..."

    # Task 1: Configure UFW firewall rules for OpenVPN port
    # Note: Portal port configured later after port selection
    if command -v ufw &>/dev/null; then
        echo "  Configuring firewall rules for OpenVPN..."
        ufw allow 1194/udp comment 'OpenVPN container' 2>/dev/null || true

        if ufw status | grep -q "Status: active"; then
            ufw reload >/dev/null 2>&1
            echo "✓ Firewall rule configured for OpenVPN"
        else
            echo "⚠ UFW installed but inactive. Please enable UFW manually: ufw enable"
        fi
    else
        echo "⚠ UFW not installed, skipping firewall configuration"
    fi

    # Task 2: Enable IP forwarding for VPN routing
    echo "  Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    # Persist IP forwarding on boot
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    echo "✓ IP forwarding enabled"

    # Configure UFW forward policy for container traffic
    if [[ -f /etc/default/ufw ]]; then
        echo "  Configuring UFW forward policy for container traffic..."
        sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

        if ufw status | grep -q "Status: active"; then
            ufw reload >/dev/null 2>&1
        fi
        echo "✓ UFW forward policy configured"
    fi

    # Task 3: Configure UFW routing rules for VPN tunnel traffic
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        echo "  Configuring UFW routing rules for VPN tunnel..."

        # Detect the default network interface (internet-facing)
        DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)

        if [[ -n "$DEFAULT_IFACE" ]]; then
            # Allow VPN traffic to be forwarded between tun0 and internet interface
            ufw route allow in on tun0 out on "$DEFAULT_IFACE" comment 'VPN to internet' >/dev/null 2>&1 || true
            ufw route allow in on "$DEFAULT_IFACE" out on tun0 comment 'Internet to VPN' >/dev/null 2>&1 || true

            if ufw status | grep -q "Status: active"; then
                ufw reload >/dev/null 2>&1
            fi
            echo "✓ UFW VPN routing rules configured (tun0 ↔ $DEFAULT_IFACE)"
        else
            echo "⚠ Could not detect default network interface, skipping UFW route rules"
        fi
    fi

    echo "✓ Host networking configured for containers"
}

# Run host network configuration
configure_host_networking

################################################################################
# Public IP Detection
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
# Portal Port Selection
################################################################################

select_portal_port() {
    echo "Checking portal port availability..."

    # Check if port 443 is in use
    if ss -tulpn | grep -q ":443 "; then
        echo ""
        echo "⚠ Port 443 is already in use (likely web server)"
        echo ""
        echo "Please choose an alternate port for the web portal:"
        read -p "Portal port [default: 8443]: " PORTAL_PORT
        PORTAL_PORT=${PORTAL_PORT:-8443}

        # Validate port number
        if ! [[ "$PORTAL_PORT" =~ ^[0-9]+$ ]] || [ "$PORTAL_PORT" -lt 1 ] || [ "$PORTAL_PORT" -gt 65535 ]; then
            error_exit "Invalid port number: $PORTAL_PORT"
        fi

        # Check if chosen port is also in use
        if ss -tulpn | grep -q ":$PORTAL_PORT "; then
            error_exit "Port $PORTAL_PORT is also in use. Please choose a different port."
        fi

        echo "✓ Portal will use port $PORTAL_PORT"
    else
        PORTAL_PORT=443
        echo "✓ Port 443 available, portal will use standard HTTPS port"
    fi
}

# Run portal port selection
select_portal_port

################################################################################
# Portal Firewall Configuration
################################################################################

configure_portal_firewall() {
    # Configure UFW to allow the selected portal port
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        echo "Configuring firewall for portal port $PORTAL_PORT..."
        ufw allow $PORTAL_PORT/tcp comment 'Web portal container' 2>/dev/null || true
        ufw reload >/dev/null 2>&1
        echo "✓ Firewall configured for portal on port $PORTAL_PORT"
    fi
}

# Run portal firewall configuration
configure_portal_firewall

################################################################################
# Password Hash Generation
################################################################################

generate_password_hash() {
    echo "Setting up portal password..."

    # Check if bcrypt is available (for hash generation)
    if ! command -v python3 &>/dev/null; then
        echo "Installing python3..."
        apt-get update && apt-get install -y python3 python3-bcrypt || error_exit "Failed to install python3"
    fi

    if ! python3 -c "import bcrypt" &>/dev/null; then
        echo "Installing bcrypt module..."
        apt-get install -y python3-bcrypt || error_exit "Failed to install python3-bcrypt"
    fi

    # Prompt for portal password
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Portal Password Setup"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Please enter a password for the web portal (or press Enter for random):"
    read -s -p "Password: " PORTAL_PASSWORD
    echo ""

    # If empty, generate random password
    if [[ -z "$PORTAL_PASSWORD" ]]; then
        PORTAL_PASSWORD=$(openssl rand -base64 16)
        echo "✓ Generated random password: $PORTAL_PASSWORD"
        echo "  SAVE THIS PASSWORD - you'll need it to access the portal!"
        echo ""
    fi

    # Generate bcrypt hash
    PORTAL_PASSWORD_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw('$PORTAL_PASSWORD'.encode(), bcrypt.gensalt()).decode())")

    echo "✓ Password hash generated"
}

# Run password hash generation
generate_password_hash

################################################################################
# Environment File Generation
################################################################################

generate_env_file() {
    echo "Generating environment configuration..."

    # Generate session secret
    SESSION_SECRET=$(openssl rand -hex 32)

    # Create .env file
    cat > .env <<EOF
# EasyOpenVPN Environment Configuration
# Generated: $(date)

# Server public IP address
SERVER_IP=$PUBLIC_IP

# Portal authentication
PORTAL_PASSWORD_HASH=$PORTAL_PASSWORD_HASH

# Flask session secret
SESSION_SECRET=$SESSION_SECRET
EOF

    # Set secure permissions
    chmod 600 .env

    # Fix ownership if script was run with sudo
    if [[ -n "$SUDO_USER" ]]; then
        chown "$SUDO_USER:$SUDO_USER" .env
        echo "✓ Environment file created: .env (owned by $SUDO_USER)"
    else
        echo "✓ Environment file created: .env"
    fi
}

# Run environment file generation
generate_env_file

################################################################################
# Docker Compose File Generation
################################################################################

generate_docker_compose() {
    echo "Generating docker-compose.yml..."

    cat > docker-compose.yml <<EOF
services:
  openvpn:
    image: lydo/easyopenvpn-server:latest
    container_name: easyopenvpn-server
    network_mode: host
    cap_add:
      - NET_ADMIN
      - MKNOD
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - openvpn-pki:/etc/openvpn/easy-rsa
      - openvpn-config:/etc/openvpn/server
    environment:
      - SERVER_IP=\${SERVER_IP}
      - VPN_SUBNET=10.8.0.0
      - VPN_NETMASK=255.255.255.0
      - VPN_PORT=1194
      - VPN_PROTOCOL=udp
      - DNS_SERVER=8.8.8.8
    restart: unless-stopped
    logging:
      driver: none
    healthcheck:
      test: ["CMD", "pgrep", "-x", "openvpn"]
      interval: 30s
      timeout: 5s
      retries: 3

  portal:
    image: lydo/easyopenvpn-portal:latest
    container_name: easyopenvpn-portal
    depends_on:
      - openvpn
    ports:
      - "${PORTAL_PORT}:443/tcp"
    volumes:
      - openvpn-pki:/etc/openvpn/easy-rsa
      - portal-certs:/app/certs
      - portal-data:/app/data
    environment:
      - PORTAL_PASSWORD_HASH=\${PORTAL_PASSWORD_HASH}
      - SESSION_SECRET=\${SESSION_SECRET}
      - SERVER_IP=\${SERVER_IP}
    restart: unless-stopped
    logging:
      driver: none

volumes:
  openvpn-pki:
  openvpn-config:
  openvpn-logs:
  portal-certs:
  portal-data:
EOF

    echo "✓ docker-compose.yml generated"
}

# Run docker-compose file generation
generate_docker_compose

################################################################################
# Container Deployment
################################################################################

deploy_containers() {
    echo "Deploying containers..."

    # Check if containers already exist
    if docker compose ps 2>/dev/null | grep -q "easyopenvpn"; then
        echo ""
        echo "⚠ Warning: Existing containers detected"
        echo ""
        read -p "Delete existing containers and volumes? This will erase all data! (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Removing existing containers and volumes..."
            docker compose down -v || error_exit "Failed to remove existing containers"
            echo "✓ Existing containers removed"
        else
            echo "Aborting installation."
            exit 0
        fi
    fi

    # Pull images from Docker Hub
    echo "Pulling container images from Docker Hub..."
    docker compose pull || error_exit "Failed to pull container images"
    echo "✓ Container images pulled"

    # Start containers
    echo "Starting containers..."
    docker compose up -d || error_exit "Failed to start containers"
    echo "✓ Containers started"

    # Wait for containers to initialize
    echo "Waiting for containers to initialize..."
    sleep 10

    # Check container status
    echo ""
    echo "Container status:"
    docker compose ps

    # Check if containers are running
    if ! docker compose ps | grep -q "easyopenvpn-server.*Up"; then
        echo ""
        echo "⚠ Warning: OpenVPN container may not be running properly"
        echo "Check logs: docker compose logs openvpn"
    fi

    if ! docker compose ps | grep -q "easyopenvpn-portal.*Up"; then
        echo ""
        echo "⚠ Warning: Portal container may not be running properly"
        echo "Check logs: docker compose logs portal"
    fi
}

# Run container deployment
deploy_containers

################################################################################
# Installation Complete
################################################################################

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "EasyOpenVPN Installation Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "OpenVPN Server: $PUBLIC_IP:1194"
echo ""
if [[ "$PORTAL_PORT" == "443" ]]; then
    echo "Web Portal: https://$PUBLIC_IP"
else
    echo "Web Portal: https://$PUBLIC_IP:$PORTAL_PORT"
fi
if [[ -n "$PORTAL_PASSWORD" ]]; then
    echo "Password: $PORTAL_PASSWORD"
fi
echo ""
echo "Use the web portal to create and manage VPN client certificates."
echo ""
echo "Useful commands:"
echo "  - Stop containers: docker compose stop"
echo "  - Start containers: docker compose start"
echo "  - Restart containers: docker compose restart"
echo "  - Remove containers: docker compose down"
echo "  - Remove containers + volumes: docker compose down -v"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
