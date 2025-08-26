import React from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useFrameworkReady } from '../hooks/useFrameworkReady';
import { ThemeProvider } from '../contexts/ThemeContext';
import { AuthProvider } from '../contexts/AuthContext';

export default function RootLayout() {
  useFrameworkReady();

  return (
    <ThemeProvider>
      <AuthProvider>
        <Stack screenOptions={{ headerShown: false }}>
          <Stack.Screen name="index" />
          <Stack.Screen name="(tabs)" />
          <Stack.Screen 
            name="chat/[id]" 
            options={{ 
              headerShown: true,
              title: 'المحادثة',
              presentation: 'card'
            }} 
          />
          <Stack.Screen 
            name="modals/add-chat" 
            options={{ 
              presentation: 'modal', 
              headerShown: true, 
              title: 'بدء محادثة جديدة' 
            }} 
          />
           <Stack.Screen 
            name="modals/edit-profile" 
            options={{ 
              presentation: 'modal', 
              headerShown: true, 
              title: 'تعديل الملف الشخصي' 
            }} 
          />
          <Stack.Screen name="+not-found" />
        </Stack>
        <StatusBar style="auto" />
      </AuthProvider>
    </ThemeProvider>
  );
}
