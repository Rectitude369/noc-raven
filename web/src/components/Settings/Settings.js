import React, { useState, useEffect } from 'react';
import './Settings.css';

const Settings = ({ initialTab }) => {
  const [config, setConfig] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);
const [activeTab, setActiveTab] = useState(initialTab || 'collection');
  const [restarting, setRestarting] = useState({});

  // Load configuration on component mount
  useEffect(() => {
    loadConfiguration();
  }, []);

  const loadConfiguration = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const response = await fetch('/api/config');
      if (!response.ok) {
        throw new Error(`Failed to load configuration: ${response.status}`);
      }
      
      const configData = await response.json();
      setConfig(configData);
    } catch (err) {
      setError(`Failed to load configuration: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const saveConfiguration = async () => {
    if (!config) return;

    try {
      setSaving(true);
      setError(null);
      setSuccess(null);
      
      const response = await fetch('/api/config', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(config),
      });
      
      const result = await response.json();
      
      if (!response.ok) {
        throw new Error(result.error || `Save failed: ${response.status}`);
      }
      
      if (result.success) {
setSuccess('✅ Configuration saved and applied successfully!');
        window.dispatchEvent(new CustomEvent('toast', { detail: { type: 'success', message: 'Configuration saved and applied' } }));
        setTimeout(() => setSuccess(null), 5000);
        
        // Reload configuration to get any server-side changes
        await loadConfiguration();
      } else {
        throw new Error(result.message || 'Configuration save failed');
      }
      
    } catch (err) {
setError(`❌ Failed to save configuration: ${err.message}`);
      window.dispatchEvent(new CustomEvent('toast', { detail: { type: 'error', message: `Save failed: ${err.message}` } }));
    } finally {
      setSaving(false);
    }
  };

  const restartService = async (serviceName) => {
    try {
      setError(null);
      setRestarting(prev => ({ ...prev, [serviceName]: true }));
      
      const response = await fetch(`/api/services/${serviceName}/restart`, {
        method: 'POST',
      });
      
      let result = null;
      try {
        result = await response.json();
      } catch (_) {
        // Non-JSON response (e.g., nginx 404 HTML). Handle below.
      }
      
      if (!response.ok || (result && result.success === false)) {
        const msg = result?.message || result?.error || `HTTP ${response.status}`;
        throw new Error(msg);
      }
      
setSuccess(`✅ Service ${serviceName} restarted successfully!`);
      window.dispatchEvent(new CustomEvent('toast', { detail: { type: 'success', message: `Service ${serviceName} restarted` } }));
      setTimeout(() => setSuccess(null), 5000);
      
    } catch (err) {
setError(`❌ Failed to restart ${serviceName}: ${err.message}`);
      window.dispatchEvent(new CustomEvent('toast', { detail: { type: 'error', message: `Restart ${serviceName} failed: ${err.message}` } }));
    } finally {
      setRestarting(prev => ({ ...prev, [serviceName]: false }));
    }
  };

  const restartAllServices = async () => {
    const services = ['fluent-bit', 'goflow2', 'telegraf', 'vector', 'nginx'];
    setError(null);
    setSuccess(null);
    setRestarting(prev => ({ ...prev, all: true }));

    const results = [];
    for (const svc of services) {
      try {
        const resp = await fetch(`/api/services/${svc}/restart`, { method: 'POST' });
        let json = null;
        try { json = await resp.json(); } catch (_) {}
        if (!resp.ok || (json && json.success === false)) {
          const msg = json?.message || json?.error || `HTTP ${resp.status}`;
          results.push(`${svc}: failed (${msg})`);
        } else {
          results.push(`${svc}: ok`);
        }
      } catch (e) {
        results.push(`${svc}: error (${e.message})`);
      }
    }

    const failed = results.filter(r => !r.includes(': ok'));
    if (failed.length === 0) {
      setSuccess('✅ All services restarted successfully');
      setTimeout(() => setSuccess(null), 5000);
    } else {
      setError(`Some restarts failed: ${failed.join('; ')}`);
    }

    setRestarting(prev => ({ ...prev, all: false }));
  };

  const updateConfig = (path, value) => {
    if (!config) return;
    
    const newConfig = { ...config };
    const keys = path.split('.');
    let current = newConfig;
    
    for (let i = 0; i < keys.length - 1; i++) {
      if (!(keys[i] in current)) {
        current[keys[i]] = {};
      }
      current = current[keys[i]];
    }
    
    current[keys[keys.length - 1]] = value;
    setConfig(newConfig);
  };

  if (loading) {
    return (
      <div className="settings-container">
        <div className="loading-spinner">
          <div className="spinner"></div>
          <p>Loading configuration...</p>
        </div>
      </div>
    );
  }

  if (!config) {
    return (
      <div className="settings-container">
        <div className="error-message">
          <p>Failed to load configuration</p>
          <button onClick={loadConfiguration} className="btn-retry">
            Retry
          </button>
        </div>
      </div>
    );
  }

  const renderCollectionSettings = () => (
    <div className="settings-section">
      <h3>📥 Data Collection Settings</h3>
      
      {/* Syslog Settings */}
      <div className="setting-group">
        <h4>🟡 Syslog Collection</h4>
        <div className="setting-row">
          <label>
            <input
              type="checkbox"
              checked={config.collection?.syslog?.enabled || false}
              onChange={(e) => updateConfig('collection.syslog.enabled', e.target.checked)}
            />
            Enable Syslog Collection
          </label>
        </div>
        <div className="setting-row">
          <label>
            Port:
            <input
              type="number"
              value={config.collection?.syslog?.port || 514}
              onChange={(e) => updateConfig('collection.syslog.port', parseInt(e.target.value))}
              min="1"
              max="65535"
            />
          </label>
          <label>
            Protocol:
            <select
              value={config.collection?.syslog?.protocol || 'UDP'}
              onChange={(e) => updateConfig('collection.syslog.protocol', e.target.value)}
            >
              <option value="UDP">UDP</option>
              <option value="TCP">TCP</option>
            </select>
          </label>
        </div>
        <div className="setting-row">
          <label>
            Bind Address:
            <input
              type="text"
              value={config.collection?.syslog?.bind_address || '0.0.0.0'}
              onChange={(e) => updateConfig('collection.syslog.bind_address', e.target.value)}
              placeholder="0.0.0.0"
            />
          </label>
          <label>
            Rate Limit (msg/sec):
            <input
              type="number"
              value={config.collection?.syslog?.rate_limit || 10000}
              onChange={(e) => updateConfig('collection.syslog.rate_limit', parseInt(e.target.value))}
              min="1"
            />
          </label>
        </div>
      </div>

      {/* NetFlow Settings */}
      <div className="setting-group">
        <h4>🌐 NetFlow/IPFIX Collection</h4>
        <div className="setting-row">
          <label>
            <input
              type="checkbox"
              checked={config.collection?.netflow?.enabled || false}
              onChange={(e) => updateConfig('collection.netflow.enabled', e.target.checked)}
            />
            Enable NetFlow Collection
          </label>
        </div>
        <div className="setting-row">
          <label>
            NetFlow v5/v9 Port:
            <input
              type="number"
              value={config.collection?.netflow?.ports?.netflow_v5 || 2055}
              onChange={(e) => updateConfig('collection.netflow.ports.netflow_v5', parseInt(e.target.value))}
              min="1"
              max="65535"
            />
          </label>
          <label>
            IPFIX Port:
            <input
              type="number"
              value={config.collection?.netflow?.ports?.ipfix || 4739}
              onChange={(e) => updateConfig('collection.netflow.ports.ipfix', parseInt(e.target.value))}
              min="1"
              max="65535"
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            Cache Size:
            <input
              type="number"
              value={config.collection?.netflow?.cache_size || 1000000}
              onChange={(e) => updateConfig('collection.netflow.cache_size', parseInt(e.target.value))}
              min="1000"
            />
          </label>
          <label>
            Buffer Size (MB):
            <input
              type="number"
              value={config.collection?.netflow?.buffer_size_mb || 128}
              onChange={(e) => updateConfig('collection.netflow.buffer_size_mb', parseInt(e.target.value))}
              min="32"
              max="1024"
            />
          </label>
        </div>
      </div>

      {/* sFlow Settings */}
      <div className="setting-group">
        <h4>🌊 sFlow Collection</h4>
        <div className="setting-row">
          <label>
            <input
              type="checkbox"
              checked={config.collection?.sflow?.enabled || false}
              onChange={(e) => updateConfig('collection.sflow.enabled', e.target.checked)}
            />
            Enable sFlow Collection
          </label>
        </div>
        <div className="setting-row">
          <label>
            sFlow Port:
            <input
              type="number"
              value={config.collection?.sflow?.port || 6343}
              onChange={(e) => updateConfig('collection.sflow.port', parseInt(e.target.value))}
              min="1"
              max="65535"
            />
          </label>
          <label>
            Sample Rate:
            <input
              type="number"
              value={config.collection?.sflow?.sample_rate || 1000}
              onChange={(e) => updateConfig('collection.sflow.sample_rate', parseInt(e.target.value))}
              min="100"
              max="10000"
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            Agent Address:
            <input
              type="text"
              value={config.collection?.sflow?.agent_address || '0.0.0.0'}
              onChange={(e) => updateConfig('collection.sflow.agent_address', e.target.value)}
              placeholder="0.0.0.0"
            />
          </label>
          <label>
            Max Packet Size:
            <input
              type="number"
              value={config.collection?.sflow?.max_packet_size || 1500}
              onChange={(e) => updateConfig('collection.sflow.max_packet_size', parseInt(e.target.value))}
              min="512"
              max="9000"
            />
          </label>
        </div>
      </div>

      {/* SNMP Settings */}
      <div className="setting-group">
        <h4>📡 SNMP Monitoring</h4>
        <div className="setting-row">
          <label>
            <input
              type="checkbox"
              checked={config.collection?.snmp?.enabled || false}
              onChange={(e) => updateConfig('collection.snmp.enabled', e.target.checked)}
            />
            Enable SNMP Monitoring
          </label>
        </div>
        <div className="setting-row">
          <label>
            Trap Port:
            <input
              type="number"
              value={config.collection?.snmp?.trap_port || 162}
              onChange={(e) => updateConfig('collection.snmp.trap_port', parseInt(e.target.value))}
              min="1"
              max="65535"
            />
          </label>
          <label>
            Community String:
            <input
              type="text"
              value={config.collection?.snmp?.community || 'public'}
              onChange={(e) => updateConfig('collection.snmp.community', e.target.value)}
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            Version:
            <select
              value={config.collection?.snmp?.version || '2c'}
              onChange={(e) => updateConfig('collection.snmp.version', e.target.value)}
            >
              <option value="1">v1</option>
              <option value="2c">v2c</option>
              <option value="3">v3</option>
            </select>
          </label>
          <label>
            Poll Interval (seconds):
            <input
              type="number"
              value={config.collection?.snmp?.poll_interval || 300}
              onChange={(e) => updateConfig('collection.snmp.poll_interval', parseInt(e.target.value))}
              min="30"
            />
          </label>
        </div>
      </div>
    </div>
  );

  const renderForwardingSettings = () => (
    <div className="settings-section">
      <h3>📤 Data Forwarding Settings</h3>
      
      <div className="setting-row">
        <label>
          <input
            type="checkbox"
            checked={config.forwarding?.enabled !== undefined ? config.forwarding.enabled : true}
            onChange={(e) => updateConfig('forwarding.enabled', e.target.checked)}
          />
          Enable Data Forwarding
        </label>
      </div>

      {config.forwarding?.destinations?.map((destination, index) => (
        <div key={index} className="setting-group">
          <h4>🎯 Destination {index + 1}: {destination.name}</h4>
          <div className="setting-row">
            <label>
              Name:
              <input
                type="text"
                value={destination.name || ''}
                onChange={(e) => updateConfig(`forwarding.destinations.${index}.name`, e.target.value)}
              />
            </label>
            <label>
              Host:
              <input
                type="text"
                value={destination.host || ''}
                onChange={(e) => updateConfig(`forwarding.destinations.${index}.host`, e.target.value)}
                placeholder="hostname or IP address"
              />
            </label>
          </div>
          <div className="setting-row">
            <label>
              Syslog Port:
              <input
                type="number"
                value={destination.ports?.syslog || 514}
                onChange={(e) => updateConfig(`forwarding.destinations.${index}.ports.syslog`, parseInt(e.target.value))}
                min="1"
                max="65535"
              />
            </label>
            <label>
              NetFlow Port:
              <input
                type="number"
                value={destination.ports?.netflow || 2055}
                onChange={(e) => updateConfig(`forwarding.destinations.${index}.ports.netflow`, parseInt(e.target.value))}
                min="1"
                max="65535"
              />
            </label>
          </div>
          <div className="setting-row">
            <label>
              sFlow Port:
              <input
                type="number"
                value={destination.ports?.sflow || 6343}
                onChange={(e) => updateConfig(`forwarding.destinations.${index}.ports.sflow`, parseInt(e.target.value))}
                min="1"
                max="65535"
              />
            </label>
            <label>
              SNMP Port:
              <input
                type="number"
                value={destination.ports?.snmp || 162}
                onChange={(e) => updateConfig(`forwarding.destinations.${index}.ports.snmp`, parseInt(e.target.value))}
                min="1"
                max="65535"
              />
            </label>
          </div>
          <div className="setting-row">
            <label>
              <input
                type="checkbox"
                checked={destination.enabled || false}
                onChange={(e) => updateConfig(`forwarding.destinations.${index}.enabled`, e.target.checked)}
              />
              Enable this destination
            </label>
            <label>
              Retry Count:
              <input
                type="number"
                value={destination.retry_count || 3}
                onChange={(e) => updateConfig(`forwarding.destinations.${index}.retry_count`, parseInt(e.target.value))}
                min="0"
                max="10"
              />
            </label>
          </div>
        </div>
      ))}
    </div>
  );

  const renderAlertsSettings = () => (
    <div className="settings-section">
      <h3>🚨 Alerts & Notifications</h3>
      
      <div className="setting-group">
        <h4>📊 System Thresholds</h4>
        <div className="setting-row">
          <label>
            CPU Usage Threshold (%):
            <input
              type="number"
              value={config.alerts?.cpu_usage_threshold || 80}
              onChange={(e) => updateConfig('alerts.cpu_usage_threshold', parseInt(e.target.value))}
              min="10"
              max="99"
            />
          </label>
          <label>
            Memory Usage Threshold (%):
            <input
              type="number"
              value={config.alerts?.memory_usage_threshold || 90}
              onChange={(e) => updateConfig('alerts.memory_usage_threshold', parseInt(e.target.value))}
              min="10"
              max="99"
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            Disk Usage Threshold (%):
            <input
              type="number"
              value={config.alerts?.disk_usage_threshold || 85}
              onChange={(e) => updateConfig('alerts.disk_usage_threshold', parseInt(e.target.value))}
              min="10"
              max="99"
            />
          </label>
          <label>
            Flow Rate Threshold (flows/sec):
            <input
              type="number"
              value={config.alerts?.flow_rate_threshold || 10000}
              onChange={(e) => updateConfig('alerts.flow_rate_threshold', parseInt(e.target.value))}
              min="100"
            />
          </label>
        </div>
      </div>

      <div className="setting-group">
        <h4>📧 Email Notifications</h4>
        <div className="setting-row">
          <label>
            <input
              type="checkbox"
              checked={config.alerts?.email_notifications?.enabled || false}
              onChange={(e) => updateConfig('alerts.email_notifications.enabled', e.target.checked)}
            />
            Enable Email Alerts
          </label>
        </div>
        {config.alerts?.email_notifications?.enabled && (
          <>
            <div className="setting-row">
              <label>
                SMTP Server:
                <input
                  type="text"
                  value={config.alerts?.email_notifications?.smtp_server || ''}
                  onChange={(e) => updateConfig('alerts.email_notifications.smtp_server', e.target.value)}
                  placeholder="smtp.example.com"
                />
              </label>
              <label>
                SMTP Port:
                <input
                  type="number"
                  value={config.alerts?.email_notifications?.smtp_port || 587}
                  onChange={(e) => updateConfig('alerts.email_notifications.smtp_port', parseInt(e.target.value))}
                  min="1"
                  max="65535"
                />
              </label>
            </div>
            <div className="setting-row">
              <label>
                Username:
                <input
                  type="text"
                  value={config.alerts?.email_notifications?.username || ''}
                  onChange={(e) => updateConfig('alerts.email_notifications.username', e.target.value)}
                />
              </label>
              <label>
                Password:
                <input
                  type="password"
                  value={config.alerts?.email_notifications?.password || ''}
                  onChange={(e) => updateConfig('alerts.email_notifications.password', e.target.value)}
                />
              </label>
            </div>
          </>
        )}
      </div>
    </div>
  );

  const renderRetentionSettings = () => (
    <div className="settings-section">
      <h3>🗄️ Data Retention Settings</h3>
      
      <div className="setting-group">
        <h4>⏰ Retention Periods</h4>
        <div className="setting-row">
          <label>
            Syslog Messages (days):
            <input
              type="number"
              value={config.retention?.syslog_days || 14}
              onChange={(e) => updateConfig('retention.syslog_days', parseInt(e.target.value))}
              min="1"
              max="365"
            />
          </label>
          <label>
            Flow Data (days):
            <input
              type="number"
              value={config.retention?.flows_days || 7}
              onChange={(e) => updateConfig('retention.flows_days', parseInt(e.target.value))}
              min="1"
              max="365"
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            SNMP Data (days):
            <input
              type="number"
              value={config.retention?.snmp_days || 30}
              onChange={(e) => updateConfig('retention.snmp_days', parseInt(e.target.value))}
              min="1"
              max="365"
            />
          </label>
          <label>
            System Metrics (days):
            <input
              type="number"
              value={config.retention?.metrics_days || 30}
              onChange={(e) => updateConfig('retention.metrics_days', parseInt(e.target.value))}
              min="1"
              max="365"
            />
          </label>
        </div>
      </div>
    </div>
  );

  const renderPerformanceSettings = () => (
    <div className="settings-section">
      <h3>⚡ Performance Settings</h3>
      
      <div className="setting-group">
        <h4>⚙️ Buffer & Processing</h4>
        <div className="setting-row">
          <label>
            Buffer Size (MB):
            <input
              type="number"
              value={config.performance?.buffer_size_mb || 256}
              onChange={(e) => updateConfig('performance.buffer_size_mb', parseInt(e.target.value))}
              min="64"
              max="4096"
            />
          </label>
          <label>
            Worker Threads:
            <input
              type="number"
              value={config.performance?.worker_threads || 4}
              onChange={(e) => updateConfig('performance.worker_threads', parseInt(e.target.value))}
              min="1"
              max="16"
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            Batch Size:
            <input
              type="number"
              value={config.performance?.batch_size || 1000}
              onChange={(e) => updateConfig('performance.batch_size', parseInt(e.target.value))}
              min="100"
              max="10000"
            />
          </label>
          <label>
            Flush Interval (seconds):
            <input
              type="number"
              value={config.performance?.flush_interval_seconds || 30}
              onChange={(e) => updateConfig('performance.flush_interval_seconds', parseInt(e.target.value))}
              min="5"
              max="300"
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            <input
              type="checkbox"
              checked={config.performance?.enable_compression !== undefined ? config.performance.enable_compression : true}
              onChange={(e) => updateConfig('performance.enable_compression', e.target.checked)}
            />
            Enable Data Compression
          </label>
          <label>
            <input
              type="checkbox"
              checked={config.performance?.enable_deduplication !== undefined ? config.performance.enable_deduplication : true}
              onChange={(e) => updateConfig('performance.enable_deduplication', e.target.checked)}
            />
            Enable Deduplication
          </label>
        </div>
      </div>
    </div>
  );

  const renderWindowsSettings = () => (
    <div className="settings-section">
      <h3>🪟 Windows Events</h3>
      <div className="setting-group">
        <h4>Collector</h4>
        <div className="setting-row">
          <label>
            <input
              type="checkbox"
              checked={config.collection?.windows?.enabled !== undefined ? config.collection.windows.enabled : true}
              onChange={(e) => updateConfig('collection.windows.enabled', e.target.checked)}
            />
            Enable Windows Events Collector
          </label>
        </div>
        <div className="setting-row">
          <label>
            HTTP Listen Port:
            <input
              type="number"
              value={config.collection?.windows?.port || 8084}
              onChange={(e) => updateConfig('collection.windows.port', parseInt(e.target.value))}
              min="1024"
              max="65535"
            />
          </label>
          <label>
            Endpoint Path:
            <input
              type="text"
              value={config.collection?.windows?.path || '/ingest/windows'}
              onChange={(e) => updateConfig('collection.windows.path', e.target.value)}
            />
          </label>
        </div>
      </div>
    </div>
  );

  const renderForwardingWindows = () => (
    <div className="settings-section">
      <h3>🪟 Windows Events Forwarding</h3>
      <div className="setting-group">
        <div className="setting-row">
          <label>
            <input
              type="checkbox"
              checked={config.forwarding?.windows?.enabled !== undefined ? config.forwarding.windows.enabled : true}
              onChange={(e) => updateConfig('forwarding.windows.enabled', e.target.checked)}
            />
            Enable Windows Events Forwarding
          </label>
        </div>
        <div className="setting-row">
          <label>
            Protocol:
            <select
              value={config.forwarding?.windows?.protocol || 'HTTP'}
              onChange={(e) => updateConfig('forwarding.windows.protocol', e.target.value)}
            >
              <option value="HTTP">HTTP</option>
              <option value="HTTPS">HTTPS</option>
            </select>
          </label>
          <label>
            Host:
            <input
              type="text"
value={config.forwarding?.windows?.host || 'obs.rectitude.net'}
              onChange={(e) => updateConfig('forwarding.windows.host', e.target.value)}
              placeholder="example.com"
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            Port:
            <input
              type="number"
              value={config.forwarding?.windows?.port || 8084}
              onChange={(e) => updateConfig('forwarding.windows.port', parseInt(e.target.value))}
              min="1"
              max="65535"
            />
          </label>
          <label>
            Path:
            <input
              type="text"
              value={config.forwarding?.windows?.path || '/api/windows/events'}
              onChange={(e) => updateConfig('forwarding.windows.path', e.target.value)}
            />
          </label>
        </div>
        <div className="setting-row">
          <label>
            Auth Token (optional):
            <input
              type="text"
              value={config.forwarding?.windows?.token || ''}
              onChange={(e) => updateConfig('forwarding.windows.token', e.target.value)}
              placeholder="Bearer token"
            />
          </label>
        </div>
      </div>
    </div>
  );

  const renderTabContent = () => {
    switch (activeTab) {
      case 'collection':
        return renderCollectionSettings();
      case 'forwarding':
        return (
          <>
            {renderForwardingSettings()}
            {renderForwardingWindows()}
          </>
        );
      case 'alerts':
        return renderAlertsSettings();
      case 'retention':
        return renderRetentionSettings();
      case 'performance':
        return renderPerformanceSettings();
      case 'windows':
        return renderWindowsSettings();
      default:
        return renderCollectionSettings();
    }
  };

  return (
    <div className="settings-container">
      <div className="settings-header">
        <h2>⚙️ System Configuration</h2>
        <div className="settings-actions">
          <button
            onClick={loadConfiguration}
            className="btn-secondary"
            disabled={loading}
          >
            {loading ? '⏳ Loading...' : '🔄 Reload'}
          </button>
          <button
            onClick={saveConfiguration}
            className="btn-primary"
            disabled={saving || !config}
          >
            {saving ? '💾 Saving...' : '💾 Save Configuration'}
          </button>
        </div>
      </div>

      {error && (
        <div className="error-message">
          <p>{error}</p>
          <button onClick={() => setError(null)}>✕</button>
        </div>
      )}

      {success && (
        <div className="success-message">
          <p>{success}</p>
          <button onClick={() => setSuccess(null)}>✕</button>
        </div>
      )}

      <div className="settings-tabs">
        <button
          className={activeTab === 'collection' ? 'tab active' : 'tab'}
          onClick={() => setActiveTab('collection')}
        >
          📥 Collection
        </button>
        <button
          className={activeTab === 'forwarding' ? 'tab active' : 'tab'}
          onClick={() => setActiveTab('forwarding')}
        >
          📤 Forwarding
        </button>
        <button
          className={activeTab === 'alerts' ? 'tab active' : 'tab'}
          onClick={() => setActiveTab('alerts')}
        >
          🚨 Alerts
        </button>
        <button
          className={activeTab === 'retention' ? 'tab active' : 'tab'}
          onClick={() => setActiveTab('retention')}
        >
          🗄️ Retention
        </button>
        <button
          className={activeTab === 'performance' ? 'tab active' : 'tab'}
          onClick={() => setActiveTab('performance')}
        >
          ⚡ Performance
        </button>
        <button
          className={activeTab === 'windows' ? 'tab active' : 'tab'}
          onClick={() => setActiveTab('windows')}
        >
          🪟 Windows Events
        </button>
      </div>

      <div className="settings-content">
        {renderTabContent()}
      </div>

      <div className="service-management">
        <h3>🔄 Service Management</h3>
        <p>Restart individual services to apply configuration changes:</p>
        <div className="service-buttons">
          <button
            onClick={() => restartService('fluent-bit')}
            className="btn-service"
            title="Restart Fluent Bit (Syslog Collection)"
            disabled={restarting['fluent-bit']}
          >
            {restarting['fluent-bit'] ? '🔄 Restarting...' : '📝 Restart Syslog Service'}
          </button>
          <button
            onClick={() => restartService('goflow2')}
            className="btn-service"
            title="Restart GoFlow2 (NetFlow/IPFIX Collection)"
            disabled={restarting['goflow2']}
          >
            {restarting['goflow2'] ? '🔄 Restarting...' : '🌊 Restart NetFlow Service'}
          </button>
          <button
            onClick={() => restartService('goflow2')}
            className="btn-service"
            title="Restart sFlow (GoFlow2) Collection"
            disabled={restarting['goflow2']}
          >
            {restarting['goflow2'] ? '🔄 Restarting...' : '🌀 Restart sFlow Service'}
          </button>
          <button
            onClick={() => restartService('telegraf')}
            className="btn-service"
            title="Restart Telegraf (SNMP Monitoring)"
            disabled={restarting['telegraf']}
          >
            {restarting['telegraf'] ? '🔄 Restarting...' : '📡 Restart SNMP Service'}
          </button>
          <button
            onClick={() => restartService('vector')}
            className="btn-service"
            title="Restart Windows Events"
            disabled={restarting['vector']}
          >
            {restarting['vector'] ? '🔄 Restarting...' : '🪟 Restart Windows Events'}
          </button>
          <button
            onClick={restartAllServices}
            className="btn-service btn-service-all"
            title="Restart All Services"
            disabled={Object.values(restarting).some(r => r)}
          >
            {Object.values(restarting).some(r => r) ? '🔄 Restarting...' : '🔄 Restart All Services'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default Settings;
