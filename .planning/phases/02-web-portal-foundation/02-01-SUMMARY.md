# Phase 2 Plan 1: HTTPS Foundation & Service Setup Summary

**Established web portal infrastructure with Flask dependencies, SSL certificates, and systemd service**

## Accomplishments

- Added `install_web_dependencies()` function to install Python3, Flask, and related packages with idempotent checks
- Added `generate_portal_ssl()` function to create self-signed SSL certificates for HTTPS portal with proper permissions (600 for key, 644 for cert)
- Added `create_portal_service()` function to define systemd service for the web portal (loaded but not started until app.py exists)
- All functions follow Phase 1 installer patterns: idempotent operations, error handling, and clear user feedback

## Files Created/Modified

- `install.sh` - Added install_web_dependencies(), generate_portal_ssl(), create_portal_service()
- `/etc/openvpn/portal/portal.{key,crt}` - Self-signed SSL certificate (created at runtime)
- `/etc/systemd/system/openvpn-portal.service` - systemd service definition (created at runtime)
- `/opt/openvpn-portal/` - Web portal app directory (created at runtime)

## Decisions Made

- **Function placement:** Web dependencies installed early (after OpenVPN packages), SSL generation follows immediately, service creation happens after client generation but before completion message
- **Idempotency checks:** Each function checks if its artifacts already exist before performing operations
- **Service management:** Service file created and loaded (daemon-reload) but NOT enabled/started - waiting for Plan 2 to create app.py
- **Permissions:** Portal SSL key set to 600 (root only), certificate set to 644 (readable by all)

## Issues Encountered

None

## Next Step

Ready for 02-02-PLAN.md (Authentication & Portal UI)
