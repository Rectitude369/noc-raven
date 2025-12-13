# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NoC Raven is a high-performance, turn-key telemetry collection and forwarding appliance designed for venue environments. It's a containerized solution that combines multiple telemetry collection services with a web-based control panel.

## Core Architecture

### Multi-Service Architecture
- **Go Config Service** (`config-service/main.go`): RESTful API server (port 5004) handling configuration persistence and service management
- **React Web UI** (`web/src/`): Control panel accessible on port 8080, built with React Router, styled-components, and Chart.js
- **Fluent Bit**: Syslog collection service with dynamic port configuration
- **GoFlow2**: NetFlow v5, IPFIX, and sFlow collectors
- **Telegraf**: SNMP trap collection and system metrics
- **Vector**: Log/metric pipeline with HTTP endpoint (8084) for Windows Events
- **Nginx**: Reverse proxy serving the web UI and proxying `/api/*` to config service

### Key Components
- **Terminal Mode**: Interactive configuration via C-based terminal menu (`scripts/terminal-menu/`)
- **Dynamic Configuration**: JSON-based config at `/opt/noc-raven/web/api/config.json`
- **Service Management**: Production service manager with restart capabilities
- **Docker Multi-stage Build**: Optimized Alpine-based container with all services

## Essential Development Commands

### Docker Operations
```bash
# Build container image
DOCKER_BUILDKIT=1 docker build -t noc-raven:latest .

# Terminal mode (first-time setup)
./scripts/run-terminal.sh
docker attach noc-raven-term  # Detach: Ctrl-p Ctrl-q

# Web mode 
./scripts/run-web.sh
# Access UI: http://localhost:9080

# Production build
./build-production.sh
```

### Web Development
```bash
cd web/
npm run build          # Production build
npm run dev            # Development server with hot reload
npm run test           # Jest unit tests
npm run test:e2e       # Playwright end-to-end tests
npm run test:e2e:ui    # Playwright with UI mode
```

### Go Config Service
```bash
cd config-service/
go build -o config-service .
go test ./...          # Run tests
```

### Testing
```bash
# E2E testing from web directory
cd web && npm run test:e2e

# Health checks
curl http://localhost:9080/health
curl http://localhost:9080/api/config
```

## Configuration Management

### Core API Endpoints
- `GET /api/config` - Retrieve current configuration
- `POST /api/config` - Update configuration (triggers service restarts)
- `POST /api/services/{name}/restart` - Restart individual services
- `GET /api/system/status` - System health and service status

### Dynamic Port Configuration
The config service automatically restarts affected services when configuration changes:
- Syslog port changes → restart fluent-bit
- NetFlow/IPFIX/sFlow port changes → restart goflow2  
- SNMP trap port changes → restart telegraf
- Windows Events port changes → restart vector

### Service Name Aliases
The API accepts friendly aliases: `syslog`/`fluentbit` → `fluent-bit`, `windows`/`win-events` → `vector`

## File Organization

### Critical Development Rules
Read and follow **ALL 12 IMMUTABLE PROJECT RULES** in `DEVELOPMENT.md` - these supersede any other guidance and must be strictly adhered to.

### Key Directories
- `web/` - React frontend application 
- `config-service/` - Go REST API backend
- `scripts/` - Shell scripts for container management and service control
- `config/` - Configuration templates for all services
- `docs/` - Comprehensive project documentation
- `tests/e2e/` - End-to-end test scripts
- `backups/` - Legacy scripts and configuration backups

### Web UI Architecture
- `web/src/App.js` - Main application with React Router and navigation
- `web/src/components/` - Individual page components (Dashboard, Settings, NetFlow, etc.)
- Built components fetch data from `/api/*` endpoints
- Uses React Router for client-side routing
- Styled with CSS modules and styled-components

## Port Mapping & Networking

### Container Ports
- **8080**: Web UI (expose on host as 9080)
- **8084**: Vector HTTP endpoint for Windows Events (expose on host)  
- **5004**: Config service API (internal only, proxied by Nginx)
- **2055/udp**: NetFlow v5 collector
- **4739/udp**: IPFIX collector
- **6343/udp**: sFlow collector
- **162/udp**: SNMP trap receiver

### Production Notes
- Container runs as non-root user `nocraven` (UID 1000)
- Terminal mode requires `CAP_NET_ADMIN` and root for network configuration
- Config service has optional API key authentication (disabled by default)

## Testing Strategy

### Unit Tests
- Go: `go test ./...` in config-service/
- JavaScript: `npm test` in web/

### E2E Tests  
- Playwright tests in `web/tests/e2e.test.js`
- Smoke tests verify basic functionality
- Tests cover configuration persistence and service restarts

### Performance Testing
- Container optimized for high-throughput telemetry collection
- Kernel tuning for network buffers and file descriptors
- Vector and GoFlow2 handle thousands of flows/logs per second

## Deployment Modes

### Development
Use `./scripts/run-web.sh` for development with bind mounts to local directories.

### Production  
Use production image `rectitude369/noc-raven:latest` with Docker volumes for persistence:
- `/data` - Telemetry buffers and logs  
- `/config` - User configuration
- `/var/log/noc-raven` - Application logs

## Important Conventions

### Service Management
- Use the production service manager script for service lifecycle
- Config changes automatically trigger relevant service restarts
- Services can be restarted individually via API or supervisorctl

### Configuration Persistence
- All config changes are automatically backed up with timestamps
- Config service handles atomic writes and service coordination
- JSON configuration is validated before persistence

### Error Handling
- Config service logs all operations to `/var/log/noc-raven/config-service.log`
- Web UI provides user feedback via toast notifications
- Services restart gracefully with supervisor management

## Security Considerations

- API authentication available but disabled by default (beta release)
- CORS configured for development (allow all origins)
- Container designed for isolated network environments
- No secrets or credentials stored in code or configuration files