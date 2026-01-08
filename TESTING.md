# Testing EasyOpenVPN

## Test Environment Requirements

- Clean Ubuntu 22.04 or Debian 11 VM/container
- Root access
- Internet connectivity
- At least 1GB RAM, 10GB disk

## Installation Test

### Fresh Install Test

1. Provision clean VM
2. Run: `curl -fsSL [url]/install.sh | bash`
3. Verify: Installation completes in 2-5 minutes
4. Verify: Credentials displayed at end
5. Verify: `systemctl status openvpn-server@server` shows active
6. Verify: `systemctl status openvpn-portal` shows active

### Idempotency Test

1. On existing installation, re-run: `bash install.sh`
2. Verify: Script detects update mode
3. Verify: Services restart gracefully
4. Verify: No errors, completes successfully
5. Verify: Existing clients still listed in portal

## Portal Tests

### Access Test

1. Visit `https://SERVER_IP:8443`
2. Accept self-signed certificate warning
3. Verify: Login page loads
4. Login with credentials
5. Verify: Dashboard displays server IP

### Session Test

1. Log in successfully
2. Navigate to different pages
3. Verify: No re-login required within 1 hour
4. Wait 61 minutes (or adjust server time)
5. Verify: Redirected to login on next request

## Client Management Tests

### Create Client

1. Enter client name (e.g., "laptop")
2. Click Create
3. Verify: Success message appears
4. Verify: Client appears in list with .ovpn file

### Download Client

1. Click download link for client
2. Verify: .ovpn file downloads
3. Verify: File contains `[remote SERVER_IP 1194]`
4. Verify: File contains embedded certificates

### Delete Client

1. Click delete for client
2. Confirm deletion
3. Verify: Client removed from list
4. Verify: Subsequent connection attempts fail (certificate revoked)

## Client Connection Tests

### Windows

1. Install OpenVPN Connect
2. Import .ovpn file
3. Connect
4. Verify: Connection successful, IP changed
5. Verify: Can browse internet through VPN

### Mac

1. Install Tunnelblick or OpenVPN Connect
2. Import .ovpn file
3. Connect
4. Verify: Connection successful, IP changed

### Linux

1. Install openvpn package
2. Run: `sudo openvpn --config client.ovpn`
3. Verify: Connection successful, routes added

### iOS

1. Install OpenVPN Connect from App Store
2. Import via Files app or AirDrop
3. Connect
4. Verify: Connection successful

### Android

1. Install OpenVPN Connect from Play Store
2. Import via file picker
3. Connect
4. Verify: Connection successful

## Security Tests

### Certificate Validation

1. Create client, download config
2. Inspect config: verify certs embedded
3. Verify: Certificate revocation works after deletion

### Authentication

1. Try accessing /dashboard without login
2. Verify: Redirected to /login
3. Try wrong password
4. Verify: Login fails with error message

### Path Traversal

1. Try downloading: `/api/download?file=../../../etc/passwd`
2. Verify: 400 error, invalid filename
3. Verify: Only .ovpn files from /root/openvpn-clients/ downloadable

## Edge Cases

### Invalid client names

- Special characters: `test@#$%.ovpn`
- Path traversal: `../../../etc/passwd`
- Empty name: `""`
- Very long name: 1000+ characters
- Expected: Validation errors, no crashes

### Network issues

- Installer runs with intermittent connectivity
- Expected: Fails gracefully with error message

### Duplicate clients

- Create client "test"
- Create client "test" again
- Expected: Clear error message (already exists or overwrite)

## Production Checklist

Before real-world deployment:

- [ ] Tested fresh install on Ubuntu 22.04
- [ ] Tested fresh install on Debian 11
- [ ] Tested idempotency (re-run installer)
- [ ] Tested portal access and authentication
- [ ] Tested client create/download/delete workflow
- [ ] Tested client connection on at least 2 platforms
- [ ] Tested certificate revocation after client deletion
- [ ] Tested session timeout (1 hour)
- [ ] Verified firewall rules created correctly
- [ ] Verified services auto-start on reboot
- [ ] Changed default portal password
- [ ] README.md accurate and complete

## Automated Testing Notes

This project intentionally uses manual testing for v1 to match the "simple as commercial VPN" philosophy. Automated testing would add complexity (Docker setup, test frameworks, CI/CD) that conflicts with the single-file installer approach.

For v2, consider:

- Vagrant/Docker test matrices
- ShellSpec or Bats for bash unit tests
- Selenium for portal testing
