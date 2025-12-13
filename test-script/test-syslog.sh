#!/bin/bash

# Simple syslog test
echo "Testing syslog to localhost..."

# Send a test syslog message
MESSAGE="Test syslog message from observability tester at $(date)"
echo "<14>$(date '+%b %d %H:%M:%S') $(hostname) test-script[$$]: $MESSAGE" | nc -u -w1 127.0.0.1 514

if [ $? -eq 0 ]; then
    echo "
    echo "
