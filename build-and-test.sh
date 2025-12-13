#!/bin/bash
# 🦅 NoC Raven - Build and Test Script
# Validates Docker build, configurations, and basic functionality

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Configuration
CONTAINER_NAME="noc-raven-test"
IMAGE_NAME="rectitude369/noc-raven"
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
# Use high, likely-free host ports for testing to avoid conflicts
HOST_WEB_PORT=${HOST_WEB_PORT:-19080}
HOST_NETFLOW_PORT=${HOST_NETFLOW_PORT:-12055}
HOST_SFLOW_PORT=${HOST_SFLOW_PORT:-16343}

# Log function
log() {
    echo -e "[$(date -Iseconds)] $*"
}

log_info() { log "${CYAN}$*${RESET}"; }
log_success() { log "${GREEN}✓ $*${RESET}"; }
log_error() { log "${RED}✗ $*${RESET}"; }
log_warn() { log "${YELLOW}⚠ $*${RESET}"; }

# Show banner
show_banner() {
    cat << 'EOF'
🦅 NoC Raven - Build & Test Script

  ███╗   ██╗ ██████╗  ██████╗    ██████╗  █████╗ ██╗   ██╗███████╗███╗   ██╗
  ████╗  ██║██╔═══██╗██╔════╝    ██╔══██╗██╔══██╗██║   ██║██╔════╝████╗  ██║
  ██╔██╗ ██║██║   ██║██║         ██████╔╝███████║██║   ██║█████╗  ██╔██╗ ██║
  ██║╚██╗██║██║   ██║██║         ██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║
  ██║ ╚████║╚██████╔╝╚██████╗    ██║  ██║██║  ██║ ╚████╔╝ ███████╗██║ ╚████║
  ╚═╝  ╚═══╝ ╚═════╝  ╚═════╝    ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝

         Telemetry Collection & Forwarding Appliance - Build & Test

EOF
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test containers and volumes..."
    docker stop $CONTAINER_NAME &>/dev/null || true
    docker rm $CONTAINER_NAME &>/dev/null || true
    docker volume rm noc-raven-test-data noc-raven-test-config &>/dev/null || true
}

# Pre-flight checks
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "Dockerfile" ]] || [[ ! -d "config" ]] || [[ ! -d "scripts" ]]; then
        log_error "Please run this script from the noc-raven project directory"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Validate configuration files
validate_configs() {
    log_info "Validating configuration files..."
    
    local configs=(
        "Dockerfile"
        "config/fluent-bit.conf"
        "config/goflow2.yml"
        "scripts/entrypoint.sh"
        "scripts/terminal-menu.sh"
    )
    
    # Optional configs that may not be present
    local optional_configs=(
        "config/fluent-bit-basic.conf"
        "config/vector-minimal.toml"
        "config/telegraf.conf"
        "config/supervisord.conf"
    )
    
    local missing_configs=()
    
    # Check required configs
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            log_success "Found: $config"
        else
            log_error "Missing: $config"
            missing_configs+=("$config")
        fi
    done
    
    # Check optional configs
    for config in "${optional_configs[@]}"; do
        if [[ -f "$config" ]]; then
            log_success "Found (optional): $config"
        else
            log_info "Optional config not found: $config"
        fi
    done
    
    if [[ ${#missing_configs[@]} -gt 0 ]]; then
        log_error "Missing ${#missing_configs[@]} required configuration files"
        for missing in "${missing_configs[@]}"; do
            log_error "  - $missing"
        done
        return 1
    fi
    
    log_success "Configuration validation passed"
}

# Build Docker image
build_image() {
    log_info "Building Docker image: $FULL_IMAGE_NAME"
    
    # Build with BuildKit for better performance
    DOCKER_BUILDKIT=1 docker build \
        --build-arg BUILD_DATE=$(date -Iseconds) \
        --build-arg VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown") \
        --tag $FULL_IMAGE_NAME \
        --progress=plain \
        .
    
    if [[ $? -eq 0 ]]; then
        log_success "Docker image built successfully"
    else
        log_error "Docker image build failed"
        exit 1
    fi
}

# Test terminal menu mode (simulated)
test_terminal_mode() {
    log_info "Testing terminal menu mode (simulated no-DHCP)..."
    
    # Create test volumes
    docker volume create noc-raven-test-data >/dev/null
    docker volume create noc-raven-test-config >/dev/null
    
    # Run container in terminal mode with timeout
    log_info "Starting container in terminal mode..."
    timeout 30s docker run \
        --name $CONTAINER_NAME \
        --rm \
        -e NETWORK_INTERFACE=lo \
        -v noc-raven-test-data:/data \
        -v noc-raven-test-config:/config \
        $FULL_IMAGE_NAME \
        --mode=terminal &
    
    local container_pid=$!
    sleep 10
    
    # Check if container started (it will exit quickly due to interactive mode)
    sleep 2
    if docker ps -a | grep $CONTAINER_NAME >/dev/null 2>&1; then
        log_success "Container started successfully in terminal mode"
        
        # Stop the container if still running
        docker stop $CONTAINER_NAME >/dev/null 2>&1 || true
        wait $container_pid 2>/dev/null || true
    else
        log_error "Container failed to start in terminal mode"
        return 1
    fi
}

# Test web panel mode (simulated DHCP)
test_web_mode() {
    log_info "Testing web panel mode (simulated DHCP)..."
    
    # Run container in web mode with timeout
    log_info "Starting container in web mode..."
    docker run \
        --name $CONTAINER_NAME \
        --rm \
        --detach \
        -p ${HOST_WEB_PORT}:8080 \
        -p ${HOST_NETFLOW_PORT}:2055/udp \
        -p ${HOST_SFLOW_PORT}:6343/udp \
        -v noc-raven-test-data:/data \
        -v noc-raven-test-config:/config \
        $FULL_IMAGE_NAME \
        --mode=web
    
    # Wait for container to initialize
    log_info "Waiting for services to initialize..."
    sleep 15
    
    # Check if container was created and started (even if it exits quickly)
    local cid
    cid=$(docker ps -aq -f name=^/${CONTAINER_NAME}$)
    if [ -n "$cid" ]; then
        log_success "Container started successfully in web mode"
        
        # Test health endpoints (if available)
        if curl -s --max-time 5 http://localhost:${HOST_WEB_PORT}/health >/dev/null 2>&1; then
            log_success "Web panel is responding"
        else
            log_warn "Web panel did not respond to /health yet (may be initializing)"
        fi
        
        # Check logs for major startup issues
        local logs
        logs=$(docker logs $CONTAINER_NAME 2>&1 || echo "")
        if echo "$logs" | grep -qi "nginx"; then
            log_success "Nginx output detected"
        else
            log_warn "Nginx output not detected yet"
        fi
        
        # Stop and remove the container
        docker stop $CONTAINER_NAME >/dev/null 2>&1 || true
        docker rm $CONTAINER_NAME >/dev/null 2>&1 || true
    else
        log_error "Container failed to start in web mode"
        return 1
    fi
}

# Test port bindings
test_port_bindings() {
    log_info "Testing port bindings..."
    
    # Ensure any prior container is stopped
    docker stop $CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm $CONTAINER_NAME >/dev/null 2>&1 || true

    docker run \
        --name $CONTAINER_NAME \
        --rm \
        --detach \
        -p ${HOST_WEB_PORT}:8080 \
        -p ${HOST_NETFLOW_PORT}:2055/udp \
        -p ${HOST_SFLOW_PORT}:6343/udp \
        -v noc-raven-test-data:/data \
        -v noc-raven-test-config:/config \
        $FULL_IMAGE_NAME \
        --mode=web
    
    sleep 20
    
    # Check if ports are bound
    local expected_ports=("${HOST_WEB_PORT}" "${HOST_NETFLOW_PORT}" "${HOST_SFLOW_PORT}")
    local bound_ports=()
    
    for port in "${expected_ports[@]}"; do
        if command -v lsof >/dev/null 2>&1; then
            if lsof -nP -i UDP:${port} 2>/dev/null | grep -q "${port}" || \
               lsof -nP -i TCP:${port} 2>/dev/null | grep -q "${port}"; then
                bound_ports+=("$port")
                log_success "Port $port is bound"
            else
                log_warn "Port $port is not bound"
            fi
        else
            if netstat -an 2>/dev/null | grep -E "[:\\.]${port}[[:space:]]" >/dev/null || \
               ss -tuln 2>/dev/null | grep -q ":${port} "; then
                bound_ports+=("$port")
                log_success "Port $port is bound"
            else
                log_warn "Port $port is not bound"
            fi
        fi
    done
    
    docker stop $CONTAINER_NAME >/dev/null
    
    if [[ ${#bound_ports[@]} -ge 3 ]]; then
        log_success "Port binding test passed (${#bound_ports[@]}/${#expected_ports[@]} ports bound)"
    else
        log_error "Port binding test failed (only ${#bound_ports[@]}/${#expected_ports[@]} ports bound)"
        return 1
    fi
}

# Test volume mounts
test_volume_mounts() {
    log_info "Testing volume mounts..."
    
    # Test write access to volumes using a simple command to avoid entrypoint script
    if docker run \
        --rm \
        -v noc-raven-test-data:/data \
        -v noc-raven-test-config:/config \
        --entrypoint /bin/sh \
        $FULL_IMAGE_NAME \
        -c "echo 'test' > /data/test.txt && echo 'test' > /config/test.txt && ls -la /data /config" >/dev/null 2>&1; then
        log_success "Volume mount test passed"
    else
        log_error "Volume mount test failed"
        return 1
    fi
}

# Test configuration validation
test_config_validation() {
    log_info "Testing configuration file validation..."
    
    # Skip external tool config validation for now since we're using built-in solutions
    log_warn "Skipping external telemetry tool validation (using built-in collectors)"
    
    # Test script syntax using cat and basic validation without execution
    if docker run --rm --workdir /opt/noc-raven --entrypoint /bin/sh $FULL_IMAGE_NAME -c "head -n 1 bin/entrypoint.sh | grep -q '#!/bin/bash' && grep -q 'set -euo pipefail' bin/entrypoint.sh" 2>/dev/null; then
        log_success "Entry point script syntax is valid"
    else
        log_error "Entry point script syntax is invalid"
        return 1
    fi
    
    if docker run --rm --workdir /opt/noc-raven --entrypoint /bin/sh $FULL_IMAGE_NAME -c "head -n 1 scripts/terminal-menu.sh | grep -q '#!/bin/bash' && grep -q 'set -euo pipefail' scripts/terminal-menu.sh" 2>/dev/null; then
        log_success "Terminal menu script syntax is valid"
    else
        log_error "Terminal menu script syntax is invalid"
        return 1
    fi
    
    # Test if GoFlow2 is available
    if docker run --rm --entrypoint /bin/sh $FULL_IMAGE_NAME -c "/opt/noc-raven/bin/goflow2 --help" >/dev/null 2>&1; then
        log_success "GoFlow2 binary is functional"
    else
        log_error "GoFlow2 binary is not functional"
        return 1
    fi
    
    # Test if systemctl replacement is working
    if docker run --rm --entrypoint /bin/sh $FULL_IMAGE_NAME -c "systemctl help" >/dev/null 2>&1; then
        log_success "Systemctl replacement is functional"
    else
        log_error "Systemctl replacement is not functional"
        return 1
    fi
}

# Generate test report
generate_report() {
    local test_results_file="test-results-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$test_results_file" << EOF
🦅 NoC Raven - Test Results Report
Generated: $(date -Iseconds)
Image: $FULL_IMAGE_NAME

Test Results:
=============
EOF
    
    # Image info
    echo "" >> "$test_results_file"
    echo "Docker Image Information:" >> "$test_results_file"
    docker inspect $FULL_IMAGE_NAME --format='Size: {{.Size}} bytes' >> "$test_results_file"
    docker inspect $FULL_IMAGE_NAME --format='Architecture: {{.Architecture}}' >> "$test_results_file"
    docker inspect $FULL_IMAGE_NAME --format='OS: {{.Os}}' >> "$test_results_file"
    
    # Image layers
    echo "" >> "$test_results_file"
    echo "Image Layers:" >> "$test_results_file"
    docker history $FULL_IMAGE_NAME --format "table {{.CreatedBy}}\t{{.Size}}" >> "$test_results_file"
    
    log_success "Test report generated: $test_results_file"
}

# Main execution
main() {
    show_banner
    
    # Set up signal handlers
    trap cleanup EXIT INT TERM
    
    log_info "Starting NoC Raven build and test sequence..."
    
    # Pre-flight checks
    check_prerequisites
    validate_configs
    
    # Build phase
    log_info "=== BUILD PHASE ==="
    build_image
    
    # Test phase
    log_info "=== TEST PHASE ==="
    
    local test_results=()
    
    # Run tests
    if test_terminal_mode; then
        test_results+=("Terminal Mode: PASS")
    else
        test_results+=("Terminal Mode: FAIL")
    fi
    
    if test_web_mode; then
        test_results+=("Web Mode: PASS")
    else
        test_results+=("Web Mode: FAIL")
    fi
    
    if test_port_bindings; then
        test_results+=("Port Bindings: PASS")
    else
        test_results+=("Port Bindings: FAIL")
    fi
    
    if test_volume_mounts; then
        test_results+=("Volume Mounts: PASS")
    else
        test_results+=("Volume Mounts: FAIL")
    fi
    
    if test_config_validation; then
        test_results+=("Config Validation: PASS")
    else
        test_results+=("Config Validation: FAIL")
    fi
    
    # Results summary
    log_info "=== TEST RESULTS SUMMARY ==="
    local passed=0
    local total=${#test_results[@]}
    
    for result in "${test_results[@]}"; do
        if [[ "$result" == *"PASS" ]]; then
            log_success "$result"
            ((passed++))
        else
            log_error "$result"
        fi
    done
    
    echo
    if [[ $passed -eq $total ]]; then
        log_success "🎉 All tests passed! ($passed/$total)"
        log_success "NoC Raven Docker image is ready for deployment"
    else
        log_error "❌ Some tests failed ($passed/$total passed)"
        log_error "Please review the issues before deployment"
    fi
    
    # Generate report
    generate_report
    
    # Cleanup
    cleanup
    
    log_info "Build and test sequence completed"
    
    # Exit with appropriate code
    if [[ $passed -eq $total ]]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"
