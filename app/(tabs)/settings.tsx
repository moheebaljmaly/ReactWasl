import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  SafeAreaView,
  Image,
  Alert,
  Switch,
  ScrollView,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { 
  User, 
  Moon, 
  Sun, 
  Bell, 
  Lock, 
  HelpCircle, 
  LogOut, 
  Edit3,
  ChevronRight,
} from 'lucide-react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useRouter } from 'expo-router';
import { useTheme } from '../../contexts/ThemeContext';
import { useAuth } from '../../contexts/AuthContext';

export default function SettingsScreen() {
  const router = useRouter();
  const { isDarkMode, theme, toggleTheme } = useTheme();
  const { user, profile, signOut } = useAuth();
  const [notificationsEnabled, setNotificationsEnabled] = useState(true);

  const handleLogout = async () => {
    Alert.alert(
      'تسجيل الخروج',
      'هل أنت متأكد من تسجيل الخروج؟',
      [
        { text: 'إلغاء', style: 'cancel' },
        {
          text: 'خروج',
          style: 'destructive',
          onPress: async () => {
            await signOut();
            router.replace('/');
          },
        },
      ]
    );
  };

  const SettingsItem = ({ 
    icon, 
    title, 
    onPress, 
    rightElement, 
    color = theme.text,
    showChevron = true 
  }: any) => (
    <TouchableOpacity 
      style={[styles.settingsItem, { backgroundColor: theme.card }]} 
      onPress={onPress}
      disabled={!onPress}
    >
      <View style={styles.settingsLeft}>
        <View style={[styles.iconContainer, { backgroundColor: theme.surface }]}>
          {icon}
        </View>
        <Text style={[styles.settingsTitle, { color }]}>{title}</Text>
      </View>
      
      <View style={styles.settingsRight}>
        {rightElement}
        {onPress && showChevron && (
          <ChevronRight size={20} color={theme.textSecondary} />
        )}
      </View>
    </TouchableOpacity>
  );

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
      <LinearGradient
        colors={[theme.background, theme.surface]}
        style={styles.gradient}
      >
        <ScrollView showsVerticalScrollIndicator={false}>
          <View style={styles.header}>
            <Text style={[styles.headerTitle, { color: theme.text }]}>الإعدادات</Text>
          </View>

          {user && profile ? (
            <TouchableOpacity 
              style={[styles.profileSection, { backgroundColor: theme.card }]}
              onPress={() => router.push('/modals/edit-profile')}
            >
              <Image
                source={{ uri: profile.avatar_url || 'https://i.pravatar.cc/150' }}
                style={styles.profileImage}
              />
              <View style={styles.profileInfo}>
                <Text style={[styles.profileName, { color: theme.text }]}>
                  {profile.full_name}
                </Text>
                <Text style={[styles.profileEmail, { color: theme.textSecondary }]}>
                  @{profile.username}
                </Text>
              </View>
              <Edit3 size={20} color={theme.textSecondary} />
            </TouchableOpacity>
          ) : (
             <View style={[styles.profileSection, { backgroundColor: theme.card }]}>
                <View style={styles.profileImage}/>
                <View style={styles.profileInfo}>
                    <Text style={[styles.profileName, { color: theme.text }]}>مستخدم ضيف</Text>
                    <Text style={[styles.profileEmail, { color: theme.textSecondary }]}>يرجى تسجيل الدخول</Text>
                </View>
            </View>
          )}

          <View style={styles.section}>
            <SettingsItem
              icon={isDarkMode ? <Sun size={20} color={theme.warning} /> : <Moon size={20} color={theme.primary} />}
              title="الوضع الداكن"
              rightElement={
                <Switch
                  value={isDarkMode}
                  onValueChange={toggleTheme}
                  trackColor={{ false: theme.border, true: theme.primary }}
                  thumbColor="white"
                />
              }
              showChevron={false}
            />

            <SettingsItem
              icon={<Bell size={20} color={theme.accent} />}
              title="الإشعارات"
              rightElement={
                <Switch
                  value={notificationsEnabled}
                  onValueChange={() => setNotificationsEnabled(v => !v)}
                  trackColor={{ false: theme.border, true: theme.primary }}
                  thumbColor="white"
                />
              }
              showChevron={false}
            />
          </View>

          <View style={styles.section}>
            <SettingsItem
              icon={<Lock size={20} color={theme.primary} />}
              title="الحساب والخصوصية"
              onPress={() => Alert.alert('قريباً', 'هذه الميزة ستكون متاحة قريباً')}
            />
            <SettingsItem
              icon={<HelpCircle size={20} color={theme.secondary} />}
              title="المساعدة والدعم"
              onPress={() => Alert.alert('قريباً', 'هذه الميزة ستكون متاحة قريباً')}
            />
          </View>

          {user && (
            <View style={styles.section}>
              <SettingsItem
                icon={<LogOut size={20} color={theme.error} />}
                title="تسجيل الخروج"
                color={theme.error}
                onPress={handleLogout}
                showChevron={false}
              />
            </View>
          )}

          <View style={styles.footer}>
            <Text style={[styles.footerText, { color: theme.textSecondary }]}>
              تطبيق وصل © 2025
            </Text>
          </View>
        </ScrollView>
      </LinearGradient>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  gradient: { flex: 1 },
  header: {
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 16,
  },
  headerTitle: { fontSize: 32, fontWeight: 'bold' },
  profileSection: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 20,
    marginBottom: 24,
    padding: 20,
    borderRadius: 16,
  },
  profileImage: {
    width: 60,
    height: 60,
    borderRadius: 30,
    marginRight: 16,
    backgroundColor: '#ccc'
  },
  profileInfo: { flex: 1 },
  profileName: { fontSize: 18, fontWeight: 'bold', marginBottom: 4 },
  profileEmail: { fontSize: 14 },
  section: {
    marginBottom: 16,
    marginHorizontal: 20,
    backgroundColor: '#f000',
    borderRadius: 16,
    overflow: 'hidden',
  },
  settingsItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 16,
  },
  settingsLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  iconContainer: {
    width: 36,
    height: 36,
    borderRadius: 18,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  settingsTitle: { fontSize: 16, fontWeight: '600' },
  settingsRight: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  footer: { alignItems: 'center', paddingVertical: 24 },
  footerText: { fontSize: 14 },
});
