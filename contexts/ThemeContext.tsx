import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

export const lightTheme = {
  background: '#ffffff',
  surface: '#f8f9fa',
  primary: '#007AFF',
  secondary: '#5856D6',
  text: '#1d1d1d',
  textSecondary: '#8e8e93',
  border: '#e5e5ea',
  card: '#ffffff',
  accent: '#34C759',
  error: '#FF3B30',
  warning: '#FF9500',
};

export const darkTheme = {
  background: '#000000',
  surface: '#1c1c1e',
  primary: '#007AFF',
  secondary: '#5856D6',
  text: '#ffffff',
  textSecondary: '#8e8e93',
  border: '#38383a',
  card: '#2c2c2e',
  accent: '#34C759',
  error: '#FF453A',
  warning: '#FF9F0A',
};

interface ThemeContextType {
  isDarkMode: boolean;
  theme: typeof darkTheme;
  toggleTheme: () => Promise<void>;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

interface ThemeProviderProps {
  children: ReactNode;
}

export const ThemeProvider: React.FC<ThemeProviderProps> = ({ children }) => {
  const [isDarkMode, setIsDarkMode] = useState(true);

  useEffect(() => {
    loadThemePreference();
  }, []);

  const loadThemePreference = async () => {
    try {
      const savedTheme = await AsyncStorage.getItem('@theme');
      if (savedTheme !== null) {
        setIsDarkMode(savedTheme === 'dark');
      }
    } catch (error) {
      console.log('Error loading theme:', error);
    }
  };

  const toggleTheme = async () => {
    const newTheme = !isDarkMode;
    setIsDarkMode(newTheme);
    await AsyncStorage.setItem('@theme', newTheme ? 'dark' : 'light');
  };

  const theme = isDarkMode ? darkTheme : lightTheme;

  return (
    <ThemeContext.Provider value={{ isDarkMode, theme, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
};

export const useTheme = () => {
  const context = useContext(ThemeContext);
  if (context === undefined) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
};
