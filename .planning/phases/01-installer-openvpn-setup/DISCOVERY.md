# Phase 1 Discovery: Installer & OpenVPN Setup

**Conducted:** 2026-01-08
**Depth:** Level 2 (Standard Research)

## OpenVPN Server Setup

### Required packages

**Core packages:**
- `openvpn` - The main OpenVPN server package (available in Ubuntu/Debian repositories)
  - Ubuntu 22.04 LTS: OpenVPN 2.5.9-2.5.11 (2.6.12 in backports)
  - Ubuntu 24.04 LTS: OpenVPN 2.6.9-2.6.14
- `easy-rsa` - Separate package for PKI management and certificate generation (required since Debian Jessie)
  - Current version: Easy-RSA 3.2.x (full compatibility with OpenSSL 3)

**Optional but recommended:**
- `tpm2-openssl` - For TPM 2.0 encryption support (Ubuntu systems with TPM hardware)

**Installation method:**
Use apt-get for Debian/Ubuntu: `apt-get install -y openvpn easy-rsa`

### Minimal viable configuration

**Essential server.conf settings:**
Based on official OpenVPN sample configurations, a minimal viable server configuration includes:

```
# Network configuration
port 1194
proto udp
dev tun
server 10.8.0.0 255.255.255.0

# Certificate/key files
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-crypt ta.key

# Security
cipher AES-128-GCM
auth SHA256
tls-version-min 1.2

# Networking
keepalive 10 120
persist-key
persist-tun

# Logging (optional but useful)
status /var/log/openvpn/openvpn-status.log
verb 3
```

**Key decisions:**
- **Default port**: UDP 1194 (standard OpenVPN port)
- **VPN subnet**: 10.8.0.0/24 (OpenVPN convention)
- **Protocol**: UDP (better performance, DCO-compatible)
- **Encryption**: AES-128-GCM (modern, DCO-compatible, default in recent versions)
- **TLS version**: 1.2 minimum (compatible with all OpenVPN 2.4+ clients)

**Performance note:**
Data Channel Offload (DCO) was merged into Linux kernel 6.16 (April 2025). When using compatible configurations (UDP + AES-128-GCM), OpenVPN automatically uses kernel acceleration for significantly improved performance.

### Network configuration

**Public IP detection methods:**

**Recommended approach - DNS-based (most reliable):**
```bash
dig +short myip.opendns.com @resolver1.opendns.com
```

**Why DNS over HTTP:**
- More robust than HTTP-based services (websites can close down or change format)
- Uses reputable DNS servers (OpenDNS, Google, Cloudflare)
- Less likely to fail unpredictably

**Alternative methods (fallback):**
```bash
curl -s ifconfig.me
curl -s icanhazip.com
wget -qO- http://ipecho.net/plain
```

**Firewall rules required:**

**Using UFW (Ubuntu's default):**

1. **Allow OpenVPN port:**
   ```bash
   ufw allow 1194/udp comment 'OpenVPN server'
   ```

2. **Enable IP forwarding:**
   Edit `/etc/sysctl.conf`:
   ```
   net.ipv4.ip_forward=1
   ```
   Apply: `sysctl -p`

3. **Enable packet forwarding in UFW:**
   Edit `/etc/default/ufw`:
   ```
   DEFAULT_FORWARD_POLICY="ACCEPT"
   ```

4. **Configure NAT/masquerading:**
   Edit `/etc/ufw/before.rules`, add to top (after header comments):
   ```
   # NAT table rules for OpenVPN
   *nat
   :POSTROUTING ACCEPT [0:0]
   -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
   COMMIT
   ```
   (Replace `eth0` with actual network interface)

5. **Reload UFW:**
   ```bash
   ufw disable
   ufw enable
   ```

**Critical note:**
NAT/masquerading is essential for clients to reach beyond the VPN server itself. Without it, clients can only communicate with the server, not the wider network or internet.

## Certificate Management

### Approach recommendation

**Use Easy-RSA 3 (strongly recommended over raw OpenSSL)**

**Rationale:**
- **Purpose-built for OpenVPN**: Designed specifically for OpenVPN PKI management
- **Simplified workflow**: Abstracts complex OpenSSL commands into simple operations
- **Best practices built-in**: Regularly updated security defaults
- **Active maintenance**: Maintained by OpenVPN development community
- **OpenSSL wrapper**: Uses OpenSSL as underlying engine, so you get the same security
- **Modern features**: Includes OpenVPN-specific commands like `gen-tls-crypt-key` and inline file generation

**When to use raw OpenSSL:**
Only if you need highly customized certificate properties not supported by Easy-RSA's configuration files. For a standard VPN installer, Easy-RSA is the clear choice.

### Certificate requirements

**Complete PKI structure:**

1. **CA (Certificate Authority)**
   - Files: `ca.crt` (public), `ca.key` (private)
   - Purpose: Signs all server and client certificates
   - Distribution: Public cert (`ca.crt`) distributed to all clients and server

2. **Server Certificate & Key**
   - Files: `server.crt` (public), `server.key` (private)
   - Purpose: Authenticates server to clients
   - Distribution: Server only

3. **Client Certificate & Key** (per client)
   - Files: `client.crt` (public), `client.key` (private)
   - Purpose: Authenticates client to server
   - Distribution: Each client gets unique cert/key pair
   - **Critical**: Always use unique common name for each client

4. **DH Parameters**
   - File: `dh.pem` (2048-bit or 4096-bit)
   - Purpose: Used during TLS handshake for key exchange
   - Distribution: Server only
   - Note: Not security-sensitive, can be generated during install

5. **TLS Crypt Key**
   - File: `ta.key` (shared secret)
   - Purpose: Encrypts control channel, provides DoS protection and obfuscation
   - Distribution: All clients and server
   - **Recommendation**: Use `tls-crypt` over `tls-auth`

**tls-crypt vs tls-auth:**
- **tls-auth**: Signs control channel packets (authentication only)
- **tls-crypt**: Signs AND encrypts control channel packets
- **tls-crypt advantages**:
  - Hides certificate information (more privacy)
  - Harder to identify traffic as OpenVPN (obfuscation)
  - Better DoS protection
  - Post-quantum resistance (if pre-shared keys kept secret)
- **Current default**: tls-crypt in OpenVPN 2.9+ (for new installations)

### Generation sequence

**Using Easy-RSA 3 - complete workflow:**

**Initial setup:**
```bash
# Make directory for Easy-RSA
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa

# Initialize PKI
./easyrsa init-pki
```

**1. Create Certificate Authority:**
```bash
# Build CA (creates ca.crt and ca.key)
./easyrsa build-ca nopass
# Use 'nopass' for automated installer (no passphrase prompt)
```

**2. Generate Server Certificate:**
```bash
# Generate server cert and key in one command
./easyrsa build-server-full server nopass
# Output: pki/issued/server.crt, pki/private/server.key
```

**3. Generate DH Parameters:**
```bash
# Generate 2048-bit DH params (faster, still secure)
./easyrsa gen-dh
# Output: pki/dh.pem
# Note: This can take several minutes
```

**4. Generate TLS Crypt Key:**
```bash
# Generate TLS crypt key
./easyrsa gen-tls-crypt-key
# Output: pki/tc.key
```

**5. Generate Client Certificate:**
```bash
# Generate client cert and key
./easyrsa build-client-full client1 nopass
# Output: pki/issued/client1.crt, pki/private/client1.key
```

**Complete file locations after generation:**
- CA cert: `pki/ca.crt`
- Server cert: `pki/issued/server.crt`
- Server key: `pki/private/server.key`
- DH params: `pki/dh.pem`
- TLS crypt: `pki/tc.key`
- Client cert: `pki/issued/client1.crt`
- Client key: `pki/private/client1.key`

**Installation locations:**
Copy generated files to OpenVPN directory:
```bash
cp pki/ca.crt /etc/openvpn/server/
cp pki/issued/server.crt /etc/openvpn/server/
cp pki/private/server.key /etc/openvpn/server/
cp pki/dh.pem /etc/openvpn/server/
cp pki/tc.key /etc/openvpn/server/
```

## Installer Patterns

### Structure recommendation

**Single-file installer approach (recommended for curl|bash pattern)**

**Rationale:**
- **Simplicity**: User runs one command, gets complete installation
- **Reliability**: No dependency on downloading additional scripts
- **Inspection**: User can easily review entire script before execution
- **No network dependency**: After initial download, works offline
- **Industry standard**: Used by Docker, NVM, Homebrew installers

**Script structure:**
```bash
#!/bin/bash
# Header with description and usage
# Variable declarations and configuration
# Function definitions (modular approach)
# Pre-flight checks (OS detection, root check, dependency check)
# Main installation logic
# Post-installation configuration
# Client file generation
# Cleanup and final instructions
```

**Idempotency approach:**

**Core principle:**
Script should be safely re-runnable without side effects. "Don't run code if the effect of the code is already present."

**Key patterns:**

1. **Check if already installed:**
   ```bash
   if systemctl is-active --quiet openvpn-server@server; then
       echo "OpenVPN already installed and running"
       # Offer to add client or exit
   fi
   ```

2. **Directory creation:**
   ```bash
   mkdir -p /etc/openvpn/server  # -p flag prevents error if exists
   ```

3. **File operations:**
   ```bash
   # Check before overwriting
   if [[ ! -f /etc/openvpn/server/server.conf ]]; then
       # Generate config
   fi
   ```

4. **Package installation:**
   ```bash
   if ! dpkg -s openvpn &>/dev/null; then
       apt-get install -y openvpn
   fi
   ```

5. **Symbolic links:**
   ```bash
   ln -sf source target  # -f removes existing link first
   ```

**Multi-file vs single-file:**
- **Single file**: Better for curl|bash pattern (recommended)
- **Multi-file**: Better for complex installers with plugins/modules
- **For Phase 1**: Single file is sufficient and preferred

### Distribution detection

**Modern standard: /etc/os-release**

This file is standardized across Linux distributions and contains all necessary information.

**Recommended detection code:**
```bash
#!/bin/bash

# Source os-release for distribution info
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    echo "Error: Cannot detect operating system"
    exit 1
fi

# Check for Ubuntu or Debian
if [[ "$OS" == "ubuntu" ]]; then
    echo "Detected Ubuntu $OS_VERSION"
    # Ubuntu-specific logic
elif [[ "$OS" == "debian" ]]; then
    echo "Detected Debian $OS_VERSION"
    # Debian-specific logic
else
    echo "Error: This script supports Ubuntu and Debian only"
    exit 1
fi
```

**Available variables in /etc/os-release:**
- `NAME` - Distribution name (e.g., "Ubuntu", "Debian GNU/Linux")
- `ID` - Distribution identifier (e.g., "ubuntu", "debian")
- `VERSION` - Human-readable version (e.g., "24.04 LTS (Noble Numbat)")
- `VERSION_ID` - Version number (e.g., "24.04", "12")
- `ID_LIKE` - Parent distributions (e.g., Ubuntu has "debian")
- `PRETTY_NAME` - Full description

**Version checking example:**
```bash
# Ensure Ubuntu 20.04 or newer
if [[ "$OS" == "ubuntu" ]] && [[ $(echo "$OS_VERSION >= 20.04" | bc) -eq 1 ]]; then
    echo "Ubuntu version supported"
fi
```

**Why /etc/os-release:**
- Standardized across modern distributions
- More reliable than `lsb_release` (not always installed)
- More portable than distribution-specific files
- Easy to parse in bash (just source it)

### Error handling

**Community divided on approach:**

**Option 1: Strict mode with set -e (use with caution)**

```bash
#!/bin/bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# Script exits immediately on any error
```

**Pros:**
- Automatic error detection
- Fails fast on problems
- Less error handling code needed

**Cons:**
- Unpredictable behavior (many false positives)
- Different behavior across Bash versions
- Commands in conditionals are immune (confusing)
- Commands in pipelines (except last) are immune
- May exit at unexpected times

**Community recommendation:** Many experienced developers avoid `set -e` due to its complex and unreliable behavior.

**Option 2: Explicit error handling (recommended for installers)**

```bash
#!/bin/bash
# No set -e, explicit checks instead

function install_package() {
    apt-get update || {
        echo "Error: Failed to update package list"
        return 1
    }

    apt-get install -y openvpn || {
        echo "Error: Failed to install OpenVPN"
        return 1
    }
}

# Call with error check
if ! install_package; then
    echo "Installation failed, exiting"
    exit 1
fi
```

**Recommended approach for Phase 1:**

```bash
#!/bin/bash

# Enable pipefail (fail if any command in pipe fails)
set -o pipefail

# Error handling function
error_exit() {
    echo "Error: $1" >&2
    exit "${2:-1}"
}

# Trap for cleanup on error
cleanup() {
    # Remove partial installations, temp files
    :
}
trap cleanup EXIT

# Check command success explicitly
apt-get update || error_exit "Failed to update package list"
apt-get install -y openvpn easy-rsa || error_exit "Failed to install packages"

# Allow expected failures
command_that_might_fail || true

# Check critical conditions
[[ -f /etc/openvpn/server/server.conf ]] || error_exit "Configuration file not found"
```

**Best practices:**
1. **Use `set -o pipefail`** - Catch pipe failures
2. **Avoid `set -e`** - Too unreliable for production installers
3. **Explicit error checking** - Check return codes of critical commands
4. **Error messages** - Clear, actionable error messages
5. **Cleanup traps** - Use `trap` for cleanup on exit/error
6. **Fail fast** - Exit immediately on critical errors
7. **Allow expected failures** - Use `|| true` for non-critical commands
8. **Use ShellCheck** - Validate script for common errors

**Example from successful installers:**
Both Docker and Angristan's OpenVPN installer use explicit error handling with custom error functions rather than relying on `set -e`.

## Recommendations

### For planning:

**1. Use Easy-RSA 3 for all certificate operations**
- Simpler, safer, actively maintained
- Purpose-built for OpenVPN
- Automated installer can call Easy-RSA commands in sequence
- Generate all certificates during install (including first client)

**2. Single-file bash installer with explicit error handling**
- No `set -e` - use explicit checks with `|| error_exit "message"`
- Use `set -o pipefail` to catch pipeline failures
- Modular functions for each major step
- Clear error messages for debugging

**3. Make installer idempotent**
- Check if OpenVPN already installed before proceeding
- Use `mkdir -p`, `ln -sf`, and existence checks
- Allow running script multiple times safely
- Offer to generate additional client configs if already installed

**4. Use tls-crypt (not tls-auth)**
- Better security (encryption + authentication)
- Better privacy (hides certificates)
- Default in modern OpenVPN
- Generate during Easy-RSA setup

**5. Detect public IP via DNS (with HTTP fallback)**
- Primary: `dig +short myip.opendns.com @resolver1.opendns.com`
- Fallback: `curl -s ifconfig.me`
- Fail gracefully if both fail (prompt user for IP)

**6. Configure UFW firewall automatically**
- Enable IP forwarding in sysctl
- Allow UDP 1194
- Configure NAT/masquerading in UFW
- Detect primary network interface automatically

**7. Use systemd service management**
- Place config in `/etc/openvpn/server/server.conf`
- Enable service: `systemctl enable openvpn-server@server`
- Start service: `systemctl start openvpn-server@server`
- No `user`/`group` directives in config (systemd handles privilege dropping)

**8. Generate client config file automatically**
- Create inline client.ovpn with embedded certificates
- Makes client setup truly zero-touch
- Easy-RSA 3 supports inline file generation
- Include all necessary directives and keys in single file

### Pitfalls to avoid:

**1. Certificate generation errors:**
- Don't use same common name for multiple clients
- Don't skip DH parameter generation (required for TLS)
- Don't forget to copy certificates to correct locations
- Don't use weak DH parameters (minimum 2048-bit)

**2. Firewall misconfiguration:**
- Don't forget NAT/masquerading (clients won't reach internet)
- Don't forget IP forwarding (packets won't route)
- Don't forget to reload UFW after rule changes
- Don't assume firewall is disabled (must configure properly)

**3. Error handling mistakes:**
- Don't rely on `set -e` alone (too unreliable)
- Don't ignore command return codes
- Don't skip pre-flight checks (OS version, root user, etc.)
- Don't leave partial installations on failure (use cleanup trap)

**4. Network detection issues:**
- Don't rely on single IP detection method (have fallbacks)
- Don't hardcode network interface names (detect dynamically)
- Don't assume eth0 (modern systems use predictable names like enp0s3)

**5. Idempotency failures:**
- Don't use `mkdir` without `-p` flag
- Don't overwrite existing configs without checking
- Don't fail if already installed (detect and offer options)

**6. Security weaknesses:**
- Don't use weak ciphers (use AES-128-GCM or better)
- Don't use tls-auth instead of tls-crypt (less secure)
- Don't use TLS 1.0/1.1 (minimum 1.2)
- Don't skip certificate validation

**7. User experience issues:**
- Don't leave users without clear next steps
- Don't forget to display client config file location
- Don't make users manually copy files to clients
- Don't skip validation that service started successfully

**8. curl|bash specific:**
- Security risk: Script can be modified mid-download
- Trust required: Users must trust your domain
- Mitigation: Keep script simple, auditable, open source
- Alternative: Provide checksums for verification (but defeats one-line install)

## Sources

**OpenVPN Installation & Configuration:**
- [OpenVPN - Debian Wiki](https://wiki.debian.org/OpenVPN)
- [How to install and use OpenVPN - Ubuntu Server documentation](https://documentation.ubuntu.com/server/how-to/security/install-openvpn/)
- [GitHub - angristan/openvpn-install](https://github.com/angristan/openvpn-install)
- [Ubuntu Package Search - openvpn](https://packages.ubuntu.com/openvpn)
- [How to install and setup the OpenVPN server on Ubuntu/Debian - GeeksforGeeks](https://www.geeksforgeeks.org/installation-guide/how-to-install-and-setup-the-openvpn-server-on-ubuntu-debian/)
- [Installing OpenVPN - OpenVPN Community](https://openvpn.net/community-docs/installing-openvpn.html)

**OpenVPN Configuration Files:**
- [openvpn/sample/sample-config-files/server.conf - GitHub](https://github.com/OpenVPN/openvpn/blob/master/sample/sample-config-files/server.conf)
- [Creating Configuration Files for Server and Clients - OpenVPN](https://openvpn.net/community-docs/creating-configuration-files-for-server-and-clients.html)
- [OpenVPN Example Configurations](https://www.cs.put.poznan.pl/csobaniec/examples/openvpn/)

**Public IP Detection:**
- [How To Find My Public IP Address From Linux CLI - nixCraft](https://www.cyberciti.biz/faq/how-to-find-my-public-ip-address-from-command-line-on-a-linux/)
- [How to Get Your Public IP in a Linux Bash Script - How-To Geek](https://www.howtogeek.com/839170/how-to-get-your-public-ip-in-a-linux-bash-script/)
- [Get External IP Address in a Shell Script - Baeldung](https://www.baeldung.com/linux/get-external-ip-shell-script)
- [4 Ways to Find Server Public IP Address in Linux Terminal - TecMint](https://www.tecmint.com/find-linux-server-public-ip-address/)

**Firewall Configuration:**
- [Firewall - Ubuntu Server documentation](https://documentation.ubuntu.com/server/how-to/security/firewalls/)
- [How To Configure Firewall with UFW on Ubuntu 20.04 LTS - nixCraft](https://www.cyberciti.biz/faq/how-to-configure-firewall-with-ufw-on-ubuntu-20-04-lts/)
- [How to set up and configure an OpenVPN Server on Ubuntu - DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-set-up-and-configure-an-openvpn-server-on-ubuntu-20-04)

**Certificate Management:**
- [Setting Up Your Own Certificate Authority (CA) - OpenVPN](https://openvpn.net/community-docs/setting-up-your-own-certificate-authority--ca--and-generating-certificates-and-keys-for-an-openvpn-server-and-multiple-clients.html)
- [Easy-RSA - ArchWiki](https://wiki.archlinux.org/title/Easy-RSA)
- [Using EasyRSA Version 3.x to Generate Certificates for OpenVPN Tunnels - HMS Support](https://support.hms-networks.com/hc/en-us/articles/27220858307986-Using-EasyRSA-Version-3-x-to-Generate-Certificates-for-OpenVPN-Tunnels)
- [EasyRSA3-OpenVPN-Howto - OpenVPN Community](https://community.openvpn.net/openvpn/wiki/EasyRSA3-OpenVPN-Howto)
- [easy-rsa/README.quickstart.md - GitHub](https://github.com/OpenVPN/easy-rsa/blob/master/README.quickstart.md)
- [Releases - OpenVPN/easy-rsa - GitHub](https://github.com/OpenVPN/easy-rsa/releases)

**TLS Security:**
- [TLS Control Channel Security in Access Server - OpenVPN](https://openvpn.net/as-docs/tls-control-channel.html)
- [Samples could use tls-crypt over tls-auth - GitHub Issue](https://github.com/OpenVPN/openvpn/issues/757)
- [DDoS prevention. tls-auth vs tls-crypt - OpenVPN Support Forum](https://forums.openvpn.net/viewtopic.php?t=29188)
- [Hardening OpenVPN Security - OpenVPN Community](https://openvpn.net/community-resources/hardening-openvpn-security/)

**Bash Installer Best Practices:**
- [5 Ways to Deal With the install.sh Curl Pipe Bash problem - Chef Blog](https://www.chef.io/blog/5-ways-to-deal-with-the-install-sh-curl-pipe-bash-problem)
- [Is it a bad idea to pipe a script from curl to your shell? - Linux Systems](https://linux.codidact.com/posts/292138)
- [Piping curl to bash: Convenient but risky - Sasha Vinčić](https://sasha.vincic.org/blog/2024/09/piping-curl-to-bash-convenient-but-risky)

**Bash Error Handling:**
- [Bash Error Handling - shell options -e/errexit - GitHub Gist](https://gist.github.com/bkahlert/08f9ec3b8453db5824a0aa3df6a24cb4)
- [Robust error handling in Bash - DEV Community](https://dev.to/banks/stop-ignoring-errors-in-bash-3co5)
- [BashFAQ/105 - Greg's Wiki](https://mywiki.wooledge.org/BashFAQ/105)
- [Learn Bash error handling by example - Red Hat](https://www.redhat.com/en/blog/bash-error-handling)
- [Writing Robust Bash Shell Scripts - David Pashley](https://www.davidpashley.com/articles/writing-robust-shell-scripts/)

**Idempotency:**
- [How to write idempotent Bash scripts - Arslan](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/)
- [GitHub - metaist/idempotent-bash](https://github.com/metaist/idempotent-bash)
- [Bash Bits: Check if a program is installed - Raymii.org](https://raymii.org/s/snippets/Bash_Bits_Check_if_command_is_available.html)

**Distribution Detection:**
- [How to check os version in Linux command line - nixCraft](https://www.cyberciti.biz/faq/how-to-check-os-version-in-linux-command-line/)
- [How To Find Out My Linux Distribution Name and Version - nixCraft](https://www.cyberciti.biz/faq/find-linux-distribution-name-version-number/)
- [Find Out Linux Distro Through the Command Line - Baeldung](https://www.baeldung.com/linux/detect-distro)

**Installer Examples:**
- [GitHub - nvm-sh/nvm: Node Version Manager](https://github.com/nvm-sh/nvm)
- [GitHub - docker/docker-install: Docker installation script](https://github.com/docker/docker-install)
- [angristan/openvpn-install.sh - GitHub](https://github.com/angristan/openvpn-install/blob/master/openvpn-install.sh)

**Systemd Service Management:**
- [Systemd - OpenVPN Community](https://community.openvpn.net/openvpn/wiki/Systemd)
- [Autostart OpenVPN in systemd (Ubuntu) - IVPN Help](https://www.ivpn.net/knowledgebase/linux/linux-autostart-openvpn-in-systemd-ubuntu/)
- [openvpn/distro/systemd/README.systemd - GitHub](https://github.com/OpenVPN/openvpn/blob/master/distro/systemd/README.systemd)
- [Service - OpenVPN - Ubuntu](https://ubuntu.com/server/docs/service-openvpn)
