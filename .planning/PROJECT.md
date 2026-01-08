# EasyOpenVPN

## What This Is

A zero-touch OpenVPN server installer for Linux VPS users. Install with a single curl | bash command, manage clients through a secure web portal, and download platform-agnostic VPN configs. Built for individuals who want commercial VPN provider simplicity on their own infrastructure.

## Core Value

Installation and client access must be as simple as commercial VPN providers. If it requires more than "curl | bash" to set up or more than "login and download" to get a working VPN config, it's too complex.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] One-line installation via curl | bash with zero manual intervention
- [ ] Automated OpenVPN server setup with self-signed certificate generation
- [ ] Web portal with simple password authentication
- [ ] Session-based portal access (1-hour session validity)
- [ ] Client config generation through web interface
- [ ] One-time download links for client files (regenerate if session valid)
- [ ] Platform-agnostic client configs (Windows, Mac, Linux, iOS, Android)
- [ ] Client management through portal (create new clients, delete existing)
- [ ] HTTPS portal with self-signed certificate (no domain required)
- [ ] Ubuntu/Debian distribution support
- [ ] Distro-agnostic architecture (extensible to other distros later)

### Out of Scope

- Advanced VPN features (split tunneling, custom routing rules, IPv6, multi-protocol support) — v1 focuses on basic secure tunnel
- Enterprise features (LDAP/SSO, audit logging, compliance reporting, user quotas) — targeting individuals, not organizations
- Existing server migration tools — greenfield installations only
- Custom mobile apps — users leverage standard OpenVPN Connect clients
- Formal certificate revocation system — use simple delete/recreate client model instead
- Let's Encrypt integration — self-signed certs sufficient for v1, no domain requirement
- CentOS/RHEL/Fedora/Arch support in v1 — Ubuntu/Debian first, expand later

## Context

**Target users:** Individual VPS users who want to run their own VPN server without complexity. These users typically choose Ubuntu-based distributions for ease of use.

**Success benchmark:** Commercial VPN providers (NordVPN, ExpressVPN, etc.) set the bar. They only require installing a client app and clicking connect. We aim to match that simplicity on the server side and client config distribution.

**Use cases:**
- Privacy-conscious users wanting control over their VPN infrastructure
- Remote access to home/office network
- Bypassing geo-restrictions using personal infrastructure
- Learning and experimentation with VPN technology

**Success criteria:**
- Daily personal use on production VPS
- Others can install without documentation or support requests
- Generated client configs work reliably across all major platforms

## Constraints

None specified — implementation flexibility prioritized for best user experience.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Self-signed certs over Let's Encrypt | Eliminates domain requirement, keeps installation truly zero-touch | — Pending |
| Delete/recreate vs certificate revocation | Simpler mental model, reduces complexity for v1 | — Pending |
| Ubuntu/Debian first | Users wanting this simplicity typically use Ubuntu-based distros | — Pending |
| Web portal for all client management | Consistent UX, no CLI commands to remember | — Pending |
| Session-based one-time download links | Balance between security and usability | — Pending |

---
*Last updated: 2026-01-08 after initialization*
