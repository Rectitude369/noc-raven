# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NoC Raven is a containerized telemetry collection and forwarding appliance for venue environments. It combines multiple telemetry collectors (syslog, NetFlow, IPFIX, sFlow, SNMP, Windows Events) with a web-based control panel.

## Critical: Read DEVELOPMENT.md First

**DEVELOPMENT.md contains 13 immutable project rules that MUST be followed.** Key rules include:
- Never change foundational features without explicit user acknowledgement
- No shortcuts, mock data, or placeholder implementations in production code
- 100% goal completion required - no incomplete tasks
- Keep CURRENT_TASKS.md updated with progress
- Zero TypeScript errors, zero ESLint errors required

## Architecture

```
┌─────────────────────────────────────────────────────┐
│         React Web UI (Port 8080)                    │
├─────────────────────────────────────────────────────┤
│    Nginx Reverse Proxy (/api/* → :5004)             │
├─────────────────────────────────────────────────────┤
│  Go Config Service (Port 5004, Internal)            │
├─────────────────────────────────────────────────────┤
│  Fluent-Bit │ GoFlow2 │ Telegraf │ Vector           │
│  (syslog)   │ (flows) │ (SNMP)   │ (Win Events)    │
├─────────────────────────────────────────────────────┤
│  Supervisord Process Manager                        │
├─────────────────────────────────────────────────────┤
│  Alpine Linux Container                             │
└─────────────────────────────────────────────────────┘
```

### Key Components
- **Go Config Service** (`config-service/main.go`): REST API on port 5004 for configuration persistence and service management
- **React Web UI** (`web/src/`): Control panel using React Router, styled-components, Chart.js
- **Terminal Mode**: C-based interactive menu (`scripts/terminal-menu/`)
- **Configuration**: JSON-based at `/opt/noc-raven/web/api/config.json`

## Development Commands

### Docker Build & Run
```bash
# Build container
DOCKER_BUILDKIT=1 docker build -t noc-raven:latest .

# Run in web mode (development)
./scripts/run-web.sh
# Access: http://localhost:9080

# Run in terminal mode
./scripts/run-terminal.sh
docker attach noc-raven-term  # Detach: Ctrl-p Ctrl-q

# Production build
./build-production.sh
```

### Web Frontend (from web/ directory)
```bash
npm run build              # Production build
npm run dev                # Development server with hot reload
npm run test               # Jest unit tests
npm run test -- --testPathPattern="ComponentName"  # Run single test file
npm run test:e2e           # Playwright E2E tests
npm run test:e2e:ui        # Playwright with interactive UI
```

### Go Config Service (from config-service/ directory)
```bash
go build -o config-service .
go test ./...
go test -v -run TestFunctionName  # Run single test
```

### Health & API Testing
```bash
curl http://localhost:9080/health
curl http://localhost:9080/api/config
curl http://localhost:9080/api/system/status
```

## API Reference

### Configuration Endpoints
- `GET /api/config` - Get current configuration
- `POST /api/config` - Update configuration (auto-restarts affected services)
- `POST /api/services/{name}/restart` - Restart specific service
- `GET /api/system/status` - System health and service status

### Service Name Aliases
API accepts aliases: `syslog`/`fluentbit` → `fluent-bit`, `windows`/`win-events` → `vector`

### Dynamic Port Configuration
Config changes automatically restart affected services:
- Syslog port → fluent-bit restart
- NetFlow/IPFIX/sFlow port → goflow2 restart
- SNMP trap port → telegraf restart
- Windows Events port → vector restart

## Port Reference

| Port | Service | Purpose |
|------|---------|---------|
| 8080/tcp | Web UI | Dashboard (expose as 9080 on host) |
| 5004/tcp | Config API | Internal, proxied via Nginx |
| 8084/tcp | Vector HTTP | Windows Events collection |
| 1514/udp | Fluent-bit | Syslog |
| 2055/udp | GoFlow2 | NetFlow v5 |
| 4739/udp | GoFlow2 | IPFIX |
| 6343/udp | GoFlow2 | sFlow |
| 162/udp | Telegraf | SNMP traps |

## Key Files

| File | Purpose |
|------|---------|
| `config-service/main.go` | Go REST API backend |
| `web/src/App.js` | React app entry with routing |
| `web/src/components/` | UI page components |
| `scripts/entrypoint.sh` | Container initialization |
| `scripts/production-service-manager.sh` | Service lifecycle management |
| `Dockerfile` | Multi-stage Alpine build |
| `DEVELOPMENT.md` | 13 immutable project rules |
| `CURRENT_TASKS.md` | Live task tracking dashboard |

## Testing Strategy

- **Unit Tests**: `npm test` (web), `go test ./...` (config-service)
- **E2E Tests**: Playwright tests in `web/tests/e2e.test.js`
- Tests cover configuration persistence, service restarts, UI workflows

## Container Notes

- Runs as non-root user `nocraven` (UID 1000)
- Terminal mode requires `CAP_NET_ADMIN` for network configuration
- Volumes: `/data` (buffers), `/config` (user config), `/var/log/noc-raven` (logs)
- Config service logs to `/var/log/noc-raven/config-service.log`
