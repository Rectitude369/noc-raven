import React from 'react';
import { useApiData, useServiceManager } from '../../hooks/useApiService';
import './BufferStatus.css';

const BufferStatus = () => {
  const { data: bufferData, loading, error } = useApiData('/buffer', 3000);
  const { restartService, loading: restarting } = useServiceManager();

  const handleRestartService = async () => {
    try {
      await restartService('buffer-service');
    } catch (err) {
      // Error handled by restartService toast notification
    }
  };

  if (loading && !bufferData) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>📦 Buffer Status</h1>
          <p>Loading buffer status...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>📦 Buffer Status</h1>
          <p className="error">Error loading buffer status: {error}</p>
        </div>
      </div>
    );
  }

  const getHealthStatus = (health) => {
    if (health >= 90) return { status: 'excellent', color: '#27ae60' };
    if (health >= 70) return { status: 'good', color: '#f39c12' };
    if (health >= 50) return { status: 'warning', color: '#e67e22' };
    return { status: 'critical', color: '#e74c3c' };
  };

  const formatBytes = (bytes) => {
    if (!bytes) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${sizes[i]}`;
  };

  const formatUptime = (seconds) => {
    if (!seconds) return '0s';
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    
    if (days > 0) return `${days}d ${hours}h ${minutes}m`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
  };

  const healthInfo = getHealthStatus(bufferData?.health_score || 0);

  return (
    <div className="page">
      <div className="page-header">
        <h1>📦 Buffer Status</h1>
        <p>Telemetry data buffering and forwarding status</p>
        <button 
          className="restart-btn" 
          onClick={handleRestartService}
          disabled={restarting}
        >
          {restarting ? 'Restarting...' : 'Restart Buffer Service'}
        </button>
      </div>

      <div className="stats-row">
        <div className="stat-card">
          <h3>Health Score</h3>
          <div className="stat-value" style={{ color: healthInfo.color }}>
            {bufferData?.health_score || 0}%
          </div>
          <div className="stat-label">{healthInfo.status}</div>
        </div>
        <div className="stat-card">
          <h3>Buffer Size</h3>
          <div className="stat-value">{formatBytes(bufferData?.buffer_size)}</div>
          <div className="stat-label">current usage</div>
        </div>
        <div className="stat-card">
          <h3>Messages/sec</h3>
          <div className="stat-value">{bufferData?.throughput?.messages_per_second || 0}</div>
          <div className="stat-label">current rate</div>
        </div>
        <div className="stat-card">
          <h3>Uptime</h3>
          <div className="stat-value">{formatUptime(bufferData?.uptime)}</div>
          <div className="stat-label">service uptime</div>
        </div>
      </div>

      <div className="content-grid">
        <div className="card">
          <h2>Buffer Utilization</h2>
          <div className="buffer-utilization">
            <div className="utilization-bar">
              <div 
                className="utilization-fill"
                style={{ 
                  width: `${bufferData?.utilization_percent || 0}%`,
                  backgroundColor: bufferData?.utilization_percent > 80 ? '#e74c3c' : 
                                  bufferData?.utilization_percent > 60 ? '#f39c12' : '#27ae60'
                }}
              ></div>
            </div>
            <div className="utilization-stats">
              <span>Used: {formatBytes(bufferData?.buffer_used)}</span>
              <span>Available: {formatBytes(bufferData?.buffer_available)}</span>
              <span>Total: {formatBytes(bufferData?.buffer_total)}</span>
            </div>
          </div>
        </div>

        <div className="card">
          <h2>Throughput Metrics</h2>
          <div className="throughput-metrics">
            <div className="metric-item">
              <span className="metric-label">Messages In</span>
              <span className="metric-value">{bufferData?.throughput?.messages_in || 0}</span>
            </div>
            <div className="metric-item">
              <span className="metric-label">Messages Out</span>
              <span className="metric-value">{bufferData?.throughput?.messages_out || 0}</span>
            </div>
            <div className="metric-item">
              <span className="metric-label">Bytes In</span>
              <span className="metric-value">{formatBytes(bufferData?.throughput?.bytes_in)}</span>
            </div>
            <div className="metric-item">
              <span className="metric-label">Bytes Out</span>
              <span className="metric-value">{formatBytes(bufferData?.throughput?.bytes_out)}</span>
            </div>
            <div className="metric-item">
              <span className="metric-label">Dropped Messages</span>
              <span className="metric-value error">{bufferData?.throughput?.dropped_messages || 0}</span>
            </div>
            <div className="metric-item">
              <span className="metric-label">Error Rate</span>
              <span className="metric-value error">{bufferData?.throughput?.error_rate || 0}%</span>
            </div>
          </div>
        </div>

        <div className="card">
          <h2>Buffer Queues</h2>
          <div className="queue-list">
            {bufferData?.queues?.map((queue, index) => (
              <div key={index} className="queue-item">
                <div className="queue-header">
                  <span className="queue-name">{queue.name}</span>
                  <span className={`queue-status ${queue.status?.toLowerCase()}`}>
                    {queue.status || 'Unknown'}
                  </span>
                </div>
                <div className="queue-stats">
                  <span>Size: {queue.size || 0}</span>
                  <span>Max: {queue.max_size || 'N/A'}</span>
                  <span>Rate: {queue.processing_rate || 0}/s</span>
                </div>
                <div className="queue-bar">
                  <div 
                    className="queue-fill"
                    style={{ 
                      width: `${queue.utilization_percent || 0}%`,
                      backgroundColor: queue.utilization_percent > 80 ? '#e74c3c' : 
                                      queue.utilization_percent > 60 ? '#f39c12' : '#27ae60'
                    }}
                  ></div>
                </div>
              </div>
            )) || (
              <div className="no-data">No queue data available</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Forwarding Destinations</h2>
          <div className="destination-list">
            {bufferData?.destinations?.map((dest, index) => (
              <div key={index} className="destination-item">
                <div className="destination-header">
                  <span className="destination-name">{dest.name}</span>
                  <span className={`destination-status ${dest.status?.toLowerCase()}`}>
                    {dest.status || 'Unknown'}
                  </span>
                </div>
                <div className="destination-details">
                  <span>Endpoint: {dest.endpoint || 'N/A'}</span>
                  <span>Protocol: {dest.protocol || 'N/A'}</span>
                  <span>Last Success: {dest.last_success ? new Date(dest.last_success).toLocaleString() : 'Never'}</span>
                </div>
                <div className="destination-metrics">
                  <span>Sent: {dest.messages_sent || 0}</span>
                  <span>Failed: {dest.messages_failed || 0}</span>
                  <span>Success Rate: {dest.success_rate || 0}%</span>
                </div>
              </div>
            )) || (
              <div className="no-data">No destination data available</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Recent Activity</h2>
          <div className="activity-log">
            {Array.isArray(bufferData?.recent_activity) ? bufferData.recent_activity.slice(0, 20).map((activity, index) => (
              <div key={index} className={`activity-item ${activity.level?.toLowerCase()}`}>
                <span className="activity-time">
                  {activity.timestamp ? new Date(activity.timestamp).toLocaleTimeString() : 'N/A'}
                </span>
                <span className="activity-message">{activity.message || 'No message'}</span>
              </div>
            )) : (
              <div className="no-data">No recent activity</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Performance Metrics</h2>
          <div className="performance-metrics">
            <div className="metric-group">
              <h4>CPU Usage</h4>
              <div className="metric-bar">
                <div 
                  className="metric-fill"
                  style={{ 
                    width: `${bufferData?.performance?.cpu_usage || 0}%`,
                    backgroundColor: bufferData?.performance?.cpu_usage > 80 ? '#e74c3c' : 
                                    bufferData?.performance?.cpu_usage > 60 ? '#f39c12' : '#27ae60'
                  }}
                ></div>
              </div>
              <span>{bufferData?.performance?.cpu_usage || 0}%</span>
            </div>
            <div className="metric-group">
              <h4>Memory Usage</h4>
              <div className="metric-bar">
                <div 
                  className="metric-fill"
                  style={{ 
                    width: `${bufferData?.performance?.memory_usage || 0}%`,
                    backgroundColor: bufferData?.performance?.memory_usage > 80 ? '#e74c3c' : 
                                    bufferData?.performance?.memory_usage > 60 ? '#f39c12' : '#27ae60'
                  }}
                ></div>
              </div>
              <span>{bufferData?.performance?.memory_usage || 0}%</span>
            </div>
            <div className="metric-group">
              <h4>Disk I/O</h4>
              <div className="metric-bar">
                <div 
                  className="metric-fill"
                  style={{ 
                    width: `${bufferData?.performance?.disk_io || 0}%`,
                    backgroundColor: bufferData?.performance?.disk_io > 80 ? '#e74c3c' : 
                                    bufferData?.performance?.disk_io > 60 ? '#f39c12' : '#27ae60'
                  }}
                ></div>
              </div>
              <span>{bufferData?.performance?.disk_io || 0}%</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default BufferStatus;
