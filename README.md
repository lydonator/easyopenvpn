# EasyOpenVPN

## What This Is

One-line OpenVPN server installer for Linux VPS. Install with a single command, manage clients through a web portal, download configs and connect. Built for individuals who want commercial VPN provider simplicity on their own infrastructure.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/[user]/easyopenvpn/master/install.sh | sudo bash
```

Or download and inspect first:

```bash
wget https://raw.githubusercontent.com/[user]/easyopenvpn/master/install.sh
bash install.sh
```

Installation completes in 2-5 minutes. Portal credentials displayed at end.

## What You Get

- OpenVPN server on UDP 1194
- HTTPS web portal on port 8443
- Client management (create, download, delete)
- Platform-agnostic client configs (Windows, Mac, Linux, iOS, Android)
- Automatic firewall configuration
- Idempotent installer (safe to re-run for updates)

## Requirements

- Ubuntu 22.04+ or Debian 11+
- Fresh VPS with root access
- Public IP address
- Ports 1194/UDP and 8443/TCP available

## After Installation

1. Visit `https://YOUR_SERVER_IP:8443`
2. Accept self-signed certificate warning (expected)
3. Log in with displayed credentials
4. Create clients, download configs, connect

## Client Setup

**Windows/Mac/Linux:** Import .ovpn file into OpenVPN Connect
**iOS/Android:** Import via OpenVPN Connect app

## Security Notes

- Portal uses self-signed HTTPS certificate (no domain required)
- Change default password after first login (regenerate via installer)
- Portal sessions expire after 1 hour
- Client certificates use 2048-bit RSA keys

## Updates

Re-run installer to update web portal or apply fixes:

```bash
curl -fsSL https://raw.githubusercontent.com/[user]/easyopenvpn/master/install.sh | sudo bash
```

Existing clients and certificates are preserved.

## Troubleshooting

- **Portal not accessible:** Check firewall allows port 8443/TCP
- **Client can't connect:** Verify port 1194/UDP not blocked
- **Certificate error:** Normal with self-signed certs, proceed anyway
- **Forgot password:** Re-run installer, new password displayed

## Architecture

- OpenVPN 2.x with UDP transport
- Flask web portal (Python 3)
- Self-signed PKI via Easy-RSA
- Certificate revocation via CRL
- Session-based authentication (bcrypt)

## License

MIT
