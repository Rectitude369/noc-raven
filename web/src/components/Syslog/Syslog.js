import React from 'react';
import { useApiData, useServiceManager } from '../../hooks/useApiService';
import './Syslog.css';

const Syslog = () => {
  const { data: logs, loading, error } = useApiData('/syslog', 3000);
  const { restartService, loading: restarting } = useServiceManager();

  const handleRestartService = async () => {
    try {
      await restartService('fluent-bit');
    } catch (err) {
      // Error handled by restartService toast notification
    }
  };

  if (loading && !logs) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>📋 Syslog Monitor</h1>
          <p>Loading syslog data...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>📋 Syslog Monitor</h1>
          <p className="error">Error loading syslog data: {error}</p>
        </div>
      </div>
    );
  }

  const getSeverityClass = (severity) => {
    const severityMap = {
      'emergency': 'critical',
      'alert': 'critical',
      'critical': 'critical',
      'error': 'error',
      'warning': 'warning',
      'notice': 'info',
      'info': 'info',
      'debug': 'debug'
    };
    return severityMap[severity?.toLowerCase()] || 'info';
  };

  return (
    <div className="page">
      <div className="page-header">
        <div className="header-content">
          <div>
            <h1>📋 Syslog Monitor</h1>
            <p>Real-time system log monitoring and analysis</p>
          </div>
          <button
            className="restart-btn"
            onClick={handleRestartService}
            disabled={restarting}
          >
            {restarting ? 'Restarting...' : 'Restart Syslog Service'}
          </button>
        </div>
      </div>

      <div className="stats-row">
        <div className="stat-card">
          <h3>Total Logs</h3>
          <div className="stat-value">{logs?.total_logs || 0}</div>
        </div>
        <div className="stat-card error">
          <h3>Errors</h3>
          <div className="stat-value">{logs?.log_levels?.error || 0}</div>
        </div>
        <div className="stat-card warning">
          <h3>Warnings</h3>
          <div className="stat-value">{logs?.log_levels?.warning || 0}</div>
        </div>
        <div className="stat-card info">
          <h3>Info</h3>
          <div className="stat-value">{logs?.log_levels?.info || 0}</div>
        </div>
      </div>

      <div className="content-grid">
        <div className="card logs-table">
          <h2>Recent Log Messages</h2>
          <div className="table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Timestamp</th>
                  <th>Host</th>
                  <th>Severity</th>
                  <th>Facility</th>
                  <th>Message</th>
                </tr>
              </thead>
              <tbody>
                {Array.isArray(logs?.logs) ? logs.logs.slice(0, 50).map((log, index) => (
                  <tr key={index} className={`log-row severity-${getSeverityClass(log.severity)}`}>
                    <td className="timestamp">
                      {log.timestamp ? new Date(log.timestamp).toLocaleString() : 'N/A'}
                    </td>
                    <td className="hostname">{log.hostname || log.host || 'Unknown'}</td>
                    <td className={`severity severity-${getSeverityClass(log.severity)}`}>
                      {log.severity || 'info'}
                    </td>
                    <td className="facility">{log.facility || 'system'}</td>
                    <td className="message">{log.message || log.msg || 'No message'}</td>
                  </tr>
                )) : (
                  <tr>
                    <td colSpan="5" className="no-data">No log data available</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        <div className="card">
          <h2>Log Level Distribution</h2>
          <div className="level-stats">
            {logs?.log_levels ? Object.entries(logs.log_levels).map(([level, count]) => (
              <div key={level} className={`level-item level-${getSeverityClass(level)}`}>
                <span className="level-name">{level.toUpperCase()}</span>
                <span className="level-count">{count.toLocaleString()}</span>
                <div className="level-bar">
                  <div 
                    className={`level-fill level-${getSeverityClass(level)}`}
                    style={{ width: `${Math.min((count / Math.max(...Object.values(logs.log_levels))) * 100, 100)}%` }}
                  ></div>
                </div>
              </div>
            )) : (
              <div className="no-data">No log level data available</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Top Hosts</h2>
          <div className="host-stats">
            {Array.isArray(logs?.top_hosts) ? logs.top_hosts.slice(0, 10).map((host, index) => (
              <div key={index} className="host-item">
                <span className="host-name">{host.hostname || host.host || 'Unknown'}</span>
                <span className="host-count">{host.count?.toLocaleString() || 0}</span>
              </div>
            )) : (
              <div className="no-data">No host data available</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Message Patterns</h2>
          <div className="pattern-stats">
            {Array.isArray(logs?.common_patterns) ? logs.common_patterns.slice(0, 8).map((pattern, index) => (
              <div key={index} className="pattern-item">
                <div className="pattern-text">{pattern.pattern || 'Unknown pattern'}</div>
                <div className="pattern-count">{pattern.count?.toLocaleString() || 0} occurrences</div>
              </div>
            )) : (
              <div className="no-data">No pattern data available</div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default Syslog;
