# Privacy & Logging Policy

## Zero-Knowledge Architecture

EasyOpenVPN is configured for **zero logging** to ensure maximum privacy. No connection logs, traffic logs, or user activity is stored.

## What Is NOT Logged

### OpenVPN Server
- ❌ No connection logs (who connected, when, from where)
- ❌ No traffic logs (bandwidth, duration, destinations)
- ❌ No IP address assignments tracked
- ❌ No status logs maintained

**Configuration:** OpenVPN `verb 0` (errors only), no status file, no IP persistence.

### Web Portal
- ❌ No HTTP access logs (who logged in, downloaded configs, created clients)
- ❌ No application logs (user actions, timestamps)
- ❌ No error logs for user actions

**Configuration:** Gunicorn with `/dev/null` logging, critical-level only.

### Docker Containers
- ❌ No container stdout/stderr logs stored
- ❌ No Docker daemon logs for VPN traffic

**Configuration:** Docker logging driver set to `none`.

### System Logs
- ⚠️  Journald/syslog may still capture some startup messages
- ⚠️  UFW firewall logs are disabled, but iptables may log if configured

## What IS Logged (Minimal)

The only data retained is:

1. **PKI Certificates** - Necessary for VPN operation
   - CA certificate, server certificate, client certificates
   - Certificate revocation list (CRL)
   - These are cryptographic artifacts, not usage logs

2. **Client Config Files** - Stored in portal for download
   - `.ovpn` files for each client
   - No connection or usage data

3. **Critical Errors** - Only fatal errors that prevent service operation
   - No user activity or traffic information

## Additional Privacy Measures

### Disable System Logs (Optional)

If you want to ensure no system-level logging, run on your VPS:

```bash
# Disable journald for Docker containers
sudo mkdir -p /etc/systemd/system/docker.service.d/
cat << EOF | sudo tee /etc/systemd/system/docker.service.d/no-journald.conf
[Service]
Environment="DOCKER_OPTS=--log-driver=none"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

# Disable UFW logging (if enabled)
sudo ufw logging off
```

### Verify No Logs

Check that no logs are being written:

```bash
# Check Docker logs (should be empty/disabled)
docker logs easyopenvpn-server  # Should fail with "configured logging driver does not support reading"
docker logs easyopenvpn-portal  # Should fail with same message

# Check for OpenVPN log files (should not exist)
docker exec easyopenvpn-server ls -la /var/log/openvpn/
# Should show empty directory or no status.log/ipp.txt files

# Check journald logs (may show startup messages only)
journalctl -u docker -n 50
```

## Trust Model

This VPN server operates on a **zero-knowledge** basis:

- The server operator (you) **cannot see** who is connected
- The server operator **cannot see** what traffic is being routed
- The server operator **cannot see** when clients connect/disconnect
- No logs means **nothing to hand over** if compelled

## Caveats

1. **Your VPS provider** may log network traffic at the hypervisor/network level
2. **Destination websites** can see traffic originating from your VPS IP
3. **DNS queries** go to configured DNS server (8.8.8.8 by default) unless you change it
4. **Timestamps** in certificate generation are unavoidable (but don't show usage)

## For Maximum Privacy

Consider:
- Using a VPS provider that accepts cryptocurrency and doesn't require identification
- Running your own recursive DNS resolver instead of using 8.8.8.8
- Encrypting your VPS disk at rest
- Using Tor as an exit relay after the VPN (VPN → Tor chain)
- Rotating client certificates regularly

## Transparency

This is open source. Verify the configuration yourself:
- `openvpn/docker-entrypoint.sh` - OpenVPN config generation (verb 0, no logs)
- `portal/Dockerfile` - Gunicorn config (logging disabled)
- `docker-compose.yml` - Docker logging driver (none)

**No logging means no logs. Period.**
