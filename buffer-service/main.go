package main

import (
	"bytes"
	"compress/gzip"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	_ "github.com/mattn/go-sqlite3"
	"github.com/sirupsen/logrus"
)

var logger = logrus.New()

func initLogger() {
	// Configure structured logging
	logger.SetFormatter(&logrus.JSONFormatter{
		TimestampFormat: time.RFC3339,
	})

	// Set log level from environment
	if level := os.Getenv("LOG_LEVEL"); level != "" {
		if parsedLevel, err := logrus.ParseLevel(level); err == nil {
			logger.SetLevel(parsedLevel)
		}
	} else {
		logger.SetLevel(logrus.InfoLevel)
	}

	// Configure output
	if logPath := os.Getenv("BUFFER_LOG_PATH"); logPath != "" {
		if file, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644); err == nil {
			logger.SetOutput(file)
		} else {
			logger.WithError(err).Warn("Failed to open log file, using stdout")
		}
	}

	logger.WithFields(logrus.Fields{
		"service": "buffer-service",
		"version": "2.0.0",
		"pid":     os.Getpid(),
	}).Info("Logger initialized")
}

// BufferConfig represents the buffer manager configuration
type BufferConfig struct {
	Enabled            bool                  `json:"enabled"`
	MaxRetentionDays   int                   `json:"max_retention_days"`
	MaxDbSizeGB        int                   `json:"max_db_size_gb"`
	MaxFileSizeGB      int                   `json:"max_file_size_gb"`
	CleanupIntervalMin int                   `json:"cleanup_interval_minutes"`
	CompressionEnabled bool                  `json:"compression_enabled"`
	VPNFailoverEnabled bool                  `json:"vpn_failover_enabled"`
	VPNCheckInterval   int                   `json:"vpn_check_interval_seconds"`
	ForwardingEnabled  bool                  `json:"forwarding_enabled"`
	ForwardingURL      string                `json:"forwarding_url"`
	MaxBufferSizeMB    int                   `json:"max_buffer_size_mb"`
	OverflowAction     string                `json:"overflow_action"` // "drop_oldest", "drop_newest", "compress_more"
	Services           map[string]ServiceCfg `json:"services"`
}

type ServiceCfg struct {
	Enabled         bool   `json:"enabled"`
	BufferMode      string `json:"buffer_mode"` // "database" or "files"
	MaxRecords      int    `json:"max_records"`
	MaxFileSizeMB   int    `json:"max_file_size_mb"`
	CompressionMode string `json:"compression_mode"` // "none", "gzip", "zstd"
	Priority        int    `json:"priority"`         // 1-10, higher numbers = higher priority
	RetentionHours  int    `json:"retention_hours"`
}

// TelemetryRecord represents a buffered telemetry record
type TelemetryRecord struct {
	ID         int64  `json:"id"`
	Service    string `json:"service"`
	Timestamp  int64  `json:"timestamp"`
	DataType   string `json:"data_type"`
	DataSize   int64  `json:"data_size"`
	FilePath   string `json:"file_path,omitempty"`
	JsonData   string `json:"json_data,omitempty"`
	SourceIP   string `json:"source_ip,omitempty"`
	Forwarded  int    `json:"forwarded"`
	RetryCount int    `json:"retry_count"`
	CreatedAt  int64  `json:"created_at"`
	ExpiresAt  int64  `json:"expires_at"`
}

// BufferStats represents buffer statistics
type BufferStats struct {
	Service      string `json:"service"`
	TotalRecords int64  `json:"total_records"`
	TotalSize    int64  `json:"total_size"`
	OldestRecord int64  `json:"oldest_record"`
	NewestRecord int64  `json:"newest_record"`
	Forwarded    int64  `json:"forwarded"`
	Pending      int64  `json:"pending"`
}

// VPNStatus represents the current VPN connection state
type VPNStatus struct {
	Connected    bool      `json:"connected"`
	LastCheck    time.Time `json:"last_check"`
	Latency      int       `json:"latency_ms"`
	FailureCount int       `json:"failure_count"`
	LastError    string    `json:"last_error,omitempty"`
}

// BufferManager manages the telemetry buffer system
type BufferManager struct {
	db          *sql.DB
	config      BufferConfig
	dataPath    string
	vpnStatus   VPNStatus
	vpnMutex    sync.RWMutex
	forwardChan chan TelemetryRecord
	stopChan    chan bool
}

// NewBufferManager creates a new buffer manager instance
func NewBufferManager(dataPath string) (*BufferManager, error) {
	bm := &BufferManager{
		dataPath:    dataPath,
		forwardChan: make(chan TelemetryRecord, 1000),
		stopChan:    make(chan bool, 1),
		vpnStatus: VPNStatus{
			Connected: false,
			LastCheck: time.Now(),
		},
		config: BufferConfig{
			Enabled:            true,
			MaxRetentionDays:   14,
			MaxDbSizeGB:        2,
			MaxFileSizeGB:      10,
			CleanupIntervalMin: 60,
			CompressionEnabled: true,
			VPNFailoverEnabled: true,
			VPNCheckInterval:   30,
			ForwardingEnabled:  false,
			ForwardingURL:      "https://obs.rectitude.net/api/ingest",
			MaxBufferSizeMB:    1000,
			OverflowAction:     "drop_oldest",
			Services: map[string]ServiceCfg{
				"vector": {
					Enabled:         true,
					BufferMode:      "database",
					MaxRecords:      1000000,
					CompressionMode: "gzip",
					Priority:        8,
					RetentionHours:  336, // 14 days
				},
				"fluent-bit": {
					Enabled:         true,
					BufferMode:      "files",
					MaxFileSizeMB:   100,
					CompressionMode: "gzip",
					Priority:        9,
					RetentionHours:  336,
				},
				"goflow2": {
					Enabled:         true,
					BufferMode:      "files",
					MaxRecords:      10000000,
					CompressionMode: "gzip",
					Priority:        10,
					RetentionHours:  168, // 7 days for flows
				},
				"telegraf": {
					Enabled:         true,
					BufferMode:      "database",
					MaxRecords:      500000,
					CompressionMode: "gzip",
					Priority:        7,
					RetentionHours:  720, // 30 days for metrics
				},
			},
		},
	}

	// Initialize database
	if err := bm.initDatabase(); err != nil {
		return nil, fmt.Errorf("failed to initialize database: %v", err)
	}

	// Load configuration
	if err := bm.loadConfig(); err != nil {
		logger.WithError(err).Warn("Failed to load config, using defaults")
	}

	// Start background workers
	go bm.startVPNMonitor()
	go bm.startForwardingWorker()

	return bm, nil
}

// compressData compresses data using the specified compression mode
func (bm *BufferManager) compressData(data []byte, mode string) ([]byte, error) {
	if mode == "none" || !bm.config.CompressionEnabled {
		return data, nil
	}

	switch mode {
	case "gzip":
		var buf bytes.Buffer
		gzWriter := gzip.NewWriter(&buf)
		if _, err := gzWriter.Write(data); err != nil {
			return nil, err
		}
		if err := gzWriter.Close(); err != nil {
			return nil, err
		}
		return buf.Bytes(), nil
	default:
		return data, nil
	}
}

// decompressData decompresses data based on compression mode
func (bm *BufferManager) decompressData(data []byte, mode string) ([]byte, error) {
	if mode == "none" || len(data) == 0 {
		return data, nil
	}

	switch mode {
	case "gzip":
		buf := bytes.NewReader(data)
		gzReader, err := gzip.NewReader(buf)
		if err != nil {
			return nil, err
		}
		defer gzReader.Close()
		return io.ReadAll(gzReader)
	default:
		return data, nil
	}
}

// checkVPNConnection checks if VPN is connected by testing connectivity
func (bm *BufferManager) checkVPNConnection() VPNStatus {
	bm.vpnMutex.Lock()
	defer bm.vpnMutex.Unlock()

	status := VPNStatus{
		LastCheck: time.Now(),
		Connected: false,
	}

	// Test connectivity to forwarding endpoint
	if bm.config.ForwardingURL != "" {
		client := &http.Client{
			Timeout: 5 * time.Second,
		}
		start := time.Now()
		resp, err := client.Get(strings.Replace(bm.config.ForwardingURL, "/api/ingest", "/health", 1))
		latency := time.Since(start)

		if err == nil && resp.StatusCode < 400 {
			status.Connected = true
			status.Latency = int(latency.Milliseconds())
			status.FailureCount = 0
			resp.Body.Close()
		} else {
			status.Connected = false
			status.FailureCount = bm.vpnStatus.FailureCount + 1
			if err != nil {
				status.LastError = err.Error()
			} else {
				status.LastError = fmt.Sprintf("HTTP %d", resp.StatusCode)
				resp.Body.Close()
			}
		}
	}

	bm.vpnStatus = status
	return status
}

// startVPNMonitor runs the VPN connection monitoring loop
func (bm *BufferManager) startVPNMonitor() {
	if !bm.config.VPNFailoverEnabled {
		return
	}

	ticker := time.NewTicker(time.Duration(bm.config.VPNCheckInterval) * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			status := bm.checkVPNConnection()
			log.Printf("VPN Status: connected=%v, latency=%dms, failures=%d",
				status.Connected, status.Latency, status.FailureCount)

			// If VPN came back online, start forwarding buffered data
			if status.Connected && bm.config.ForwardingEnabled {
				go bm.forwardBufferedRecords()
			}
		case <-bm.stopChan:
			return
		}
	}
}

// startForwardingWorker handles real-time forwarding when VPN is available
func (bm *BufferManager) startForwardingWorker() {
	for {
		select {
		case record := <-bm.forwardChan:
			bm.vpnMutex.RLock()
			vpnConnected := bm.vpnStatus.Connected
			bm.vpnMutex.RUnlock()

			if vpnConnected && bm.config.ForwardingEnabled {
				if err := bm.forwardRecord(record); err != nil {
					log.Printf("Failed to forward record: %v, buffering instead", err)
					// Store in buffer if forwarding fails
					if err := bm.StoreRecord(record); err != nil {
						log.Printf("Failed to buffer record: %v", err)
					}
				}
			} else {
				// VPN not available, store in buffer
				if err := bm.StoreRecord(record); err != nil {
					log.Printf("Failed to buffer record: %v", err)
				}
			}
		case <-bm.stopChan:
			return
		}
	}
}

// forwardRecord sends a single record to the remote endpoint using appropriate protocol
func (bm *BufferManager) forwardRecord(record TelemetryRecord) error {
	// Route to appropriate forwarding method based on data type and service
	switch record.DataType {
	case "syslog":
		return bm.forwardSyslogUDP(record)
	case "netflow":
		return bm.forwardNetFlowUDP(record)
	case "snmp":
		return bm.forwardSNMPUDP(record)
	case "windows_events":
		return bm.forwardWindowsHTTP(record)
	case "metrics":
		return bm.forwardMetricsHTTP(record)
	default:
		logger.WithFields(logrus.Fields{
			"data_type": record.DataType,
			"service":   record.Service,
		}).Warn("Unknown data type, skipping forward")
		return nil
	}
}

// forwardSyslogUDP forwards syslog data via UDP to obs.rectitude.net:1514
func (bm *BufferManager) forwardSyslogUDP(record TelemetryRecord) error {
	conn, err := net.Dial("udp", "obs.rectitude.net:1514")
	if err != nil {
		return err
	}
	defer conn.Close()

	// Set write deadline
	conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	
	// Send raw JSON data
	_, err = conn.Write([]byte(record.JsonData))
	return err
}

// forwardNetFlowUDP forwards NetFlow/sFlow/IPFIX data via UDP
func (bm *BufferManager) forwardNetFlowUDP(record TelemetryRecord) error {
	// Parse JSON to determine flow type and route to appropriate port
	var flowData map[string]interface{}
	if err := json.Unmarshal([]byte(record.JsonData), &flowData); err != nil {
		return err
	}

	port := "2055" // Default NetFlow port
	if flowType, ok := flowData["flow_type"].(string); ok {
		switch flowType {
		case "sflow":
			port = "6343"
		case "ipfix":
			port = "4739"
		}
	}

	conn, err := net.Dial("udp", fmt.Sprintf("obs.rectitude.net:%s", port))
	if err != nil {
		return err
	}
	defer conn.Close()

	conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	_, err = conn.Write([]byte(record.JsonData))
	return err
}

// forwardSNMPUDP forwards SNMP trap data via UDP to port 162
func (bm *BufferManager) forwardSNMPUDP(record TelemetryRecord) error {
	conn, err := net.Dial("udp", "obs.rectitude.net:162")
	if err != nil {
		return err
	}
	defer conn.Close()

	conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	_, err = conn.Write([]byte(record.JsonData))
	return err
}

// forwardWindowsHTTP forwards Windows Events via HTTP to Vector endpoint
func (bm *BufferManager) forwardWindowsHTTP(record TelemetryRecord) error {
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	req, err := http.NewRequest("POST", "http://obs.rectitude.net:8084/", bytes.NewBufferString(record.JsonData))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "noc-raven/2.0")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	return nil
}

// forwardMetricsHTTP forwards metrics to InfluxDB
func (bm *BufferManager) forwardMetricsHTTP(record TelemetryRecord) error {
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	// InfluxDB write endpoint
	url := "http://obs.rectitude.net:8086/api/v2/write?org=rectitude&bucket=r369"
	req, err := http.NewRequest("POST", url, bytes.NewBufferString(record.JsonData))
	if err != nil {
		return err
	}

	// Add InfluxDB auth token from environment
	token := os.Getenv("INFLUXDB_TOKEN")
	if token == "" {
		token = "4DhBMQYYZZRlI_ER8WyVusydNbTC8JTDjvf8vD-MJIgfGdtXdF0cJB6DwjyjJ7hZxtpLtvqwJ7gAfCCHFXh5ow=="
	}

	req.Header.Set("Authorization", "Token "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	return nil
}

// forwardBufferedRecords forwards all buffered records when VPN comes online
func (bm *BufferManager) forwardBufferedRecords() {
	log.Println("Starting to forward buffered records...")

	// Get all unforwarded records
	query := `
		SELECT id, service, timestamp, data_type, data_size, json_data, source_ip
		FROM telemetry_buffer 
		WHERE forwarded = 0 
		ORDER BY timestamp ASC
		LIMIT 1000
	`

	rows, err := bm.db.Query(query)
	if err != nil {
		log.Printf("Failed to query buffered records: %v", err)
		return
	}
	defer rows.Close()

	forwarded := 0
	for rows.Next() {
		var record TelemetryRecord
		err := rows.Scan(&record.ID, &record.Service, &record.Timestamp,
			&record.DataType, &record.DataSize, &record.JsonData, &record.SourceIP)
		if err != nil {
			log.Printf("Failed to scan record: %v", err)
			continue
		}

		if err := bm.forwardRecord(record); err != nil {
			log.Printf("Failed to forward buffered record %d: %v", record.ID, err)
			break // Stop if forwarding fails
		}

		// Mark as forwarded
		updateQuery := "UPDATE telemetry_buffer SET forwarded = 1 WHERE id = ?"
		if _, err := bm.db.Exec(updateQuery, record.ID); err != nil {
			log.Printf("Failed to mark record as forwarded: %v", err)
		}

		forwarded++
	}

	if forwarded > 0 {
		log.Printf("Forwarded %d buffered records", forwarded)
	}
}

// handleBufferOverflow handles buffer overflow based on configuration
func (bm *BufferManager) handleBufferOverflow() error {
	switch bm.config.OverflowAction {
	case "drop_oldest":
		return bm.dropOldestRecords(1000)
	case "drop_newest":
		return fmt.Errorf("buffer full, dropping newest records")
	case "compress_more":
		return bm.compressOldRecords()
	default:
		return bm.dropOldestRecords(1000)
	}
}

// dropOldestRecords removes the oldest records from buffer
func (bm *BufferManager) dropOldestRecords(count int) error {
	query := "DELETE FROM telemetry_buffer WHERE id IN (SELECT id FROM telemetry_buffer ORDER BY timestamp ASC LIMIT ?)"
	result, err := bm.db.Exec(query, count)
	if err != nil {
		return err
	}

	rowsAffected, _ := result.RowsAffected()
	log.Printf("Dropped %d oldest records due to buffer overflow", rowsAffected)
	return nil
}

// compressOldRecords applies additional compression to old records
func (bm *BufferManager) compressOldRecords() error {
	// This is a placeholder for more advanced compression logic
	log.Println("Applying additional compression to old records")
	return nil
}

// getBufferSizeMB returns current buffer size in MB
func (bm *BufferManager) getBufferSizeMB() (int, error) {
	query := "SELECT COALESCE(SUM(data_size), 0) FROM telemetry_buffer"
	var totalSize int64
	err := bm.db.QueryRow(query).Scan(&totalSize)
	if err != nil {
		return 0, err
	}
	return int(totalSize / 1024 / 1024), nil
}

// initDatabase initializes the SQLite database
func (bm *BufferManager) initDatabase() error {
	dbDir := filepath.Join(bm.dataPath, "buffer", "db")
	if err := os.MkdirAll(dbDir, 0755); err != nil {
		return fmt.Errorf("failed to create database directory: %v", err)
	}

	dbPath := filepath.Join(dbDir, "telemetry.db")
	var err error
	bm.db, err = sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_synchronous=NORMAL&_cache_size=10000")
	if err != nil {
		return fmt.Errorf("failed to open database: %v", err)
	}

	// Test connection
	if err := bm.db.Ping(); err != nil {
		return fmt.Errorf("failed to ping database: %v", err)
	}

	// Create tables
	if err := bm.createTables(); err != nil {
		return fmt.Errorf("failed to create tables: %v", err)
	}

	return nil
}

// createTables creates the database schema
func (bm *BufferManager) createTables() error {
	schema := `
	CREATE TABLE IF NOT EXISTS telemetry_buffer (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		service TEXT NOT NULL,
		timestamp INTEGER NOT NULL,
		data_type TEXT NOT NULL,
		data_size INTEGER NOT NULL,
		file_path TEXT,
		json_data TEXT,
		source_ip TEXT,
		forwarded INTEGER DEFAULT 0,
		retry_count INTEGER DEFAULT 0,
		created_at INTEGER NOT NULL,
		expires_at INTEGER NOT NULL
	);

	CREATE INDEX IF NOT EXISTS idx_telemetry_timestamp ON telemetry_buffer(timestamp);
	CREATE INDEX IF NOT EXISTS idx_telemetry_service ON telemetry_buffer(service);
	CREATE INDEX IF NOT EXISTS idx_telemetry_forwarded ON telemetry_buffer(forwarded);
	CREATE INDEX IF NOT EXISTS idx_telemetry_expires ON telemetry_buffer(expires_at);

	CREATE TABLE IF NOT EXISTS buffer_stats (
		id INTEGER PRIMARY KEY,
		service TEXT NOT NULL,
		metric_name TEXT NOT NULL,
		metric_value INTEGER NOT NULL,
		updated_at INTEGER NOT NULL
	);
	`

	_, err := bm.db.Exec(schema)
	return err
}

// loadConfig loads configuration from file
func (bm *BufferManager) loadConfig() error {
	configPath := filepath.Join(bm.dataPath, "buffer", "config", "buffer-config.json")

	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		// Create default config
		return bm.saveConfig()
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}

	return json.Unmarshal(data, &bm.config)
}

// saveConfig saves configuration to file
func (bm *BufferManager) saveConfig() error {
	configDir := filepath.Join(bm.dataPath, "buffer", "config")
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return err
	}

	configPath := filepath.Join(configDir, "buffer-config.json")
	data, err := json.MarshalIndent(bm.config, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(configPath, data, 0644)
}

// StoreRecord stores a telemetry record in the buffer with compression and overflow handling
func (bm *BufferManager) StoreRecord(record TelemetryRecord) error {
	// Check buffer size and handle overflow if necessary
	currentSize, err := bm.getBufferSizeMB()
	if err == nil && currentSize > bm.config.MaxBufferSizeMB {
		log.Printf("Buffer size (%dMB) exceeds limit (%dMB), handling overflow",
			currentSize, bm.config.MaxBufferSizeMB)
		if err := bm.handleBufferOverflow(); err != nil {
			log.Printf("Failed to handle buffer overflow: %v", err)
		}
	}

	now := time.Now().Unix()

	// Use service-specific retention if configured
	serviceCfg, exists := bm.config.Services[record.Service]
	var expiresAt int64
	if exists && serviceCfg.RetentionHours > 0 {
		expiresAt = now + int64(serviceCfg.RetentionHours*60*60)
	} else {
		expiresAt = now + int64(bm.config.MaxRetentionDays*24*60*60)
	}

	// Compress JSON data if compression is enabled for this service
	jsonData := record.JsonData
	if exists && serviceCfg.CompressionMode != "none" {
		compressed, err := bm.compressData([]byte(record.JsonData), serviceCfg.CompressionMode)
		if err != nil {
			log.Printf("Failed to compress data for service %s: %v", record.Service, err)
		} else {
			jsonData = string(compressed)
			// Update data size to compressed size
			record.DataSize = int64(len(compressed))
		}
	}

	query := `
		INSERT INTO telemetry_buffer 
		(service, timestamp, data_type, data_size, file_path, json_data, source_ip, 
		 forwarded, retry_count, created_at, expires_at) 
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`

	_, err = bm.db.Exec(query,
		record.Service, record.Timestamp, record.DataType, record.DataSize,
		record.FilePath, jsonData, record.SourceIP,
		record.Forwarded, record.RetryCount, now, expiresAt)

	return err
}

// GetStats returns buffer statistics for a service
func (bm *BufferManager) GetStats(service string) (*BufferStats, error) {
	stats := &BufferStats{Service: service}

	query := `
		SELECT 
			COUNT(*) as total_records,
			COALESCE(SUM(data_size), 0) as total_size,
			COALESCE(MIN(timestamp), 0) as oldest_record,
			COALESCE(MAX(timestamp), 0) as newest_record,
			COALESCE(SUM(CASE WHEN forwarded = 1 THEN 1 ELSE 0 END), 0) as forwarded,
			COALESCE(SUM(CASE WHEN forwarded = 0 THEN 1 ELSE 0 END), 0) as pending
		FROM telemetry_buffer 
		WHERE service = ?
	`

	err := bm.db.QueryRow(query, service).Scan(
		&stats.TotalRecords,
		&stats.TotalSize,
		&stats.OldestRecord,
		&stats.NewestRecord,
		&stats.Forwarded,
		&stats.Pending,
	)

	return stats, err
}

// CleanupExpiredRecords removes expired records
func (bm *BufferManager) CleanupExpiredRecords() error {
	now := time.Now().Unix()
	query := "DELETE FROM telemetry_buffer WHERE expires_at < ?"
	result, err := bm.db.Exec(query, now)
	if err != nil {
		return err
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected > 0 {
		log.Printf("Cleaned up %d expired records", rowsAffected)
	}

	return nil
}

// HTTP Handlers

func (bm *BufferManager) handleStatus(w http.ResponseWriter, r *http.Request) {
	services := []string{"vector", "fluent-bit", "goflow2", "telegraf"}
	bufferSizeMB, _ := bm.getBufferSizeMB()

	bm.vpnMutex.RLock()
	vpnStatus := bm.vpnStatus
	bm.vpnMutex.RUnlock()

	status := map[string]interface{}{
		"enabled":            bm.config.Enabled,
		"compression":        bm.config.CompressionEnabled,
		"vpn_failover":       bm.config.VPNFailoverEnabled,
		"forwarding":         bm.config.ForwardingEnabled,
		"buffer_size_mb":     bufferSizeMB,
		"max_buffer_size_mb": bm.config.MaxBufferSizeMB,
		"buffer_usage_pct":   float64(bufferSizeMB) / float64(bm.config.MaxBufferSizeMB) * 100,
		"vpn_status":         vpnStatus,
		"services":           make(map[string]*BufferStats),
		"updated_at":         time.Now().Unix(),
	}

	for _, service := range services {
		stats, err := bm.GetStats(service)
		if err != nil {
			log.Printf("Error getting stats for %s: %v", service, err)
			continue
		}
		status["services"].(map[string]*BufferStats)[service] = stats
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func (bm *BufferManager) handleServiceStats(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	service := vars["service"]

	stats, err := bm.GetStats(service)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error getting stats: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

func (bm *BufferManager) handleCleanup(w http.ResponseWriter, r *http.Request) {
	if err := bm.CleanupExpiredRecords(); err != nil {
		http.Error(w, fmt.Sprintf("Cleanup failed: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "cleanup completed"})
}

func (bm *BufferManager) handleConfig(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(bm.config)
	case "POST":
		var newConfig BufferConfig
		if err := json.NewDecoder(r.Body).Decode(&newConfig); err != nil {
			http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
			return
		}

		bm.config = newConfig
		if err := bm.saveConfig(); err != nil {
			http.Error(w, fmt.Sprintf("Failed to save config: %v", err), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "config updated"})
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleVPNStatus returns current VPN connection status
func (bm *BufferManager) handleVPNStatus(w http.ResponseWriter, r *http.Request) {
	bm.vpnMutex.RLock()
	status := bm.vpnStatus
	bm.vpnMutex.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

// handleForwardBuffer manually triggers forwarding of buffered data
func (bm *BufferManager) handleForwardBuffer(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	bm.vpnMutex.RLock()
	vpnConnected := bm.vpnStatus.Connected
	bm.vpnMutex.RUnlock()

	if !vpnConnected {
		http.Error(w, "VPN not connected", http.StatusServiceUnavailable)
		return
	}

	go bm.forwardBufferedRecords()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "forwarding started"})
}

// handleBufferStats returns comprehensive buffer statistics
func (bm *BufferManager) handleBufferStats(w http.ResponseWriter, r *http.Request) {
	bufferSize, _ := bm.getBufferSizeMB()

	// Get record counts by service
	serviceCounts := make(map[string]int64)
	services := []string{"vector", "fluent-bit", "goflow2", "telegraf"}

	for _, service := range services {
		stats, err := bm.GetStats(service)
		if err == nil {
			serviceCounts[service] = stats.TotalRecords
		}
	}

	// Get total record count
	var totalRecords int64
	query := "SELECT COUNT(*) FROM telemetry_buffer"
	bm.db.QueryRow(query).Scan(&totalRecords)

	// Get oldest and newest record timestamps
	var oldestRecord, newestRecord int64
	query = "SELECT COALESCE(MIN(timestamp), 0), COALESCE(MAX(timestamp), 0) FROM telemetry_buffer"
	bm.db.QueryRow(query).Scan(&oldestRecord, &newestRecord)

	stats := map[string]interface{}{
		"buffer_size_mb":      bufferSize,
		"max_buffer_size_mb":  bm.config.MaxBufferSizeMB,
		"usage_percentage":    float64(bufferSize) / float64(bm.config.MaxBufferSizeMB) * 100,
		"total_records":       totalRecords,
		"oldest_record":       oldestRecord,
		"newest_record":       newestRecord,
		"retention_days":      bm.config.MaxRetentionDays,
		"compression_enabled": bm.config.CompressionEnabled,
		"overflow_action":     bm.config.OverflowAction,
		"service_records":     serviceCounts,
		"timestamp":           time.Now().Unix(),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

// Generic ingestion handler
func (bm *BufferManager) ingestData(w http.ResponseWriter, r *http.Request, service string, dataType string) {
	var payload interface{}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}

	// Convert payload to JSON
	jsonData, err := json.Marshal(payload)
	if err != nil {
		http.Error(w, fmt.Sprintf("JSON marshal error: %v", err), http.StatusInternalServerError)
		return
	}

	// Create telemetry record
	record := TelemetryRecord{
		Service:   service,
		Timestamp: time.Now().Unix(),
		DataType:  dataType,
		DataSize:  int64(len(jsonData)),
		JsonData:  string(jsonData),
		SourceIP:  r.RemoteAddr,
		Forwarded: 0,
	}

	// Try to forward immediately via channel if VPN failover is enabled
	if bm.config.VPNFailoverEnabled {
		select {
		case bm.forwardChan <- record:
			// Record sent to forwarding worker
		default:
			// Channel full, store in buffer
			if err := bm.StoreRecord(record); err != nil {
				http.Error(w, fmt.Sprintf("Storage error: %v", err), http.StatusInternalServerError)
				return
			}
		}
	} else {
		// Store directly in buffer
		if err := bm.StoreRecord(record); err != nil {
			http.Error(w, fmt.Sprintf("Storage error: %v", err), http.StatusInternalServerError)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "success",
		"service":   service,
		"data_type": dataType,
		"timestamp": time.Now().Unix(),
	})
}

// handleSyslogIngest handles syslog data from Fluent Bit
func (bm *BufferManager) handleSyslogIngest(w http.ResponseWriter, r *http.Request) {
	bm.ingestData(w, r, "fluent-bit", "syslog")
}

// handleNetFlowIngest handles NetFlow/sFlow/IPFIX data from GoFlow2
func (bm *BufferManager) handleNetFlowIngest(w http.ResponseWriter, r *http.Request) {
	bm.ingestData(w, r, "goflow2", "netflow")
}

// handleSNMPIngest handles SNMP trap data from Telegraf
func (bm *BufferManager) handleSNMPIngest(w http.ResponseWriter, r *http.Request) {
	bm.ingestData(w, r, "telegraf", "snmp")
}

// handleMetricsIngest handles metrics data from Telegraf
func (bm *BufferManager) handleMetricsIngest(w http.ResponseWriter, r *http.Request) {
	bm.ingestData(w, r, "telegraf", "metrics")
}

// handleWindowsIngest handles Windows Events data from Vector
func (bm *BufferManager) handleWindowsIngest(w http.ResponseWriter, r *http.Request) {
	bm.ingestData(w, r, "vector", "windows_events")
}

// handleIngest handles telemetry data ingestion from Vector
func (bm *BufferManager) handleIngest(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse incoming telemetry data from Vector
	var payload []map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}

	processed := 0
	errors := 0

	for _, event := range payload {
		// Extract common fields
		service := "vector"
		if s, ok := event["source_type"].(string); ok && s != "" {
			service = s
		}

		dataType := "unknown"
		if dt, ok := event["data_type"].(string); ok {
			dataType = dt
		} else if source, ok := event["source"].(string); ok {
			dataType = source
		}

		timestamp := time.Now().Unix()
		if ts, ok := event["timestamp"]; ok {
			if tsFloat, ok := ts.(float64); ok {
				timestamp = int64(tsFloat)
			} else if tsString, ok := ts.(string); ok {
				if parsedTime, err := time.Parse(time.RFC3339, tsString); err == nil {
					timestamp = parsedTime.Unix()
				}
			}
		}

		sourceIP := ""
		if ip, ok := event["source_ip"].(string); ok {
			sourceIP = ip
		} else if host, ok := event["host"].(string); ok {
			sourceIP = host
		}

		// Serialize event data
		jsonData, err := json.Marshal(event)
		if err != nil {
			log.Printf("Failed to marshal event data: %v", err)
			errors++
			continue
		}

		// Create telemetry record
		record := TelemetryRecord{
			Service:   service,
			Timestamp: timestamp,
			DataType:  dataType,
			DataSize:  int64(len(jsonData)),
			JsonData:  string(jsonData),
			SourceIP:  sourceIP,
			Forwarded: 0, // Start as buffered
		}

		// Try to forward immediately via channel if VPN failover is enabled
		if bm.config.VPNFailoverEnabled {
			select {
			case bm.forwardChan <- record:
				// Record sent to forwarding worker
			default:
				// Channel full, store in buffer
				if err := bm.StoreRecord(record); err != nil {
					log.Printf("Failed to store record: %v", err)
					errors++
					continue
				}
			}
		} else {
			// Store directly in buffer
			if err := bm.StoreRecord(record); err != nil {
				log.Printf("Failed to store record: %v", err)
				errors++
				continue
			}
		}

		processed++
	}

	// Return response
	response := map[string]interface{}{
		"status":    "success",
		"processed": processed,
		"errors":    errors,
		"timestamp": time.Now().Unix(),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// startCleanupWorker starts the background cleanup worker
func (bm *BufferManager) startCleanupWorker() {
	ticker := time.NewTicker(time.Duration(bm.config.CleanupIntervalMin) * time.Minute)
	go func() {
		for range ticker.C {
			if err := bm.CleanupExpiredRecords(); err != nil {
				log.Printf("Cleanup worker error: %v", err)
			}
		}
	}()
}

func main() {
	// Initialize structured logging
	initLogger()

	dataPath := os.Getenv("DATA_PATH")
	if dataPath == "" {
		dataPath = "/data"
	}

	port := os.Getenv("BUFFER_PORT")
	if port == "" {
		port = "5005"
	}

	bm, err := NewBufferManager(dataPath)
	if err != nil {
		logger.WithError(err).Fatal("Failed to initialize buffer manager")
	}
	defer bm.db.Close()

	// Start cleanup worker
	bm.startCleanupWorker()

	// Setup HTTP routes
	r := mux.NewRouter()
	api := r.PathPrefix("/api/buffer").Subrouter()

	// Core buffer operations
	api.HandleFunc("/status", bm.handleStatus).Methods("GET")
	api.HandleFunc("/stats", bm.handleBufferStats).Methods("GET")
	api.HandleFunc("/stats/{service}", bm.handleServiceStats).Methods("GET")
	api.HandleFunc("/cleanup", bm.handleCleanup).Methods("POST")
	api.HandleFunc("/config", bm.handleConfig).Methods("GET", "POST")
	api.HandleFunc("/ingest", bm.handleIngest).Methods("POST")

	// V1 API - Per-service ingestion endpoints
	v1 := r.PathPrefix("/api/v1").Subrouter()
	v1.HandleFunc("/ingest/syslog", bm.handleSyslogIngest).Methods("POST")
	v1.HandleFunc("/ingest/netflow", bm.handleNetFlowIngest).Methods("POST")
	v1.HandleFunc("/ingest/snmp", bm.handleSNMPIngest).Methods("POST")
	v1.HandleFunc("/ingest/metrics", bm.handleMetricsIngest).Methods("POST")
	v1.HandleFunc("/ingest/windows", bm.handleWindowsIngest).Methods("POST")
	v1.HandleFunc("/status", bm.handleStatus).Methods("GET")
	v1.HandleFunc("/buffer/stats", bm.handleBufferStats).Methods("GET")

	// VPN and forwarding operations
	api.HandleFunc("/vpn/status", bm.handleVPNStatus).Methods("GET")
	api.HandleFunc("/forward", bm.handleForwardBuffer).Methods("POST")

	// Health check with enhanced status
	r.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		bufferSize, _ := bm.getBufferSizeMB()
		bm.vpnMutex.RLock()
		vpnConnected := bm.vpnStatus.Connected
		bm.vpnMutex.RUnlock()

		health := map[string]interface{}{
			"status":           "healthy",
			"timestamp":        time.Now().Unix(),
			"buffer_size_mb":   bufferSize,
			"vpn_connected":    vpnConnected,
			"services_enabled": len(bm.config.Services),
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(health)
	})

	// Graceful shutdown setup
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		<-signalChan
		logger.Info("Shutdown signal received, closing gracefully...")

		// Signal workers to stop
		close(bm.stopChan)

		// Close database connection
		bm.db.Close()

		logger.Info("Buffer Manager shutdown complete")
		os.Exit(0)
	}()

	logger.WithFields(logrus.Fields{
		"port":         port,
		"data_path":    dataPath,
		"vpn_failover": bm.config.VPNFailoverEnabled,
		"compression":  bm.config.CompressionEnabled,
		"forwarding":   bm.config.ForwardingEnabled,
	}).Info("Buffer Manager starting")

	if err := http.ListenAndServe(":"+port, r); err != nil {
		logger.WithError(err).Fatal("HTTP server failed")
	}
}
