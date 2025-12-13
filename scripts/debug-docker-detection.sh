#!/bin/bash
# Debug Docker detection logic

echo "=== Docker Detection Debug ==="
echo "Date: $(date)"
echo ""

echo "1. Checking /.dockerenv file:"
if [[ -f /.dockerenv ]]; then
    echo "   ✅ /.dockerenv exists"
    ls -la /.dockerenv
else
    echo "   ❌ /.dockerenv does not exist"
fi

echo ""
echo "2. Checking /proc/1/cgroup:"
if [[ -f /proc/1/cgroup ]]; then
    echo "   ✅ /proc/1/cgroup exists"
    echo "   Content:"
    cat /proc/1/cgroup | head -10
    echo ""
    echo "   Checking for docker/lxc patterns:"
    if grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        echo "   ✅ Found docker/lxc pattern"
        grep 'docker\|lxc' /proc/1/cgroup
    else
        echo "   ❌ No docker/lxc pattern found"
    fi
else
    echo "   ❌ /proc/1/cgroup does not exist"
fi

echo ""
echo "3. Combined Docker detection test:"
if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
    echo "   ✅ Docker container detected!"
else
    echo "   ❌ Docker container NOT detected"
fi

echo ""
echo "4. Environment variables:"
echo "   CONTAINER: ${CONTAINER:-not set}"
echo "   DOCKER: ${DOCKER:-not set}"
echo "   PWD: $PWD"
echo "   USER: $(whoami)"

echo ""
echo "5. Process information:"
echo "   PID 1 process:"
ps -p 1 -o pid,ppid,cmd

echo ""
echo "6. Mount information:"
echo "   Root filesystem:"
df -h / | head -2

echo ""
echo "=== End Debug ==="
