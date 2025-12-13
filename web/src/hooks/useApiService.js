import { useState, useEffect, useCallback } from 'react';
import apiService from '../services/apiService';

/**
 * Custom hook for API data fetching with loading states
 */
export const useApiData = (endpoint, interval = null) => {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await apiService.fetchData(endpoint);
      setData(result);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [endpoint]);

  useEffect(() => {
    fetchData();
    
    if (interval) {
      const intervalId = setInterval(fetchData, interval);
      return () => clearInterval(intervalId);
    }
  }, [fetchData, interval]);

  return { data, loading, error, refetch: fetchData };
};

/**
 * Custom hook for system status with real-time updates
 */
export const useSystemStatus = (updateInterval = 5000) => {
  return useApiData('/system/status', updateInterval);
};

/**
 * Custom hook for configuration management
 */
export const useConfig = () => {
  const [config, setConfig] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const loadConfig = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await apiService.getConfig();
      setConfig(result);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  const saveConfig = useCallback(async (newConfig) => {
    try {
      setLoading(true);
      setError(null);
      await apiService.saveConfig(newConfig);
      setConfig(newConfig);
      apiService.showToast('success', 'Configuration saved successfully');
    } catch (err) {
      setError(err.message);
      apiService.showToast('error', `Failed to save configuration: ${err.message}`);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

  return { config, loading, error, saveConfig, reloadConfig: loadConfig };
};

/**
 * Custom hook for service management
 */
export const useServiceManager = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const restartService = useCallback(async (serviceName) => {
    try {
      setLoading(true);
      setError(null);
      await apiService.restartService(serviceName);
    } catch (err) {
      setError(err.message);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { restartService, loading, error };
};
