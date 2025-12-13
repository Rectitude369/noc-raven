import apiService from './apiService';

// Mock fetch globally
global.fetch = jest.fn();

// Mock window.dispatchEvent
const mockDispatchEvent = jest.fn();
window.dispatchEvent = mockDispatchEvent;

describe('apiService', () => {
  beforeEach(() => {
    fetch.mockClear();
    mockDispatchEvent.mockClear();
  });

  describe('fetchData', () => {
    test('successfully fetches data', async () => {
      const mockData = { test: 'data' };
      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockData
      });

      const result = await apiService.fetchData('/test');
      
      expect(fetch).toHaveBeenCalledWith('/api/test');
      expect(result).toEqual(mockData);
      // Clear mocks after successful calls to isolate error tests
      mockDispatchEvent.mockClear();
    });

    test('handles fetch error', async () => {
      fetch.mockRejectedValueOnce(new Error('Network error'));

      const result = await apiService.fetchData('/test');
      
      expect(result).toBeNull();
      expect(mockDispatchEvent).toHaveBeenCalled();
      const eventCall = mockDispatchEvent.mock.calls[0][0];
      expect(eventCall.type).toBe('toast');
      expect(eventCall.detail.type).toBe('error');
      expect(eventCall.detail.message).toContain('Network error');
    });

    test('handles HTTP error response', async () => {
      fetch.mockResolvedValueOnce({
        ok: false,
        status: 404,
        statusText: 'Not Found'
      });

      const result = await apiService.fetchData('/test');
      
      expect(result).toBeNull();
      expect(mockDispatchEvent).toHaveBeenCalled();
      const eventCall = mockDispatchEvent.mock.calls[0][0];
      expect(eventCall.type).toBe('toast');
      expect(eventCall.detail.type).toBe('error');
      expect(eventCall.detail.message).toContain('HTTP 404');
    });
  });

  describe('postData', () => {
    test('successfully posts data', async () => {
      const mockResponse = { success: true };
      const postData = { key: 'value' };
      
      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockResponse
      });

      const result = await apiService.postData('/test', postData);
      
      expect(fetch).toHaveBeenCalledWith('/api/test', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(postData)
      });
      expect(result).toEqual(mockResponse);
      // Clear mocks after this test to isolate other tests
      mockDispatchEvent.mockClear();
    });

    test('handles post error', async () => {
      fetch.mockRejectedValueOnce(new Error('Network error'));

      try {
        await apiService.postData('/test', {});
      } catch (err) {
        // Expected to throw
        expect(err.message).toBe('Network error');
      }
      
      expect(mockDispatchEvent).toHaveBeenCalled();
      const eventCall = mockDispatchEvent.mock.calls[0][0];
      expect(eventCall.type).toBe('toast');
      expect(eventCall.detail.type).toBe('error');
    });
  });

  describe('restartService', () => {
    beforeEach(() => {
      mockDispatchEvent.mockClear();
    });

    test('successfully restarts service', async () => {
      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ message: 'Service restarted' })
      });

      const result = await apiService.restartService('fluent-bit');
      
      // Check that fetch was called with the correct endpoint and method
      expect(fetch).toHaveBeenCalledWith(
        '/api/services/fluent-bit/restart',
        expect.objectContaining({
          method: 'POST'
        })
      );
      expect(result).toEqual({ message: 'Service restarted' });
      expect(mockDispatchEvent).toHaveBeenCalled();
      const eventCall = mockDispatchEvent.mock.calls[0][0];
      expect(eventCall.type).toBe('toast');
      expect(eventCall.detail.type).toBe('success');
      expect(eventCall.detail.message).toContain('restarted');
    });

    test('handles restart failure', async () => {
      fetch.mockResolvedValueOnce({
        ok: false,
        status: 500,
        statusText: 'Internal Server Error'
      });

      try {
        await apiService.restartService('fluent-bit');
      } catch (err) {
        // Expected to throw
        expect(err.message).toContain('HTTP 500');
      }
      
      expect(mockDispatchEvent).toHaveBeenCalled();
      const eventCall = mockDispatchEvent.mock.calls[mockDispatchEvent.mock.calls.length - 1][0];
      expect(eventCall.type).toBe('toast');
      expect(eventCall.detail.type).toBe('error');
    });
  });

  describe('getSystemStatus', () => {
    test('successfully gets system status', async () => {
      const mockStatus = { status: 'healthy', uptime: '1 day' };
      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockStatus
      });

      const result = await apiService.getSystemStatus();
      
      expect(fetch).toHaveBeenCalledWith('/api/system/status');
      expect(result).toEqual(mockStatus);
      mockDispatchEvent.mockClear();
    });
  });

  describe('getConfig', () => {
    test('successfully gets config', async () => {
      const mockConfig = { syslog_port: 514 };
      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockConfig
      });

      const result = await apiService.getConfig();
      
      expect(fetch).toHaveBeenCalledWith('/api/config');
      expect(result).toEqual(mockConfig);
      mockDispatchEvent.mockClear();
    });
  });

  describe('saveConfig', () => {
    beforeEach(() => {
      mockDispatchEvent.mockClear();
    });

    test('successfully saves config', async () => {
      const config = { syslog_port: 1514 };
      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ success: true })
      });

      const result = await apiService.saveConfig(config);
      
      expect(fetch).toHaveBeenCalledWith('/api/config', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(config)
      });
      expect(result).toEqual({ success: true });
      // saveConfig should also call postData which may trigger showToast
      // Check that fetch was called at least
      expect(fetch).toHaveBeenCalled();
    });
  });
});
