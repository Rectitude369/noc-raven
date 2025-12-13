# 🔧 NoC Raven Pipeline Architecture Review & Fixes

**Date:** January 13, 2025  
**Review Type:** Pre-Deployment Architecture Analysis  
**Status:** Critical Issues Identified - Fixes Required Before Build

---

## 🚨 Critical Issues Found

### **ISSUE #1: Fluent Bit Bypasses Buffer Service** 🔴

**Problem:**
- Fluent Bit syslog output (config line 136-154) sends directly to `obs.rectitude.net:1514` via UDP
- No integration with local buffer service
- Data is lost immediately if VPN/connectivity fails

**Current Flow:**
```
Devices → Fluent Bit:1514 → [DIRECT UDP] → obs.rectitude.net:1514
                              ❌ NO BUFFERING
```

**Required Flow:**
```
Devices → Fluent Bit:1514 → Buffer Service API → [Queue] → obs.rectitude.net:1514
                                                   ↓
                                              Local Storage
                                              (2-week buffer)
```

**Fix Required:**
- Change Fluent Bit output to HTTP POST to buffer service
- Buffer service exposes `/api/v1/ingest/syslog` endpoint
- Buffer service handles queueing and forwarding

---

### **ISSUE #2: Vector Buffer Integration Broken** 🔴

**Problem:**
- Vector config line 300 sends to `http://127.0.0.1:5005/api/buffer/ingest`
- Buffer service Go code doesn't expose port 5005 or `/api/buffer/ingest` endpoint
- Windows Events and processed syslog won't be buffered

**Current State:**
- Buffer service has no HTTP server configured
- No API endpoints defined
- Vector requests will fail with connection refused

**Fix Required:**
1. Add HTTP server to buffer service (port 5005)
2. Implement `/api/buffer/ingest` endpoint
3. Add `/api/v1/ingest/syslog` endpoint for Fluent Bit
4. Add `/api/v1/ingest/netflow` endpoint for GoFlow2
5. Add `/api/v1/ingest/snmp` endpoint for Telegraf

---

### **ISSUE #3: Telegraf Not Buffered** 🟡

**Problem:**
- Telegraf outputs bypass buffer service entirely
- Line 196-207: InfluxDB output (won't work, no local InfluxDB)
- Line 209-215: Prometheus client (metrics endpoint only)
- Line 217-228: HTTP to Vector (good, but Vector also broken)
- Line 239-245: Syslog output (goes to Fluent Bit, adds unnecessary hop)

**Required Changes:**
- Add HTTP output to buffer service `/api/v1/ingest/metrics` 
- Remove InfluxDB output (not available locally)
- Keep Prometheus metrics endpoint for monitoring

---

### **ISSUE #4: GoFlow2 Configuration Missing** 🔴

**Problem:**
- No `goflow2.yml` configuration file found in `/config` directory
- Dockerfile expects to copy it (line 199: `COPY config/ ${NOC_RAVEN_HOME}/config/`)
- Build will fail or GoFlow2 won't start

**Required:**
- Create `/config/goflow2.yml` with proper configuration
- Configure NetFlow v5/v9, IPFIX, sFlow listeners
- Output to buffer service HTTP endpoint

---

### **ISSUE #5: Buffer Service Forwarding Configuration Wrong** 🔴

**Problem:**
- Buffer service line 152: `ForwardingURL: "https://obs.rectitude.net/api/ingest"`
- This endpoint doesn't exist in the observability stack
- Should forward to individual protocol endpoints

**Actual Observability Stack Endpoints:**
```
- Syslog:         obs.rectitude.net:1514   (UDP)
- NetFlow:        obs.rectitude.net:2055   (UDP)
- IPFIX:          obs.rectitude.net:4739   (UDP)
- sFlow:          obs.rectitude.net:6343   (UDP)
- SNMP Traps:     obs.rectitude.net:162    (UDP)
- Windows Events: obs.rectitude.net:8084   (HTTP/JSON)
- InfluxDB:       obs.rectitude.net:8086   (HTTP - but needs auth token)
```

**Required:**
- Buffer service needs separate forwarding logic per telemetry type
- Must use correct protocol (UDP vs HTTP)
- Must send to correct port
- Should NOT assume single /api/ingest endpoint

---

### **ISSUE #6: No GoFlow2 Integration with Buffer Service** 🔴

**Problem:**
- GoFlow2 not mentioned in Dockerfile service orchestration
- No supervisor config for GoFlow2
- No integration with buffer service
- Won't start automatically

**Required:**
- Add GoFlow2 to supervisor configuration
- Configure GoFlow2 to output to buffer service via HTTP
- Or configure Go Flow2 to write to files that buffer service monitors

---

## 🏗️ **Corrected Architecture**

### **Proposed Data Flow:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    COLLECTION LAYER                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Fluent Bit  │  │   GoFlow2    │  │  Telegraf    │          │
│  │  (Syslog)    │  │ (NetFlow/    │  │ (SNMP Traps) │          │
│  │  UDP:1514    │  │  sFlow)      │  │  UDP:162     │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                  │                   │
│         │ HTTP POST       │ HTTP POST        │ HTTP POST         │
│         │ /ingest/syslog  │ /ingest/netflow  │ /ingest/metrics   │
│         └─────────────────┴──────────────────┘                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
           ┌───────────────────▼────────────────────────┐
           │        BUFFER SERVICE (Go)                  │
           │        HTTP API Server :5005                │
           │                                             │
           │  ┌─────────────────────────────────┐       │
           │  │   Ingestion API Endpoints       │       │
           │  │  - /api/v1/ingest/syslog        │       │
           │  │  - /api/v1/ingest/netflow       │       │
           │  │  - /api/v1/ingest/snmp          │       │
           │  │  - /api/v1/ingest/metrics       │       │
           │  │  - /api/v1/ingest/windows       │       │
           │  └─────────────────────────────────┘       │
           │                                             │
           │  ┌─────────────────────────────────┐       │
           │  │  SQLite Database + File Storage │       │
           │  │  - 2-week retention             │       │
           │  │  - GZIP compression             │       │
           │  │  - Priority queuing             │       │
           │  └─────────────────────────────────┘       │
           │                                             │
           │  ┌─────────────────────────────────┐       │
           │  │   Forwarding Engine             │       │
           │  │  - VPN health monitoring        │       │
           │  │  - Automatic retry logic        │       │
           │  │  - Per-protocol routing         │       │
           │  └─────────────────────────────────┘       │
           └─────────────────┬───────────────────────────┘
                             │
                ┌────────────▼─────────────┐
                │      VPN TUNNEL          │
                │   OpenVPN Connect        │
                └────────────┬─────────────┘
                             │
       ┌─────────────────────┴─────────────────────┐
       │                                            │
   ┌───▼─────────────────────────────────────────┐ │
   │    OBSERVABILITY STACK (obs.rectitude.net)   │ │
   │                                               │ │
   │  • Syslog Bridge  :1514  (UDP)               │ │
   │  • GoFlow2        :2055  (UDP - NetFlow)     │ │
   │  • GoFlow2        :4739  (UDP - IPFIX)       │ │
   │  • GoFlow2        :6343  (UDP - sFlow)       │ │
   │  • SNMP Exporter  :162   (UDP)               │ │
   │  • Vector         :8084  (HTTP - Win Events)  │ │
   │  • InfluxDB       :8086  (HTTP - Metrics)     │ │
   │  • Prometheus     :9090  (HTTP - Metrics)     │ │
   └───────────────────────────────────────────────┘
```

---

## 📝 **Required Code Changes**

### **1. Buffer Service HTTP API Server**

Add to `buffer-service/main.go`:

```go
// Add after line 206 in NewBufferManager:
func (bm *BufferManager) StartHTTPServer(port int) error {
    router := mux.NewRouter()
    
    // Ingestion endpoints
    router.HandleFunc("/api/v1/ingest/syslog", bm.handleSyslogIngest).Methods("POST")
    router.HandleFunc("/api/v1/ingest/netflow", bm.handleNetFlowIngest).Methods("POST")
    router.HandleFunc("/api/v1/ingest/snmp", bm.handleSNMPIngest).Methods("POST")
    router.HandleFunc("/api/v1/ingest/metrics", bm.handleMetricsIngest).Methods("POST")
    router.HandleFunc("/api/v1/ingest/windows", bm.handleWindowsIngest).Methods("POST")
    
    // Status and monitoring endpoints
    router.HandleFunc("/api/v1/status", bm.handleStatus).Methods("GET")
    router.HandleFunc("/api/v1/buffer/stats", bm.handleBufferStats).Methods("GET")
    router.HandleFunc("/health", bm.handleHealth).Methods("GET")
    
    addr := fmt.Sprintf("0.0.0.0:%d", port)
    logger.WithField("address", addr).Info("Starting HTTP API server")
    
    return http.ListenAndServe(addr, router)
}
```

### **2. Fluent Bit Output Change**

Replace lines 136-154 in `/config/fluent-bit.conf`:

```toml
# Buffer Service HTTP output (replaces direct syslog output)
[OUTPUT]
    Name                    http
    Match                   syslog.*
    Host                    127.0.0.1
    Port                    5005
    URI                     /api/v1/ingest/syslog
    Format                  json
    json_date_key           timestamp
    json_date_format        iso8601
    # Retry configuration
    Retry_Limit             False  # Infinite retry
    # Storage for offline operation
    storage.type            filesystem
    storage.total_limit_size 10GB
```

### **3. GoFlow2 Configuration**

Create `/config/goflow2.yml`:

```yaml
# GoFlow2 NetFlow/sFlow/IPFIX Collector Configuration
listen:
  netflow:
    - addr: "0.0.0.0:2055"
      type: "netflow"
  sflow:
    - addr: "0.0.0.0:6343"
      type: "sflow"
  ipfix:
    - addr: "0.0.0.0:4739"
      type: "ipfix"

logging:
  level: "info"
  file: "/var/log/noc-raven/goflow2.log"

output:
  type: "http"
  http:
    url: "http://127.0.0.1:5005/api/v1/ingest/netflow"
    method: "POST"
    timeout: "5s"
    batch_size: 1000
    batch_timeout: "1s"
    
# Buffering (in case buffer service is temporarily unavailable)
buffer:
  type: "disk"
  path: "/data/flows/buffer"
  max_size: "10GB"
```

### **4. Telegraf Output Update**

Replace Telegraf outputs section (lines 195-245):

```toml
# Primary output to buffer service
[[outputs.http]]
  url = "http://127.0.0.1:5005/api/v1/ingest/metrics"
  timeout = "5s"
  method = "POST"
  data_format = "json"
  content_encoding = "gzip"
  
  [outputs.http.headers]
    Content-Type = "application/json"
    X-Source = "telegraf-snmp"

# Prometheus metrics endpoint (for monitoring)
[[outputs.prometheus_client]]
  listen = ":9273"
  metric_version = 2
  path = "/metrics"
```

### **5. Supervisor Configuration for GoFlow2**

Create `/services/goflow2.conf`:

```ini
[program:goflow2]
command=/opt/noc-raven/bin/goflow2 -config /opt/noc-raven/config/goflow2.yml
directory=/opt/noc-raven
user=nocraven
autostart=true
autorestart=true
startsecs=5
stopwaitsecs=10
stdout_logfile=/var/log/noc-raven/goflow2.log
stderr_logfile=/var/log/noc-raven/goflow2-error.log
environment=HOME="/opt/noc-raven",USER="nocraven"
```

---

## 🎯 **Testing Plan After Fixes**

### **Phase 1: Component Testing**
1. ✅ Buffer service HTTP API responds on port 5005
2. ✅ All ingestion endpoints accept POST requests
3. ✅ Data is stored in SQLite database
4. ✅ File storage works for large payloads

### **Phase 2: Collection Testing**
1. ✅ Send test syslog → Fluent Bit → Buffer Service
2. ✅ Send test NetFlow → GoFlow2 → Buffer Service
3. ✅ Send test SNMP trap → Telegraf → Buffer Service
4. ✅ Verify all data appears in buffer storage

### **Phase 3: Forwarding Testing**
1. ✅ Simulate VPN connected state
2. ✅ Verify buffer service forwards to correct endpoints
3. ✅ Verify proper protocol usage (UDP vs HTTP)
4. ✅ Verify data reaches obs.rectitude.net

### **Phase 4: Offline Testing**
1. ✅ Block connectivity to obs.rectitude.net
2. ✅ Verify data continues to buffer locally
3. ✅ Verify 2-week retention works
4. ✅ Restore connectivity and verify replay

---

## 📊 **Priority Matrix**

| Fix | Priority | Complexity | Impact | Status |
|-----|----------|------------|--------|--------|
| Buffer Service HTTP API | 🔴 Critical | High | Blocks everything | ⏳ Pending |
| Fluent Bit Output Change | 🔴 Critical | Low | Required for syslog | ⏳ Pending |
| GoFlow2 Configuration | 🔴 Critical | Medium | Required for flows | ⏳ Pending |
| Telegraf Output Fix | 🟡 High | Low | Required for SNMP | ⏳ Pending |
| Buffer Forwarding Logic | 🔴 Critical | High | Required for remote send | ⏳ Pending |

---

## ✅ **Acceptance Criteria**

Before marking this deployment-ready:

- [ ] All collectors send to buffer service (not direct to remote)
- [ ] Buffer service stores data locally with 2-week retention
- [ ] Buffer service forwards to correct obs.rectitude.net endpoints
- [ ] VPN failure doesn't cause data loss
- [ ] VPN recovery triggers automatic data replay
- [ ] Web interface can view locally buffered data
- [ ] All services start automatically via supervisor
- [ ] Health checks pass for all components

---

**Next Steps:**
1. Implement buffer service HTTP API server
2. Update all collector configurations
3. Create GoFlow2 configuration file
4. Add supervisor configs for all services
5. Build and test Docker image
6. Deploy to OrbStack for E2E testing

---

*This document will be updated as fixes are implemented and tested.*
