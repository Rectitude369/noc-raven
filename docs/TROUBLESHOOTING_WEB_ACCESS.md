# NoC Raven Web Console Access Troubleshooting

## 🔧 **Quick Fix Checklist**

### **1. Use HTTP, Not HTTPS** ⭐
**Most Common Issue**: The container serves HTTP only by default.
```bash
# ❌ WRONG: https://localhost:9080  
# ✅ CORRECT: http://localhost:9080
```

### **2. Verify Container Status**
```bash
# Check if container is running
docker ps | grep noc-raven

# Expected output should show:
# - Container status: Up
# - Port mapping: 0.0.0.0:9080->8080/tcp
```

### **3. Check Container Logs**
```bash
# View startup logs
docker logs noc-raven-web --tail 50

# Look for:
# ✅ "nginx started (PID: ...)"
# ✅ "NoC Raven is fully operational! 🦅"
# ❌ Any error messages about nginx or port binding
```

### **4. Test Internal Connectivity**
```bash
# Test from inside container
docker exec noc-raven-web curl -f http://localhost:8080/health

# Expected response:
# {"status": "healthy", "timestamp": "..."}
```

### **5. Verify Port Bindings**
```bash
# Check actual port mappings
docker port noc-raven-web

# Expected output:
# 8080/tcp -> 0.0.0.0:9080
# 8084/tcp -> 0.0.0.0:8084
# 514/udp -> 0.0.0.0:514
# etc.
```

## 🐛 **Common Issues & Solutions**

### **Issue: "Connection Refused" or "Site Can't Be Reached"**

**Cause**: Services not started or crashed during startup

**Solution**:
```bash
# 1. Check container is actually running
docker ps | grep noc-raven

# 2. If not running, check why it exited
docker logs noc-raven-web

# 3. Restart container
docker restart noc-raven-web

# 4. Monitor startup process
docker logs noc-raven-web -f
```

### **Issue: "This Site Can't Provide a Secure Connection"**

**Cause**: Using HTTPS URL when container serves HTTP

**Solution**:
```bash
# Use HTTP instead of HTTPS
http://localhost:9080
```

### **Issue: Container Running But No Response**

**Cause**: nginx service failed to start

**Solution**:
```bash
# Check if nginx is running
docker exec noc-raven-web ps aux | grep nginx

# If not running, start it manually
docker exec noc-raven-web nginx

# Check nginx error logs
docker exec noc-raven-web cat /opt/noc-raven/logs/nginx.error.log
```

### **Issue: Port Already in Use**

**Cause**: Another service using port 9080

**Solution**:
```bash
# Check what's using port 9080
lsof -i :9080

# Use different port
docker run ... -p 9081:8080 ... noc-raven:latest
# Then access: http://localhost:9081
```

## 🔍 **OrbStack-Specific Troubleshooting**

### **1. Check OrbStack Container Access**
```bash
# OrbStack may provide direct container access
# Check OrbStack documentation for container URLs
```

### **2. Test with Different Port**
```bash
# Stop existing container
docker stop noc-raven-web && docker rm noc-raven-web

# Run on different port
./scripts/run-web.sh
# But manually edit to use -p 8080:8080 instead of -p 9080:8080

# Then access: http://localhost:8080
```

### **3. Network Mode Testing**
```bash
# Try with host networking (Linux/macOS only)
docker run -d --name noc-raven-host \
  --network host \
  noc-raven:latest --mode=web

# Then access: http://localhost:8080
```

## 📋 **Step-by-Step Diagnosis**

Run these commands in order and share the output:

```bash
# 1. Container status
echo "=== Container Status ==="
docker ps | grep noc-raven

# 2. Port bindings
echo "=== Port Bindings ==="
docker port noc-raven-web

# 3. Recent logs
echo "=== Recent Logs ==="
docker logs noc-raven-web --tail 20

# 4. Internal health check
echo "=== Internal Health ==="
docker exec noc-raven-web curl -f http://localhost:8080/health 2>/dev/null || echo "Health check failed"

# 5. Process check
echo "=== Running Processes ==="
docker exec noc-raven-web ps aux | grep -E "(nginx|node|python)"

# 6. Port listening check
echo "=== Listening Ports ==="
docker exec noc-raven-web netstat -tlnp | grep -E "(8080|5004)"
```

## 🎯 **Quick Resolution**

**Most likely fix for immediate access**:
1. Try `http://localhost:9080` (not https)
2. If that fails, run: `docker logs noc-raven-web --tail 10`
3. Share the log output for specific diagnosis

**Emergency alternative**:
```bash
# Quick test with direct port 8080
docker run -d --name noc-raven-direct \
  -p 8080:8080 \
  noc-raven:latest --mode=web

# Access: http://localhost:8080
```