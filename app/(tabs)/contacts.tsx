import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  SafeAreaView,
  Image,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { MessageCircle } from 'lucide-react-native';
import { useTheme } from '../../contexts/ThemeContext';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { useRouter, useFocusEffect } from 'expo-router';

export default function ContactsScreen() {
  const { theme } = useTheme();
  const { user } = useAuth();
  const router = useRouter();
  const [contacts, setContacts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchContacts = async () => {
    if (!user) return;
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .neq('id', user.id); // Exclude current user
      if (error) throw error;
      setContacts(data || []);
    } catch (error: any) {
      Alert.alert('خطأ', 'فشل في جلب جهات الاتصال.');
      console.error(error.message);
    } finally {
      setLoading(false);
    }
  };

  useFocusEffect(
    useCallback(() => {
      fetchContacts();
    }, [user])
  );

  const handleStartChat = async (contact: any) => {
    if (!user) return;
    try {
      const { data, error } = await supabase.rpc('create_private_conversation', {
        other_user_id: contact.id
      });
      if (error) throw error;
      router.push(`/chat/${data}`);
    } catch (error: any) {
      Alert.alert('خطأ', 'فشل في بدء المحادثة.');
      console.error(error.message);
    }
  };

  const renderContactItem = ({ item }: { item: any }) => (
    <View style={[styles.contactItem, { backgroundColor: theme.card }]}>
      <Image 
        source={{ uri: item.avatar_url || 'https://i.pravatar.cc/150' }} 
        style={styles.avatar} 
      />
      <View style={styles.contactContent}>
        <Text style={[styles.contactName, { color: theme.text }]} numberOfLines={1}>
          {item.full_name}
        </Text>
        <Text style={[styles.contactStatus, { color: theme.textSecondary }]} numberOfLines={1}>
          @{item.username}
        </Text>
      </View>
      <TouchableOpacity 
        style={[styles.chatButton, { backgroundColor: theme.primary }]}
        onPress={() => handleStartChat(item)}
      >
        <MessageCircle size={18} color="white" />
      </TouchableOpacity>
    </View>
  );

  if (loading) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
        <ActivityIndicator size="large" color={theme.primary} style={{ flex: 1 }} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
      <LinearGradient
        colors={[theme.background, theme.surface]}
        style={styles.gradient}
      >
        <View style={styles.header}>
          <Text style={[styles.headerTitle, { color: theme.text }]}>جهات الاتصال</Text>
        </View>

        <FlatList
          data={contacts}
          keyExtractor={(item) => item.id}
          renderItem={renderContactItem}
          showsVerticalScrollIndicator={false}
          contentContainerStyle={styles.listContainer}
          ListEmptyComponent={() => (
            <View style={styles.emptyContainer}>
              <Text style={[styles.emptyText, { color: theme.textSecondary }]}>
                لا يوجد مستخدمون آخرون بعد.
              </Text>
            </View>
          )}
        />
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
  listContainer: { paddingHorizontal: 20 },
  contactItem: {
    flexDirection: 'row',
    padding: 16,
    marginBottom: 8,
    borderRadius: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
    alignItems: 'center',
  },
  avatar: { width: 52, height: 52, borderRadius: 26, marginRight: 16 },
  contactContent: { flex: 1 },
  contactName: { fontSize: 16, fontWeight: '600', marginBottom: 4 },
  contactStatus: { fontSize: 14 },
  chatButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingTop: 50,
  },
  emptyText: {
    fontSize: 16,
    fontWeight: '600',
  },
});
