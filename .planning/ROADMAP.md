# Roadmap: EasyOpenVPN

## Overview

Transform a blank VPS into a fully functional VPN server with a single curl command. Users install OpenVPN through an automated script, then manage all clients through a secure web portal. The journey: installer foundation → web interface → client lifecycle management → production-ready validation.

## Domain Expertise

None

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Installer & OpenVPN Setup** - Curl | bash installer with automated OpenVPN server configuration
- [ ] **Phase 2: Web Portal Foundation** - HTTPS web interface with password authentication and session management
- [ ] **Phase 3: Client Management** - Create/delete clients and generate platform-agnostic VPN configs
- [ ] **Phase 4: Testing & Polish** - Cross-platform validation and production readiness

## Phase Details

### Phase 1: Installer & OpenVPN Setup
**Goal**: Single-command installer that provisions a working OpenVPN server with self-signed certificates
**Depends on**: Nothing (first phase)
**Research**: Likely (OpenVPN server setup, installer patterns)
**Research topics**: OpenVPN server configuration on Ubuntu/Debian, bash installer best practices, self-signed certificate generation with OpenSSL
**Plans**: TBD

Plans:
- (To be defined during phase planning)

### Phase 2: Web Portal Foundation
**Goal**: Secure web portal with HTTPS, password authentication, and session management
**Depends on**: Phase 1
**Research**: Likely (web framework choice, HTTPS setup)
**Research topics**: Lightweight web frameworks for Linux, HTTPS setup with self-signed certificates, session management patterns
**Plans**: TBD

Plans:
- (To be defined during phase planning)

### Phase 3: Client Management
**Goal**: Full client lifecycle through web UI - create, configure, download, delete
**Depends on**: Phase 2
**Research**: Likely (client config format, platform requirements)
**Research topics**: OpenVPN client config format, platform-specific config differences (Windows/Mac/Linux/iOS/Android)
**Plans**: TBD

Plans:
- (To be defined during phase planning)

### Phase 4: Testing & Polish
**Goal**: Production-ready system validated across all target platforms
**Depends on**: Phase 3
**Research**: Unlikely (validation using established patterns)
**Plans**: TBD

Plans:
- (To be defined during phase planning)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Installer & OpenVPN Setup | 3/4 | In progress | - |
| 2. Web Portal Foundation | 0/TBD | Not started | - |
| 3. Client Management | 0/TBD | Not started | - |
| 4. Testing & Polish | 0/TBD | Not started | - |
