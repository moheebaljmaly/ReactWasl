import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  FlatList,
  TouchableOpacity,
  Image,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { useTheme } from '../../contexts/ThemeContext';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { useRouter } from 'expo-router';
import { Search } from 'lucide-react-native';

export default function AddChatModal() {
  const { theme } = useTheme();
  const { user } = useAuth();
  const router = useRouter();

  const [searchQuery, setSearchQuery] = useState('');
  const [results, setResults] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);

  const handleSearch = async () => {
    if (!searchQuery.trim() || !user) return;
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .or(`username.ilike.%${searchQuery}%,email.ilike.%${searchQuery}%`)
        .neq('id', user.id)
        .limit(10);
      
      if (error) throw error;
      setResults(data || []);
    } catch (error: any) {
      Alert.alert('خطأ في البحث', error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleStartChat = async (contact: any) => {
    if (!user) return;
    try {
      const { data, error } = await supabase.rpc('create_private_conversation', {
        other_user_id: contact.id
      });
      if (error) throw error;
      router.back(); // Close modal
      router.push(`/chat/${data}`);
    } catch (error: any) {
      Alert.alert('خطأ', 'فشل في بدء المحادثة.');
      console.error(error.message);
    }
  };

  const renderItem = ({ item }: { item: any }) => (
    <TouchableOpacity 
      style={[styles.resultItem, { backgroundColor: theme.surface }]}
      onPress={() => handleStartChat(item)}
    >
      <Image source={{ uri: item.avatar_url }} style={styles.avatar} />
      <View>
        <Text style={[styles.fullName, { color: theme.text }]}>{item.full_name}</Text>
        <Text style={[styles.username, { color: theme.textSecondary }]}>@{item.username}</Text>
      </View>
    </TouchableOpacity>
  );

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <View style={[styles.searchContainer, { backgroundColor: theme.surface }]}>
        <TextInput
          style={[styles.input, { color: theme.text }]}
          placeholder="ابحث بالاسم أو البريد الإلكتروني..."
          placeholderTextColor={theme.textSecondary}
          value={searchQuery}
          onChangeText={setSearchQuery}
          onSubmitEditing={handleSearch}
          returnKeyType="search"
          textAlign="right"
        />
        <TouchableOpacity onPress={handleSearch}>
          <Search size={24} color={theme.primary} />
        </TouchableOpacity>
      </View>

      {loading ? (
        <ActivityIndicator size="large" color={theme.primary} style={{ marginTop: 20 }} />
      ) : (
        <FlatList
          data={results}
          keyExtractor={(item) => item.id}
          renderItem={renderItem}
          ListEmptyComponent={() => (
            <View style={styles.emptyContainer}>
              <Text style={{ color: theme.textSecondary }}>
                {searchQuery ? 'لم يتم العثور على نتائج' : 'أدخل اسم مستخدم أو بريد إلكتروني للبحث'}
              </Text>
            </View>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 20,
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 12,
    paddingHorizontal: 16,
    marginBottom: 20,
  },
  input: {
    flex: 1,
    height: 50,
    fontSize: 16,
  },
  resultItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    borderRadius: 8,
    marginBottom: 8,
  },
  avatar: {
    width: 50,
    height: 50,
    borderRadius: 25,
    marginRight: 12,
  },
  fullName: {
    fontSize: 16,
    fontWeight: 'bold',
  },
  username: {
    fontSize: 14,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 50,
  },
});
