import React from 'react';
import { useApiData, useServiceManager } from '../../hooks/useApiService';
import './WindowsEvents.css';

const WindowsEvents = () => {
  const { data: events, loading, error } = useApiData('/windows', 5000);
  const { restartService, loading: restarting } = useServiceManager();

  const handleRestartService = async () => {
    try {
      await restartService('vector');
    } catch (err) {
      // Error handled by restartService toast notification
    }
  };

  if (loading && !events) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>🪟 Windows Events</h1>
          <p>Loading Windows event data...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="page">
        <div className="page-header">
          <h1>🪟 Windows Events</h1>
          <p className="error">Error loading Windows events: {error}</p>
        </div>
      </div>
    );
  }

  const getSeverityClass = (level) => {
    const levelMap = {
      'critical': 'critical',
      'error': 'error', 
      'warning': 'warning',
      'information': 'info',
      'verbose': 'debug'
    };
    return levelMap[level?.toLowerCase()] || 'info';
  };

  return (
    <div className="page">
      <div className="page-header">
        <h1>🪟 Windows Events</h1>
        <p>Windows Event Log monitoring via Vector HTTP endpoint</p>
        <button
          className="restart-btn"
          onClick={handleRestartService}
          disabled={restarting}
        >
          {restarting ? 'Restarting...' : 'Restart Windows Events Service'}
        </button>
      </div>

      <div className="stats-row">
        <div className="stat-card">
          <h3>Total Events</h3>
          <div className="stat-value">{events?.total_events || 0}</div>
        </div>
        <div className="stat-card critical">
          <h3>Critical</h3>
          <div className="stat-value">{events?.event_levels?.critical || 0}</div>
        </div>
        <div className="stat-card error">
          <h3>Errors</h3>
          <div className="stat-value">{events?.event_levels?.error || 0}</div>
        </div>
        <div className="stat-card warning">
          <h3>Warnings</h3>
          <div className="stat-value">{events?.event_levels?.warning || 0}</div>
        </div>
      </div>

      <div className="content-grid">
        <div className="card events-table">
          <h2>Recent Windows Events</h2>
          <div className="table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Level</th>
                  <th>Source</th>
                  <th>Event ID</th>
                  <th>Computer</th>
                  <th>Message</th>
                </tr>
              </thead>
              <tbody>
                {Array.isArray(events?.events) ? events.events.slice(0, 50).map((event, index) => (
                  <tr key={index} className={`event-row severity-${getSeverityClass(event.level)}`}>
                    <td className="timestamp">
                      {event.timestamp ? new Date(event.timestamp).toLocaleString() : 'N/A'}
                    </td>
                    <td className={`level severity-${getSeverityClass(event.level)}`}>
                      {event.level || 'Unknown'}
                    </td>
                    <td className="source">{event.source || event.provider_name || 'Unknown'}</td>
                    <td className="event-id">{event.event_id || 'N/A'}</td>
                    <td className="computer">{event.computer || event.hostname || 'Unknown'}</td>
                    <td className="message">{event.message || event.description || 'No message'}</td>
                  </tr>
                )) : (
                  <tr>
                    <td colSpan="6" className="no-data">No Windows events received</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        <div className="card">
          <h2>Event Sources</h2>
          <div className="source-stats">
            <div className="no-data">No event source data available</div>
          </div>
        </div>

        <div className="card">
          <h2>Event Levels</h2>
          <div className="level-stats">
            <div className="no-data">No event level data available</div>
          </div>
        </div>

        <div className="card">
          <h2>Top Computers</h2>
          <div className="computer-stats">
            {Array.isArray(events?.top_computers) ? events.top_computers.slice(0, 10).map((computer, index) => (
              <div key={index} className="computer-item">
                <span className="computer-name">{computer.name || 'Unknown'}</span>
                <span className="computer-count">{computer.count || 0}</span>
              </div>
            )) : (
              <div className="no-data">No computer data available</div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default WindowsEvents;
