#!/bin/bash
# 🦅 NoC Raven - GoFlow2 Startup Script
# Starts GoFlow2 with proper command line arguments for production stability

set -euo pipefail

# Create necessary directories
mkdir -p /data/flows

# Start GoFlow2 with stable configuration
exec /opt/noc-raven/bin/goflow2 \
    -listen "sflow://:6343,netflow://:2055,ipfix://:4739" \
    -transport file \
    -transport.file "/data/flows/goflow2.log" \
    -transport.file.sep "\n" \
    -format json \
    -produce sample \
    -loglevel info \
    -logfmt normal \
    -addr ":8081" \
    -templates.path "/data/flows/templates"
