/**
 * NoC Raven API Service
 * Centralized API communication layer
 */

class ApiService {
  constructor(baseURL = '/api') {
    this.baseURL = baseURL;
  }

  async fetchData(endpoint) {
    try {
      const response = await fetch(`${this.baseURL}${endpoint}`);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      this.showToast('error', `API Error: ${error.message}`);
      return null;
    }
  }

  async postData(endpoint, data) {
    try {
      const response = await fetch(`${this.baseURL}${endpoint}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(data),
      });
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      
      return await response.json();
    } catch (error) {
      this.showToast('error', `API Error: ${error.message}`);
      throw error;
    }
  }

  async restartService(serviceName) {
    try {
      const response = await this.postData(`/services/${serviceName}/restart`, {});

      // Map technical service names to user-friendly display names
      const displayNames = {
        'vector': 'Windows Events',
        'fluent-bit': 'Syslog',
        'goflow2': 'Flow',
        'telegraf': 'SNMP',
        'buffer-service': 'Buffer'
      };

      const displayName = displayNames[serviceName] || serviceName;
      this.showToast('success', `Service ${displayName} restarted successfully`);
      return response;
    } catch (error) {
      const displayNames = {
        'vector': 'Windows Events',
        'fluent-bit': 'Syslog',
        'goflow2': 'Flow',
        'telegraf': 'SNMP',
        'buffer-service': 'Buffer'
      };

      const displayName = displayNames[serviceName] || serviceName;
      this.showToast('error', `Failed to restart ${displayName}: ${error.message}`);
      throw error;
    }
  }

  async getSystemStatus() {
    return this.fetchData('/system/status');
  }

  async getConfig() {
    return this.fetchData('/config');
  }

  async saveConfig(config) {
    return this.postData('/config', config);
  }

  async getFlows() {
    return this.fetchData('/flows');
  }

  async getSyslog() {
    return this.fetchData('/syslog');
  }

  async getSNMP() {
    return this.fetchData('/snmp');
  }

  async getMetrics() {
    return this.fetchData('/metrics');
  }

  async getBufferStatus() {
    return this.fetchData('/buffer/status');
  }

  showToast(type, message, ttl = 5000) {
    const event = new CustomEvent('toast', {
      detail: { type, message, ttl }
    });
    window.dispatchEvent(event);
  }
}

// Export singleton instance
export default new ApiService();
