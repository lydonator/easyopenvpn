# Roadmap: EasyOpenVPN

## Overview

Transform a blank VPS into a fully functional VPN server with a single curl command. Users install OpenVPN through an automated script, then manage all clients through a secure web portal. The journey: installer foundation → web interface → client lifecycle management → production-ready validation → containerized deployment.

## Milestones

- ✅ **v1.0 MVP** - Phases 1-4 (shipped 2026-01-08)
- 🚧 **v1.1 Docker Upgrade** - Phases 5-7 (in progress)

## Domain Expertise

None

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Installer & OpenVPN Setup** - Curl | bash installer with automated OpenVPN server configuration
- [x] **Phase 2: Web Portal Foundation** - HTTPS web interface with password authentication and session management
- [x] **Phase 3: Client Management** - Create/delete clients and generate platform-agnostic VPN configs
- [x] **Phase 4: Testing & Polish** - Cross-platform validation and production readiness
- [x] **Phase 5: Docker Prerequisites & Host Setup** - Auto-install Docker/Compose, configure host networking for containers
- [x] **Phase 6: Containerized OpenVPN & Portal** - Dockerfile, docker-compose orchestration, containerized services
- [ ] **Phase 7: Docker Testing & Documentation** - Container-specific testing, updated documentation

## Phase Details

<details>
<summary>✅ v1.0 MVP (Phases 1-4) - SHIPPED 2026-01-08</summary>

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
- [x] 02-01: HTTPS Foundation & Service Setup - Flask dependencies, SSL certificates, systemd service
- [x] 02-02: Authentication & Portal UI - Flask app with bcrypt auth, login/dashboard pages, systemd integration

### Phase 3: Client Management
**Goal**: Full client lifecycle through web UI - create, configure, download, delete
**Depends on**: Phase 2
**Research**: Likely (client config format, platform requirements)
**Research topics**: OpenVPN client config format, platform-specific config differences (Windows/Mac/Linux/iOS/Android)
**Plans**: TBD

Plans:
- [x] 03-01: Backend Client Management - Flask REST API for client CRUD, certificate revocation with CRL
- [x] 03-02: Frontend & Downloads - Client management UI, secure downloads, idempotent installer

### Phase 4: Testing & Polish
**Goal**: Production-ready system validated across all target platforms
**Depends on**: Phase 3
**Research**: Unlikely (validation using established patterns)
**Plans**: 2 plans

Plans:
- [x] 04-01: Script Validation & Documentation - Shellcheck validation, README.md, TESTING.md, production readiness
- [x] 04-02: Manual Testing & Production Validation - Execute testing procedures, verify production readiness

</details>

### 🚧 v1.1 Docker Upgrade (In Progress)

**Milestone Goal:** Transform the bash installer from host-based installation to containerized deployment, automatically installing Docker prerequisites and running OpenVPN + portal services in containers.

#### Phase 5: Docker Prerequisites & Host Setup
**Goal**: Detect and install Docker/Docker Compose if missing, configure host for containerized services
**Depends on**: Phase 4 (v1.0 complete)
**Research**: Likely (Docker installation patterns, container networking)
**Research topics**: Docker/Docker Compose installation on Ubuntu/Debian, container port mapping for UDP and TCP, firewall configuration for containerized services
**Plans**: TBD

Plans:
- [x] 05-01: Docker Installation & Prerequisites - Docker Engine, Compose v2, TUN module
- [x] 05-02: Host Network Configuration - UFW rules, IP forwarding, simplified installer

#### Phase 6: Containerized OpenVPN & Portal
**Goal**: Create Dockerfile and docker-compose.yml to run OpenVPN server and Flask portal in containers
**Depends on**: Phase 5
**Research**: Likely (OpenVPN containerization, volume management)
**Research topics**: OpenVPN Docker best practices, persistent volume management for certificates/configs, multi-container networking
**Plans**: TBD

Plans:
- [x] 06-01: OpenVPN Container Structure - Dockerfile, docker-entrypoint.sh with PKI initialization
- [x] 06-02: Flask Portal Container Structure - Python container, portal app migration, build verification
- [x] 06-03: Docker Compose & Installer Migration - docker-compose.yml orchestration, simplified install.sh (1860→383 lines)

#### Phase 7: Docker Testing & Documentation
**Goal**: Update testing procedures and documentation for containerized deployment
**Depends on**: Phase 6
**Research**: Unlikely (documentation update, existing testing patterns adapted)
**Plans**: 1

Plans:
- [x] 07-01: Update User Documentation - README.md port 443, Docker requirements, container troubleshooting

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Installer & OpenVPN Setup | v1.0 | 4/4 | Complete | 2026-01-08 |
| 2. Web Portal Foundation | v1.0 | 2/2 | Complete | 2026-01-08 |
| 3. Client Management | v1.0 | 2/2 | Complete | 2026-01-08 |
| 4. Testing & Polish | v1.0 | 2/2 | Complete | 2026-01-08 |
| 5. Docker Prerequisites & Host Setup | v1.1 | 2/2 | Complete | 2026-01-08 |
| 6. Containerized OpenVPN & Portal | v1.1 | 3/3 | Complete | 2026-01-08 |
| 7. Docker Testing & Documentation | v1.1 | 1/1 | Complete | 2026-01-08 |
