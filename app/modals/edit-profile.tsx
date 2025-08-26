import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Image,
  TouchableOpacity,
  Alert,
  ScrollView,
  ActivityIndicator,
  Platform,
} from 'react-native';
import { useTheme } from '../../contexts/ThemeContext';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { useRouter } from 'expo-router';
import { Input } from '../../components/Input';
import { Button } from '../../components/Button';
import * as ImagePicker from 'expo-image-picker';
import { Edit3 } from 'lucide-react-native';

export default function EditProfileModal() {
  const { theme } = useTheme();
  const { user, profile, fetchProfile } = useAuth();
  const router = useRouter();

  const [fullName, setFullName] = useState('');
  const [username, setUsername] = useState('');
  const [status, setStatus] = useState('');
  const [avatarUrl, setAvatarUrl] = useState('');
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    if (profile) {
      setFullName(profile.full_name || '');
      setUsername(profile.username || '');
      setStatus(profile.status || '');
      setAvatarUrl(profile.avatar_url || '');
    }
  }, [profile]);

  const handleUpdateProfile = async () => {
    if (!user) return;
    setLoading(true);
    try {
      const updates = {
        id: user.id,
        full_name: fullName,
        username,
        status,
        avatar_url: avatarUrl,
        updated_at: new Date(),
      };
      const { error } = await supabase.from('profiles').upsert(updates);
      if (error) throw error;
      await fetchProfile(); // Refetch profile to update context
      Alert.alert('نجاح', 'تم تحديث الملف الشخصي بنجاح.');
      router.back();
    } catch (error: any) {
      Alert.alert('خطأ', error.message);
    } finally {
      setLoading(false);
    }
  };

  const pickImage = async () => {
    let result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [1, 1],
      quality: 1,
    });

    if (!result.canceled) {
      uploadAvatar(result.assets[0].uri);
    }
  };

  const uploadAvatar = async (uri: string) => {
    if (!user) return;
    setUploading(true);
    try {
      const response = await fetch(uri);
      const blob = await response.blob();
      const fileExt = uri.split('.').pop();
      const fileName = `${user.id}.${fileExt}`;
      const filePath = `${fileName}`;

      const { error: uploadError } = await supabase.storage
        .from('avatars')
        .upload(filePath, blob, {
          cacheControl: '3600',
          upsert: true,
        });

      if (uploadError) throw uploadError;

      const { data } = supabase.storage.from('avatars').getPublicUrl(filePath);
      setAvatarUrl(data.publicUrl);
    } catch (error: any) {
      Alert.alert('خطأ', 'فشل في رفع الصورة: ' + error.message);
    } finally {
      setUploading(false);
    }
  };

  return (
    <ScrollView 
      style={[styles.container, { backgroundColor: theme.background }]}
      contentContainerStyle={styles.contentContainer}
      keyboardShouldPersistTaps="handled"
    >
      <View style={styles.avatarContainer}>
        <Image source={{ uri: avatarUrl || 'https://i.pravatar.cc/150' }} style={styles.avatar} />
        <TouchableOpacity style={[styles.editButton, {backgroundColor: theme.primary}]} onPress={pickImage} disabled={uploading}>
            {uploading ? <ActivityIndicator color="white" size="small" /> : <Edit3 size={18} color="white" />}
        </TouchableOpacity>
      </View>

      <View style={styles.form}>
        <Input
          label="الاسم الكامل"
          value={fullName}
          onChangeText={setFullName}
        />
        <Input
          label="اسم المستخدم"
          value={username}
          onChangeText={setUsername}
          autoCapitalize="none"
        />
        <Input
          label="الحالة"
          value={status}
          onChangeText={setStatus}
        />
        
        <Button
          title={loading ? 'جارٍ الحفظ...' : 'حفظ التغييرات'}
          onPress={handleUpdateProfile}
          disabled={loading || uploading}
          style={{marginTop: 20}}
        />
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  contentContainer: {
    paddingBottom: 40,
  },
  avatarContainer: {
    alignItems: 'center',
    marginVertical: 30,
  },
  avatar: {
    width: 120,
    height: 120,
    borderRadius: 60,
    borderWidth: 3,
    borderColor: '#ccc'
  },
  editButton: {
    position: 'absolute',
    bottom: 0,
    right: '32%',
    width: 36,
    height: 36,
    borderRadius: 18,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: 'white'
  },
  form: {
    paddingHorizontal: 20,
  },
});
