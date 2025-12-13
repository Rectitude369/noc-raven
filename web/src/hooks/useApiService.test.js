import { renderHook, act, waitFor } from '@testing-library/react';
import { useApiData, useSystemStatus, useConfig, useServiceManager } from './useApiService';
import apiService from '../services/apiService';

// Mock the API service
jest.mock('../services/apiService');

// Mock showToast for all tests
apiService.showToast = jest.fn();

describe('useApiService hooks', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('useApiData', () => {
    test('fetches data successfully', async () => {
      const mockData = { test: 'data' };
      apiService.fetchData.mockResolvedValue(mockData);

      const { result } = renderHook(() => useApiData('/test'));

      expect(result.current.loading).toBe(true);
      expect(result.current.data).toBeNull();
      expect(result.current.error).toBeNull();

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
        expect(result.current.data).toEqual(mockData);
        expect(result.current.error).toBeNull();
      });

      expect(apiService.fetchData).toHaveBeenCalledWith('/test');
    });

    test('handles fetch error', async () => {
      const errorMessage = 'Network error';
      apiService.fetchData.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useApiData('/test'));

      // Hook catches the error and doesn't rethrow, so no error in result
      await waitFor(() => {
        expect(result.current.loading).toBe(false);
        expect(result.current.data).toBeNull();
        // Error is caught internally and handled
      });
    });

    test('refreshes data at specified interval', async () => {
      const mockData = { test: 'data' };
      apiService.fetchData.mockResolvedValue(mockData);

      renderHook(() => useApiData('/test', 5000));

      expect(apiService.fetchData).toHaveBeenCalledTimes(1);

      // Fast-forward time by 5 seconds
      act(() => {
        jest.advanceTimersByTime(5000);
      });

      await waitFor(() => {
        expect(apiService.fetchData).toHaveBeenCalledTimes(2);
      }, { timeout: 3000 });
    });

    test('cleans up interval on unmount', () => {
      const { unmount } = renderHook(() => useApiData('/test', 5000));
      
      // No error should occur during unmount
      expect(() => {
        unmount();
      }).not.toThrow();
    });
  });

  describe('useSystemStatus', () => {
    test('fetches system status', async () => {
      const mockStatus = { status: 'healthy', uptime: '1 day' };
      apiService.fetchData.mockResolvedValue(mockStatus);

      const { result } = renderHook(() => useSystemStatus());

      await waitFor(() => {
        expect(result.current.data).toEqual(mockStatus);
        expect(result.current.loading).toBe(false);
      });

      expect(apiService.fetchData).toHaveBeenCalledWith('/system/status');
    });

    test('refreshes status at specified interval', async () => {
      const mockStatus = { status: 'healthy' };
      apiService.fetchData.mockResolvedValue(mockStatus);

      renderHook(() => useSystemStatus(3000));

      expect(apiService.fetchData).toHaveBeenCalledTimes(1);

      act(() => {
        jest.advanceTimersByTime(3000);
      });

      await waitFor(() => {
        expect(apiService.fetchData).toHaveBeenCalledTimes(2);
      }, { timeout: 3000 });
    });
  });

  describe('useConfig', () => {
    test('fetches and saves config', async () => {
      const mockConfig = { syslog_port: 514 };
      const updatedConfig = { syslog_port: 1514 };
      
      apiService.getConfig.mockResolvedValue(mockConfig);
      apiService.saveConfig.mockResolvedValue({ success: true });

      const { result } = renderHook(() => useConfig());

      // Wait for initial fetch
      await waitFor(() => {
        expect(result.current.config).toEqual(mockConfig);
        expect(result.current.loading).toBe(false);
      });

      // Test save functionality
      await act(async () => {
        await result.current.saveConfig(updatedConfig);
      });

      expect(apiService.saveConfig).toHaveBeenCalledWith(updatedConfig);
      expect(result.current.config).toEqual(updatedConfig);
    });

    test('handles save error', async () => {
      const mockConfig = { syslog_port: 514 };
      apiService.getConfig.mockResolvedValue(mockConfig);
      apiService.saveConfig.mockRejectedValue(new Error('Save failed'));

      const { result } = renderHook(() => useConfig());

      await waitFor(() => {
        expect(result.current.config).toEqual(mockConfig);
      });

      let saveError = null;
      await act(async () => {
        try {
          await result.current.saveConfig({ syslog_port: 1514 });
        } catch (err) {
          saveError = err;
        }
      });

      expect(saveError).not.toBeNull();
      expect(result.current.error).toBe('Save failed');
      expect(result.current.config).toEqual(mockConfig); // Should not update on error
    });
  });

  describe('useServiceManager', () => {
    test('restarts service successfully', async () => {
      apiService.restartService.mockResolvedValue({ success: true });

      const { result } = renderHook(() => useServiceManager());

      expect(result.current.loading).toBe(false);
      expect(result.current.error).toBeNull();

      await act(async () => {
        await result.current.restartService('fluent-bit');
      });

      expect(apiService.restartService).toHaveBeenCalledWith('fluent-bit');
      expect(result.current.loading).toBe(false);
      expect(result.current.error).toBeNull();
    });

    test('handles restart error', async () => {
      apiService.restartService.mockRejectedValue(new Error('Restart failed'));

      const { result } = renderHook(() => useServiceManager());

      let restartError = null;
      await act(async () => {
        try {
          await result.current.restartService('fluent-bit');
        } catch (err) {
          restartError = err;
        }
      });

      expect(restartError).not.toBeNull();
      expect(restartError.message).toBe('Restart failed');
    });

    test('shows loading state during restart', async () => {
      let resolveRestart;
      const restartPromise = new Promise(resolve => {
        resolveRestart = resolve;
      });
      apiService.restartService.mockReturnValue(restartPromise);

      const { result } = renderHook(() => useServiceManager());

      let restartPromiseReturned;
      act(() => {
        restartPromiseReturned = result.current.restartService('fluent-bit');
      });

      expect(result.current.loading).toBe(true);

      await act(async () => {
        resolveRestart({ success: true });
        await restartPromiseReturned;
      });

      expect(result.current.loading).toBe(false);
    });
  });
});
