import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, StyleSheet, ActivityIndicator, Image, Platform } from 'react-native';
import { useLocalSearchParams, useNavigation } from 'expo-router';
import { useTheme } from '../../contexts/ThemeContext';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { GiftedChat, IMessage, Bubble, Send, InputToolbar } from 'react-native-gifted-chat';
import { Send as SendIcon } from 'lucide-react-native';

export default function ChatScreen() {
  const { id: conversationId } = useLocalSearchParams() as { id: string };
  const navigation = useNavigation();
  const { theme } = useTheme();
  const { user, profile } = useAuth();
  
  const [messages, setMessages] = useState<IMessage[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchChatInfo = async () => {
      if (!conversationId || !user) return;

      const { data: partnerData, error: partnerError } = await supabase
        .rpc('get_conversation_partner', { p_conversation_id: conversationId });
      
      if (partnerError) {
        console.error('Error fetching partner:', partnerError);
      } else if (partnerData) {
        navigation.setOptions({ 
          headerStyle: { backgroundColor: theme.surface },
          headerTintColor: theme.text,
          headerTitle: () => (
            <View style={styles.headerTitleContainer}>
              <Image source={{ uri: partnerData.avatar_url || 'https://i.pravatar.cc/150' }} style={styles.headerAvatar} />
              <Text style={[styles.headerTitle, { color: theme.text }]}>
                {partnerData.full_name || partnerData.username}
              </Text>
            </View>
          ),
        });
      }
    };

    fetchChatInfo();
  }, [conversationId, user, navigation, theme]);

  useEffect(() => {
    const fetchMessages = async () => {
      if (!conversationId) return;
      setLoading(true);
      const { data, error } = await supabase
        .from('messages')
        .select(`id, content, created_at, user_id, profiles (username, avatar_url)`)
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: false });

      if (error) {
        console.error('Error fetching messages:', error);
      } else {
        const formattedMessages = data.map((msg: any) => ({
          _id: msg.id,
          text: msg.content,
          createdAt: new Date(msg.created_at),
          user: {
            _id: msg.user_id,
            name: msg.profiles.username,
            avatar: msg.profiles.avatar_url,
          },
        }));
        setMessages(formattedMessages);
      }
      setLoading(false);
    };

    fetchMessages();
  }, [conversationId]);

  useEffect(() => {
    if (!conversationId) return;

    const channel = supabase
      .channel(`chat_${conversationId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${conversationId}` },
        async (payload) => {
          const newMessage = payload.new;
          if (newMessage.user_id === user?.id) return; // Avoid duplicating own messages

          const { data: profileData } = await supabase.from('profiles').select('username, avatar_url').eq('id', newMessage.user_id).single();

          const formattedMessage: IMessage = {
            _id: newMessage.id,
            text: newMessage.content,
            createdAt: new Date(newMessage.created_at),
            user: { _id: newMessage.user_id, name: profileData?.username, avatar: profileData?.avatar_url },
          };
          setMessages(previousMessages => GiftedChat.append(previousMessages, [formattedMessage]));
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [conversationId, user]);

  const onSend = useCallback(async (messagesToSend: IMessage[] = []) => {
    if (!user || !conversationId) return;
    const { text } = messagesToSend[0];
    
    setMessages(previousMessages => GiftedChat.append(previousMessages, messagesToSend));

    const { error } = await supabase.from('messages').insert({
      content: text,
      user_id: user.id,
      conversation_id: conversationId,
    });

    if (error) {
      console.error('Error sending message:', error);
      // Optional: remove the message from UI if sending failed
    }
  }, [user, conversationId]);

  if (loading) {
    return (
      <View style={[styles.container, { backgroundColor: theme.background }]}>
        <ActivityIndicator size="large" color={theme.primary} />
      </View>
    );
  }

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <GiftedChat
        messages={messages}
        onSend={messages => onSend(messages)}
        user={{ _id: user!.id, name: profile?.username, avatar: profile?.avatar_url }}
        placeholder="اكتب رسالتك هنا..."
        messagesContainerStyle={{ backgroundColor: theme.background, paddingBottom: 10 }}
        textInputStyle={[styles.textInput, { color: theme.text }]}
        renderBubble={props => (
          <Bubble
            {...props}
            wrapperStyle={{
              right: { backgroundColor: theme.primary },
              left: { backgroundColor: theme.surface },
            }}
            textStyle={{
              right: { color: '#fff' },
              left: { color: theme.text },
            }}
          />
        )}
        renderSend={props => (
          <Send {...props} containerStyle={styles.sendContainer}>
            <SendIcon size={24} color={theme.primary} />
          </Send>
        )}
        renderInputToolbar={props => (
          <InputToolbar {...props} containerStyle={[styles.inputToolbar, { backgroundColor: theme.surface }]} />
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  headerTitleContainer: { flexDirection: 'row', alignItems: 'center' },
  headerAvatar: { width: 32, height: 32, borderRadius: 16, marginRight: 10 },
  headerTitle: { fontSize: 17, fontWeight: '600' },
  sendContainer: {
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 10,
    marginBottom: 5,
  },
  inputToolbar: {
    borderTopWidth: 1,
    borderTopColor: '#e0e0e0',
    padding: 5,
  },
  textInput: {
    textAlign: 'right',
    paddingTop: Platform.OS === 'ios' ? 8 : 0,
    paddingBottom: Platform.OS === 'ios' ? 8 : 0,
    lineHeight: 20,
  },
});
