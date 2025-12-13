import React from 'react';
import { useApiData, useServiceManager } from '../../hooks/useApiService';
import './NetFlow.css';

const NetFlow = () => {
  const { data: flows, loading, error } = useApiData('/flows', 5000);
  const { restartService, loading: restarting } = useServiceManager();

  const handleRestartFlow = async () => {
    try {
      await restartService('goflow2');
    } catch (err) {
      // Error handled by restartService toast notification
    }
  };

  if (loading && !flows) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>🌐 Flow Analysis</h1>
          <p>Loading network flow data...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>🌐 Flow Analysis</h1>
          <p className="error">Error loading flow data: {error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page">
      <div className="page-header">
        <div className="header-content">
          <div>
            <h1>🌐 Flow Analysis</h1>
            <p>Real-time NetFlow, IPFIX, and sFlow monitoring and analysis</p>
          </div>
          <div className="restart-buttons">
            <button
              className="restart-btn"
              onClick={handleRestartFlow}
              disabled={restarting}
            >
              {restarting ? 'Restarting...' : 'Restart Flow Service'}
            </button>
          </div>
        </div>
      </div>

      <div className="stats-row">
        <div className="stat-card">
          <h3>Total Flows</h3>
          <div className="stat-value">{flows?.total_flows || 0}</div>
        </div>
        <div className="stat-card">
          <h3>Active Connections</h3>
          <div className="stat-value">{flows?.flows?.length || 0}</div>
        </div>
        <div className="stat-card">
          <h3>Bytes/sec</h3>
          <div className="stat-value">{flows?.bytes_per_second || 0}</div>
        </div>
        <div className="stat-card">
          <h3>Packets/sec</h3>
          <div className="stat-value">{flows?.packets_per_second || 0}</div>
        </div>
      </div>

      <div className="content-grid">
        <div className="card">
          <h2>Top Talkers</h2>
          <div className="table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Source IP</th>
                  <th>Destination IP</th>
                  <th>Protocol</th>
                  <th>Bytes</th>
                  <th>Packets</th>
                </tr>
              </thead>
              <tbody>
                {Array.isArray(flows?.flows) ? flows.flows.slice(0, 10).map((flow, index) => (
                  <tr key={index}>
                    <td>{flow.src_ip || 'N/A'}</td>
                    <td>{flow.dst_ip || 'N/A'}</td>
                    <td>{flow.protocol || 'N/A'}</td>
                    <td>{flow.bytes?.toLocaleString() || 0}</td>
                    <td>{flow.packets?.toLocaleString() || 0}</td>
                  </tr>
                )) : (
                  <tr>
                    <td colSpan="5" className="no-data">No flow data available</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        <div className="card">
          <h2>Protocol Distribution</h2>
          <div className="protocol-stats">
            {flows?.protocol_stats ? Object.entries(flows.protocol_stats).map(([protocol, count]) => (
              <div key={protocol} className="protocol-item">
                <span className="protocol-name">{protocol.toUpperCase()}</span>
                <span className="protocol-count">{count.toLocaleString()}</span>
              </div>
            )) : (
              <div className="no-data">No protocol data available</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Port Activity</h2>
          <div className="port-stats">
            {flows?.port_stats ? Object.entries(flows.port_stats).slice(0, 10).map(([port, count]) => (
              <div key={port} className="port-item">
                <span className="port-number">Port {port}</span>
                <span className="port-count">{count.toLocaleString()}</span>
              </div>
            )) : (
              <div className="no-data">No port data available</div>
            )}
          </div>
        </div>

        <div className="card">
          <h2>Flow Timeline</h2>
          <div className="timeline-container">
            <div className="timeline-placeholder">
              <p>Flow timeline visualization would go here</p>
              <p className="note">Chart.js integration pending</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default NetFlow;
