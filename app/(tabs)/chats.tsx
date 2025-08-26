import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  SafeAreaView,
  Image,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Plus } from 'lucide-react-native';
import { useTheme } from '../../contexts/ThemeContext';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { useRouter, useFocusEffect } from 'expo-router';
import { formatDistanceToNowStrict } from 'date-fns';
import { ar } from 'date-fns/locale';

export default function ChatsScreen() {
  const { theme } = useTheme();
  const { user } = useAuth();
  const router = useRouter();
  
  const [conversations, setConversations] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const fetchConversations = async () => {
    if (!user) return;
    try {
      const { data, error } = await supabase.rpc('get_user_conversations');
      if (error) throw error;
      setConversations(data || []);
    } catch (error: any) {
      console.error('Error fetching conversations:', error.message);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useFocusEffect(
    useCallback(() => {
      fetchConversations();
    }, [user])
  );

  useEffect(() => {
    if (!user) return;

    const channel = supabase
      .channel('public:messages')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'messages' },
        (payload) => {
          // A new message was inserted, refetch conversations to update last message
          fetchConversations();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [user]);

  const onRefresh = () => {
    setRefreshing(true);
    fetchConversations();
  };

  const formatTime = (date: string) => {
    return formatDistanceToNowStrict(new Date(date), { addSuffix: true, locale: ar });
  };

  const renderChatItem = ({ item }: { item: any }) => (
    <TouchableOpacity 
      style={[styles.chatItem, { backgroundColor: theme.card }]}
      onPress={() => router.push(`/chat/${item.conversation_id}`)}
    >
      <View style={styles.avatarContainer}>
        <Image 
          source={{ uri: item.avatar_url || 'https://i.pravatar.cc/150' }} 
          style={styles.avatar} 
        />
      </View>
      
      <View style={styles.chatContent}>
        <View style={styles.chatHeader}>
          <Text style={[styles.chatName, { color: theme.text }]} numberOfLines={1}>
            {item.full_name || item.username}
          </Text>
          <Text style={[styles.chatTime, { color: theme.textSecondary }]}>
            {item.last_message_created_at ? formatTime(item.last_message_created_at) : ''}
          </Text>
        </View>
        
        <View style={styles.chatFooter}>
          <Text 
            style={[styles.lastMessage, { color: theme.textSecondary }]} 
            numberOfLines={1}
          >
            {item.last_message_content || 'لا توجد رسائل بعد'}
          </Text>
        </View>
      </View>
    </TouchableOpacity>
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
          <Text style={[styles.headerTitle, { color: theme.text }]}>المحادثات</Text>
          <TouchableOpacity 
            style={[styles.addButton, { backgroundColor: theme.primary }]}
            onPress={() => router.push('/modals/add-chat')}
          >
            <Plus size={24} color="white" />
          </TouchableOpacity>
        </View>

        {conversations.length === 0 ? (
          <View style={styles.emptyContainer}>
            <Text style={[styles.emptyText, { color: theme.textSecondary }]}>
              لا توجد محادثات.
            </Text>
            <Text style={[styles.emptySubText, { color: theme.textSecondary }]}>
              انقر على زر + لبدء محادثة جديدة.
            </Text>
          </View>
        ) : (
          <FlatList
            data={conversations}
            keyExtractor={(item) => item.conversation_id}
            renderItem={renderChatItem}
            showsVerticalScrollIndicator={false}
            contentContainerStyle={styles.listContainer}
            refreshControl={
              <RefreshControl
                refreshing={refreshing}
                onRefresh={onRefresh}
                colors={[theme.primary]}
                tintColor={theme.primary}
              />
            }
          />
        )}
      </LinearGradient>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  gradient: { flex: 1 },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 16,
  },
  headerTitle: { fontSize: 32, fontWeight: 'bold' },
  addButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 8,
    elevation: 4,
  },
  listContainer: { paddingHorizontal: 20 },
  chatItem: {
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
  avatarContainer: { marginRight: 16 },
  avatar: { width: 52, height: 52, borderRadius: 26 },
  chatContent: { flex: 1 },
  chatHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 4,
  },
  chatName: { fontSize: 16, fontWeight: '600', flex: 1 },
  chatTime: { fontSize: 14 },
  chatFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  lastMessage: { fontSize: 14, flex: 1 },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    fontSize: 18,
    fontWeight: '600',
  },
  emptySubText: {
    fontSize: 14,
    marginTop: 8,
  },
});
