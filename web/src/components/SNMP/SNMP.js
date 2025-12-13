import React from 'react';
import { useApiData, useServiceManager } from '../../hooks/useApiService';
import './SNMP.css';

const SNMP = () => {
  const { data: devices, loading, error } = useApiData('/snmp', 5000);
  const { restartService, loading: restarting } = useServiceManager();

  const handleRestartService = async () => {
    try {
      await restartService('telegraf');
    } catch (err) {
      // Error handled by restartService toast notification
    }
  };

  if (loading && !devices) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>🔌 SNMP Monitoring</h1>
          <p>Loading SNMP device data...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>🔌 SNMP Monitoring</h1>
          <p className="error">Error loading SNMP data: {error}</p>
        </div>
      </div>
    );
  }

  const getStatusClass = (status) => {
    const statusMap = {
      'online': 'success',
      'up': 'success',
      'healthy': 'success',
      'warning': 'warning',
      'degraded': 'warning',
      'offline': 'error',
      'down': 'error',
      'failed': 'error'
    };
    return statusMap[status?.toLowerCase()] || 'unknown';
  };

  return (
    <div className="page">
      <div className="page-header">
        <h1>🔌 SNMP Monitoring</h1>
        <p>Network device monitoring via SNMP</p>
        <button 
          className="restart-btn" 
          onClick={handleRestartService}
          disabled={restarting}
        >
          {restarting ? 'Restarting...' : 'Restart SNMP Service'}
        </button>
      </div>

      <div className="stats-row">
        <div className="stat-card">
          <h3>Total Devices</h3>
          <div className="stat-value">{devices?.total_devices || 0}</div>
        </div>
        <div className="stat-card success">
          <h3>Online</h3>
          <div className="stat-value">{devices?.device_status?.online || 0}</div>
        </div>
        <div className="stat-card warning">
          <h3>Warning</h3>
          <div className="stat-value">{devices?.device_status?.warning || 0}</div>
        </div>
        <div className="stat-card error">
          <h3>Offline</h3>
          <div className="stat-value">{devices?.device_status?.offline || 0}</div>
        </div>
      </div>

      <div className="content-grid">
        <div className="card devices-table">
          <h2>Device Status</h2>
          <div className="table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Device</th>
                  <th>IP Address</th>
                  <th>Type</th>
                  <th>Status</th>
                  <th>Uptime</th>
                  <th>Last Seen</th>
                </tr>
              </thead>
              <tbody>
                {devices?.devices?.map((device, index) => (
                  <tr key={index} className={`device-row status-${getStatusClass(device.status)}`}>
                    <td className="device-name">{device.name || device.hostname || 'Unknown'}</td>
                    <td className="device-ip">{device.ip || device.address || 'N/A'}</td>
                    <td className="device-type">{device.type || device.sysDescr || 'Unknown'}</td>
                    <td className={`device-status status-${getStatusClass(device.status)}`}>
                      {device.status || 'unknown'}
                    </td>
                    <td className="device-uptime">{device.uptime || 'N/A'}</td>
                    <td className="device-last-seen">
                      {device.lastSeen ? new Date(device.lastSeen).toLocaleString() : 'N/A'}
                    </td>
                  </tr>
                )) || (
                  <tr>
                    <td colSpan="6" className="no-data">No SNMP devices configured or discovered</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        <div className="card">
          <h2>Device Types</h2>
          <div className="type-stats">
            {devices?.device_types ? Object.entries(devices.device_types).map(([type, count]) => (
              <div key={type} className="type-item">
                <span className="type-name">{type}</span>
                <span className="type-count">{count}</span>
              </div>
            )) : (
              <div className="no-data">No device type data available</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Recent Traps</h2>
          <div className="traps-list">
            {Array.isArray(devices?.recent_traps) ? devices.recent_traps.slice(0, 10).map((trap, index) => (
              <div key={index} className={`trap-item severity-${trap.severity || 'info'}`}>
                <div className="trap-header">
                  <span className="trap-source">{trap.source || 'Unknown'}</span>
                  <span className="trap-time">
                    {trap.timestamp ? new Date(trap.timestamp).toLocaleString() : 'N/A'}
                  </span>
                </div>
                <div className="trap-message">{trap.message || trap.oid || 'No message'}</div>
              </div>
            )) : (
              <div className="no-data">No recent SNMP traps</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Performance Metrics</h2>
          <div className="metrics-list">
            {devices?.performance_metrics && devices.performance_metrics !== null && typeof devices.performance_metrics === 'object' && !Array.isArray(devices.performance_metrics) && Object.keys(devices.performance_metrics).length > 0 ? (
              Object.entries(devices.performance_metrics).map(([metric, value]) => (
                <div key={metric} className="metric-item">
                  <span className="metric-name">{metric.replace(/_/g, ' ').toUpperCase()}</span>
                  <span className="metric-value">{value}</span>
                </div>
              ))
            ) : (
              <div className="no-data">No performance metrics available</div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default SNMP;
