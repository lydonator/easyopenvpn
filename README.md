# EasyOpenVPN

## What This Is

One-line OpenVPN server installer for Linux VPS. Install with a single command, manage clients through a web portal, download configs and connect. Built for individuals who want commercial VPN provider simplicity on their own infrastructure.

## Why I built it?

Digital privacy should be accessible to everyone. As commercial VPN services face increasing regulatory challenges, self-hosted solutions become more important. This project makes running your own VPN server nearly as easy as subscribing to a commercial service, while giving you complete control over your data and infrastructure.

## Quick Start

**One-command install**:

```bash
curl -fsSL https://raw.githubusercontent.com/lydonator/easyopenvpn/master/install.sh | sudo bash
```

Or download and inspect first:

```bash
wget https://raw.githubusercontent.com/lydonator/easyopenvpn/master/install.sh
sudo bash install.sh
```

The installer is completely self-contained - it downloads Docker images from Docker Hub and generates all configuration files automatically.

Installation completes in 2-4 minutes. Portal credentials displayed at end.

## What You Get

- OpenVPN server on UDP 1194
- HTTPS web portal on port 443
- Client management (create, download, delete)
- Platform-agnostic client configs (Windows, Mac, Linux, iOS, Android)
- Automatic firewall configuration
- Idempotent installer (safe to re-run for updates)

## Requirements

- Ubuntu 22.04+ or Debian 11+ (should work on Ubuntu & Debian variants e.g Linux Mint)
- Fresh VPS with root access (will work on existing VPS, does not interfere with host OS install)
- Public IP address
- Ports 1194/UDP and 443/TCP available
- Docker Engine (auto-installed by script if missing)
- Docker Compose v2 (auto-installed by script if missing)

## After Installation

1. Visit `https://YOUR_SERVER_IP`
2. Accept self-signed certificate warning (expected)
3. Log in with displayed credentials
4. Create clients, download configs, connect

## Client Setup

**Windows/Mac/Linux:** Import .ovpn file into OpenVPN Connect.
**iOS/Android:** Import via OpenVPN Connect app

## Security Notes

- Portal uses self-signed HTTPS certificate (no domain required)
- Change default password after first login (regenerate via installer)
- Portal sessions expire after 1 hour
- Client certificates use 2048-bit RSA keys

## Updates

Re-run installer to update web portal or apply fixes:

```bash
curl -fsSL https://raw.githubusercontent.com/lydonator/easyopenvpn/master/install.sh | sudo bash
```

Existing clients and certificates are preserved.

## Troubleshooting

**Note:** This VPN uses zero-logging for privacy. No connection or access logs are stored. See [PRIVACY.md](PRIVACY.md) for details.

**Portal not accessible:**
- Check containers running: `docker ps` (should show easyopenvpn-server and easyopenvpn-portal)
- Check container health: `docker inspect easyopenvpn-portal | grep Status`
- Verify firewall allows port 443/TCP: `sudo ufw status`
- Test connectivity: `curl -k https://localhost` (from VPS)

**Client can't connect:**
- Check OpenVPN container running: `docker ps | grep openvpn`
- Check OpenVPN process: `docker exec easyopenvpn-server pgrep openvpn`
- Verify port 1194/UDP not blocked: `sudo ufw status`
- Test from VPS: `nc -u -v localhost 1194` (should connect)

**Certificate error in browser:**
- Normal with self-signed certs, proceed anyway (click "Advanced" → "Proceed")

**Forgot password:**
- Re-run installer: `bash install.sh`
- New password will be displayed and .env updated

**Container issues:**
- Restart containers: `docker compose restart`
- Check container status: `docker compose ps`
- Inspect container: `docker inspect easyopenvpn-server`

## Architecture

- **Containerized deployment** via Docker Compose
- **OpenVPN container:** Debian-based with OpenVPN 2.x, Easy-RSA PKI, automatic initialization
- **Portal container:** Python 3.11 Flask app with HTTPS and bcrypt authentication
- **Shared volumes:** PKI certificates, client configs, persistent data
- **Host networking:** IP forwarding and UFW firewall rules configured by installer
- **Self-signed certificates:** No domain required, generated automatically

## License

MIT
