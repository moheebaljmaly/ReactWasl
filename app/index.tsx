import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  Alert,
  Dimensions,
  Platform,
  ScrollView,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import { MessageCircle, Lock, Users, Settings, Moon, Sun } from 'lucide-react-native';
import { useTheme } from '../contexts/ThemeContext';
import { useAuth } from '../contexts/AuthContext';
import { Button } from '../components/Button';
import { Input } from '../components/Input';

const { width, height } = Dimensions.get('window');

export default function WelcomeScreen() {
  const router = useRouter();
  const { isDarkMode, theme, toggleTheme } = useTheme();
  const { signIn, signUp, user, loading } = useAuth();
  
  const [isLogin, setIsLogin] = useState(true);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [username, setUsername] = useState('');
  const [authLoading, setAuthLoading] = useState(false);

  useEffect(() => {
    if (user) {
      router.replace('/(tabs)/chats');
    }
  }, [user]);

  const handleAuth = async () => {
    if (!email || !password) {
      Alert.alert('خطأ', 'يرجى ملء جميع الحقول');
      return;
    }

    if (!isLogin && (!fullName || !username)) {
      Alert.alert('خطأ', 'يرجى إدخال الاسم الكامل واسم المستخدم');
      return;
    }

    setAuthLoading(true);
    try {
      if (isLogin) {
        await signIn(email, password);
      } else {
        await signUp(email, password, fullName, username);
        Alert.alert('تم بنجاح!', 'تم إنشاء الحساب بنجاح. يمكنك الآن تسجيل الدخول.');
        setIsLogin(true); // Switch to login tab after successful signup
      }
    } catch (error: any) {
      Alert.alert('خطأ في المصادقة', error.message);
    } finally {
      setAuthLoading(false);
    }
  };

  const handleGuestAccess = () => {
    router.push('/(tabs)/chats');
  };

  if (loading) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
        <View style={styles.loadingContainer}>
          <Text style={[styles.loadingText, { color: theme.text }]}>جارٍ التحميل...</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
      <LinearGradient
        colors={isDarkMode ? ['#000000', '#1c1c1e', '#2c2c2e'] : ['#ffffff', '#f8f9fa', '#e9ecef']}
        style={styles.gradient}
      >
        <ScrollView showsVerticalScrollIndicator={false}>
          {/* Header */}
          <View style={styles.header}>
            <TouchableOpacity onPress={toggleTheme} style={[styles.themeButton, { backgroundColor: theme.surface }]}>
              {isDarkMode ? (
                <Sun size={24} color={theme.text} />
              ) : (
                <Moon size={24} color={theme.text} />
              )}
            </TouchableOpacity>
          </View>

          {/* Logo and Title */}
          <View style={styles.logoContainer}>
            <View style={[styles.logoCircle, { backgroundColor: theme.primary }]}>
              <MessageCircle size={48} color="white" />
            </View>
            <Text style={[styles.appTitle, { color: theme.text }]}>وصـل</Text>
            <Text style={[styles.appSubtitle, { color: theme.textSecondary }]}>
              تطبيق الدردشة الذكي
            </Text>
          </View>

          {/* Features */}
          <View style={styles.featuresContainer}>
            <View style={styles.featuresRow}>
              <View style={[styles.featureCard, { backgroundColor: theme.surface }]}>
                <MessageCircle size={24} color={theme.primary} />
                <Text style={[styles.featureText, { color: theme.text }]}>دردشة سريعة</Text>
              </View>
              <View style={[styles.featureCard, { backgroundColor: theme.surface }]}>
                <Lock size={24} color={theme.accent} />
                <Text style={[styles.featureText, { color: theme.text }]}>آمن وخاص</Text>
              </View>
            </View>
            <View style={styles.featuresRow}>
              <View style={[styles.featureCard, { backgroundColor: theme.surface }]}>
                <Users size={24} color={theme.secondary} />
                <Text style={[styles.featureText, { color: theme.text }]}>جماعي</Text>
              </View>
              <View style={[styles.featureCard, { backgroundColor: theme.surface }]}>
                <Settings size={24} color={theme.warning} />
                <Text style={[styles.featureText, { color: theme.text }]}>سهل الاستخدام</Text>
              </View>
            </View>
          </View>

          {/* Auth Form */}
          <View style={[styles.formContainer, { backgroundColor: theme.card }]}>
            <View style={styles.tabContainer}>
              <TouchableOpacity
                style={[styles.tab, isLogin && { backgroundColor: theme.primary }]}
                onPress={() => setIsLogin(true)}
              >
                <Text style={[styles.tabText, { color: isLogin ? 'white' : theme.textSecondary }]}>
                  تسجيل دخول
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.tab, !isLogin && { backgroundColor: theme.primary }]}
                onPress={() => setIsLogin(false)}
              >
                <Text style={[styles.tabText, { color: !isLogin ? 'white' : theme.textSecondary }]}>
                  حساب جديد
                </Text>
              </TouchableOpacity>
            </View>

            {!isLogin && (
              <>
                <Input
                  placeholder="الاسم الكامل"
                  value={fullName}
                  onChangeText={setFullName}
                  textAlign="right"
                />
                <Input
                  placeholder="اسم المستخدم (فريد)"
                  value={username}
                  onChangeText={setUsername}
                  autoCapitalize="none"
                  textAlign="right"
                />
              </>
            )}

            <Input
              placeholder="البريد الإلكتروني"
              value={email}
              onChangeText={setEmail}
              keyboardType="email-address"
              autoCapitalize="none"
              textAlign="right"
            />

            <Input
              placeholder="كلمة المرور"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              textAlign="right"
            />

            <Button
              title={authLoading ? 'جارٍ التحميل...' : isLogin ? 'تسجيل الدخول' : 'إنشاء حساب'}
              onPress={handleAuth}
              disabled={authLoading}
              style={styles.authButton}
            />
          </View>

          {/* Skip Button */}
          <Button
            title="تخطي والدخول كضيف"
            onPress={handleGuestAccess}
            variant="outline"
            style={styles.skipButton}
          />
        </ScrollView>
      </LinearGradient>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  gradient: {
    flex: 1,
    paddingHorizontal: 20,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    fontSize: 18,
    fontWeight: '600',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    alignItems: 'center',
    paddingTop: Platform.OS === 'ios' ? 10 : 40,
    marginBottom: 20,
  },
  themeButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 3,
  },
  logoContainer: {
    alignItems: 'center',
    marginBottom: 40,
  },
  logoCircle: {
    width: 100,
    height: 100,
    borderRadius: 50,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 12,
    elevation: 8,
  },
  appTitle: {
    fontSize: 36,
    fontWeight: 'bold',
    marginBottom: 8,
    textAlign: 'center',
  },
  appSubtitle: {
    fontSize: 16,
    textAlign: 'center',
  },
  featuresContainer: {
    marginBottom: 40,
  },
  featuresRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 16,
  },
  featureCard: {
    flex: 1,
    alignItems: 'center',
    padding: 20,
    marginHorizontal: 8,
    borderRadius: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 3,
  },
  featureText: {
    fontSize: 14,
    fontWeight: '600',
    marginTop: 8,
    textAlign: 'center',
  },
  formContainer: {
    borderRadius: 20,
    padding: 24,
    marginBottom: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 8,
  },
  tabContainer: {
    flexDirection: 'row',
    marginBottom: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.05)',
    padding: 4,
  },
  tab: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  tabText: {
    fontSize: 16,
    fontWeight: '600',
  },
  authButton: {
    marginTop: 8,
  },
  skipButton: {
    marginBottom: 20,
  },
});
