# 📱 تطبيق وصل - دليل المطور الشامل

## 🎯 نظرة عامة على المشروع

**وصل** هو تطبيق دردشة ذكي وعصري مبني بتقنية React Native مع Expo، يهدف إلى توفير تجربة تواصل سلسة وآمنة بين المستخدمين.

### 🚀 الميزات الرئيسية
- **🔐 نظام مصادقة متكامل** مع Supabase
- **🎨 تصميم عصري** مع دعم الثيم الداكن/الفاتح
- **💬 دردشة فورية** مع إشعارات في الوقت الفعلي
- **📱 واجهة متجاوبة** لجميع أحجام الشاشات
- **🔄 عمل بدون إنترنت** مع مزامنة تلقائية
- **🌐 دعم اللغة العربية** مع RTL

---

## 🏗️ هيكل المشروع

```
wasl-app/
├── app/                      # صفحات التطبيق (Expo Router)
│   ├── index.tsx            # الصفحة الرئيسية - الترحيب والمصادقة
│   ├── (tabs)/              # التبويبات الرئيسية
│   │   ├── _layout.tsx      # تخطيط التبويبات
│   │   ├── chats.tsx        # قائمة المحادثات
│   │   ├── contacts.tsx     # جهات الاتصال
│   │   └── settings.tsx     # الإعدادات
│   ├── _layout.tsx          # التخطيط العام
│   └── +not-found.tsx       # صفحة 404
├── hooks/                   # React Hooks مخصصة
│   └── useFrameworkReady.ts # Hook لجاهزية الإطار
├── .env                     # متغيرات البيئة
├── package.json             # تبعيات المشروع
└── PROJECT_DOCUMENTATION.md # هذا الملف
```

---

## 🎨 نظام التصميم

### 🌈 ألوان الثيم

#### الثيم الداكن (افتراضي)
```typescript
const darkTheme = {
  background: '#000000',     // خلفية سوداء نقية
  surface: '#1c1c1e',       // أسطح داكنة
  primary: '#007AFF',       // أزرق iOS الكلاسيكي
  secondary: '#5856D6',     // بنفسجي أنيق
  text: '#ffffff',          // نص أبيض
  textSecondary: '#8e8e93', // نص ثانوي رمادي
  border: '#38383a',        // حدود داكنة
  card: '#2c2c2e',          // بطاقات داكنة
  accent: '#34C759',        // أخضر للحالة النشطة
  error: '#FF453A',         // أحمر للأخطاء
  warning: '#FF9F0A',       // برتقالي للتحذيرات
};
```

#### الثيم الفاتح
```typescript
const lightTheme = {
  background: '#ffffff',     // خلفية بيضاء
  surface: '#f8f9fa',       // أسطح فاتحة
  primary: '#007AFF',       // أزرق iOS
  text: '#1d1d1d',          // نص داكن
  textSecondary: '#8e8e93', // نص ثانوي
  // ... باقي الألوان
};
```

### 📐 التخطيط والتصميم

#### مبادئ التصميم
1. **البساطة**: واجهة نظيفة وبديهية
2. **الوضوح**: عناصر واضحة ومقروءة
3. **التناسق**: ألوان وخطوط موحدة
4. **الاستجابة**: تكيف مع جميع أحجام الشاشات

#### العناصر الأساسية
- **الأزرار**: دائرية مع ظلال ناعمة
- **البطاقات**: زوايا مدورة وخلفيات متدرجة
- **الحقول**: تصميم iOS مع حدود ناعمة
- **الآيقونات**: من مكتبة Lucide React Native

---

## ⚡ التقنيات المستخدمة

### 🛠️ المكتبات الأساسية

| التقنية | الإصدار | الغرض |
|---------|---------|--------|
| **React Native** | 0.79.2 | إطار العمل الأساسي |
| **Expo** | 53.0.9 | أدوات التطوير والنشر |
| **TypeScript** | 5.8.3 | لغة البرمجة |
| **Expo Router** | 5.0.7 | التنقل بين الصفحات |

### 🎨 واجهة المستخدم

| المكتبة | الغرض |
|---------|--------|
| **expo-linear-gradient** | التدرجات اللونية |
| **lucide-react-native** | الآيقونات |
| **@expo/vector-icons** | آيقونات إضافية |
| **react-native-safe-area-context** | منطقة الأمان |

### 🔗 الباكاند والبيانات

| التقنية | الغرض |
|---------|--------|
| **Supabase** | قاعدة البيانات والمصادقة |
| **@supabase/supabase-js** | عميل Supabase |
| **AsyncStorage** | التخزين المحلي |
| **@faker-js/faker** | البيانات التجريبية |

---

## 🗄️ قاعدة البيانات (Supabase)

### 📊 المخطط المقترح للجداول

#### جدول المستخدمين (Users)
```sql
-- يتم إنشاء المستخدمين تلقائياً في auth.users
-- جدول إضافي للملفات الشخصية
CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  full_name TEXT,
  avatar_url TEXT,
  phone TEXT,
  status TEXT,
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

#### جدول المحادثات (Conversations)
```sql
CREATE TABLE conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type TEXT CHECK (type IN ('direct', 'group')) DEFAULT 'direct',
  name TEXT, -- للمحادثات الجماعية
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

#### جدول أعضاء المحادثات (Conversation Members)
```sql
CREATE TABLE conversation_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT CHECK (role IN ('admin', 'member')) DEFAULT 'member',
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(conversation_id, user_id)
);
```

#### جدول الرسائل (Messages)
```sql
CREATE TABLE messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT,
  message_type TEXT CHECK (message_type IN ('text', 'image', 'file')) DEFAULT 'text',
  file_url TEXT,
  reply_to UUID REFERENCES messages(id),
  is_edited BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

#### جدول حالة قراءة الرسائل (Message Status)
```sql
CREATE TABLE message_status (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT CHECK (status IN ('sent', 'delivered', 'read')) DEFAULT 'sent',
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id)
);
```

### 🔒 سياسات الأمان (RLS)

```sql
-- تفعيل RLS على جميع الجداول
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_status ENABLE ROW LEVEL SECURITY;

-- سياسات المستخدمين
CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- سياسات المحادثات (المستخدم يرى فقط محادثاته)
CREATE POLICY "Users can view their conversations" ON conversations
  FOR SELECT USING (
    id IN (
      SELECT conversation_id FROM conversation_members 
      WHERE user_id = auth.uid()
    )
  );

-- سياسات الرسائل (المستخدم يرى فقط رسائل محادثاته)
CREATE POLICY "Users can view messages in their conversations" ON messages
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_members 
      WHERE user_id = auth.uid()
    )
  );
```

---

## 📱 الصفحات والمكونات

### 🏠 الصفحة الرئيسية (index.tsx)
**الوظائف:**
- شاشة ترحيب جذابة مع شعار التطبيق
- نموذج تسجيل دخول وإنشاء حساب
- عرض ميزات التطبيق
- تبديل الثيم الداكن/الفاتح
- دخول كضيف

**المكونات:**
- `LinearGradient` للخلفيات المتدرجة
- `TouchableOpacity` للأزرار التفاعلية
- `TextInput` للحقول
- آيقونات من `lucide-react-native`

### 💬 قائمة المحادثات (chats.tsx)
**الوظائف:**
- عرض جميع المحادثات النشطة
- البحث السريع في المحادثات
- عرض آخر رسالة ووقت الإرسال
- مؤشر الرسائل غير المقروءة
- حالة الاتصال (متصل/غير متصل)
- حالة الرسالة (مرسلة/مستلمة/مقروءة)

**البيانات التجريبية:**
```typescript
const chatItem = {
  id: 'chat_1',
  name: 'أحمد محمد',
  lastMessage: 'مرحباً، كيف حالك؟',
  timestamp: new Date(),
  avatar: 'https://i.pravatar.cc/150?img=1',
  unreadCount: 3,
  isOnline: true,
  messageStatus: 'read'
};
```

### 👥 جهات الاتصال (contacts.tsx)
**الوظائف:**
- عرض جميع جهات الاتصال
- البحث بالاسم أو رقم الهاتف
- بدء محادثة جديدة
- حالة الاتصال
- معلومات الحالة الشخصية

### ⚙️ الإعدادات (settings.tsx)
**الوظائف:**
- عرض معلومات المستخدم
- تبديل الثيم
- إعدادات الإشعارات
- إعدادات الخصوصية والأمان
- تسجيل الخروج
- معلومات التطبيق

**الأقسام:**
1. **الملف الشخصي**: صورة، اسم، بريد إلكتروني
2. **عام**: الثيم، الإشعارات، الألوان
3. **الخصوصية والأمان**: كلمة المرور، النسخ الاحتياطي
4. **الدعم**: المساعدة، معلومات التطبيق

---

## 🔧 إعداد البيئة

### 📋 متطلبات النظام
- **Node.js** 18.0.0 أو أحدث
- **npm** أو **yarn**
- **Expo CLI** للتطوير
- **Android Studio** (للأندرويد)
- **Xcode** (لـ iOS - macOS فقط)

### ⚡ التثبيت والتشغيل

```bash
# 1. تثبيت التبعيات
yarn install

# 2. إنشاء ملف البيئة
echo "SUPABASE_URL=your_supabase_url" > .env
echo "SUPABASE_ANON_KEY=your_anon_key" >> .env

# 3. تشغيل التطبيق
yarn dev

# 4. فتح على الهاتف
# امسح الـ QR code باستخدام Expo Go
```

### 🔌 إعداد Supabase

1. **إنشاء مشروع جديد** على [supabase.com](https://supabase.com)
2. **الحصول على URL و API Key** من إعدادات المشروع
3. **تشغيل SQL Scripts** لإنشاء الجداول
4. **تفعيل Email Auth** في Authentication

---

## 🚀 خطة التطوير المستقبلية

### 📅 المرحلة الحالية - MVP ✅
- [x] واجهة المستخدم الأساسية
- [x] نظام المصادقة
- [x] التصميم المتجاوب
- [x] التبديل بين الثيمات
- [x] البيانات التجريبية

### 🔄 المرحلة التالية - المحادثات الحقيقية
- [ ] إنشاء جداول قاعدة البيانات
- [ ] صفحة المحادثة الفردية
- [ ] إرسال واستقبال الرسائل
- [ ] الإشعارات الفورية مع WebSocket
- [ ] حالة قراءة الرسائل

### 🌟 المراحل المتقدمة
- [ ] إرسال الصور والملفات
- [ ] المحادثات الجماعية
- [ ] الرسائل الصوتية
- [ ] البحث في المحادثات
- [ ] التخزين المحلي (Offline Mode)
- [ ] النسخ الاحتياطي التلقائي

### 📱 النشر والتوزيع
- [ ] بناء نسخة الإنتاج
- [ ] اختبار الأداء
- [ ] النشر على Google Play Store
- [ ] النشر على Apple App Store

---

## 🐛 استكشاف الأخطاء

### ❌ مشاكل شائعة وحلولها

#### التطبيق لا يظهر شيء
```bash
# تأكد من وجود ملف app/index.tsx
# تأكد من تثبيت جميع التبعيات
yarn install
yarn dev
```

#### خطأ في Supabase
```javascript
// تأكد من صحة متغيرات البيئة
console.log('Supabase URL:', process.env.SUPABASE_URL);
console.log('Supabase Key:', process.env.SUPABASE_ANON_KEY);
```

#### مشاكل في الخطوط
```bash
# تثبيت خطوط إضافية
expo install @expo-google-fonts/inter
```

---

## 🤝 المساهمة في المشروع

### 📝 إرشادات المساهمة
1. **Fork** المشروع
2. إنشاء **branch** جديد للميزة
3. **Commit** التغييرات مع رسائل واضحة
4. **Push** إلى الـ branch
5. إنشاء **Pull Request**

### 🎯 معايير الكود
- استخدام **TypeScript** لجميع الملفات
- اتباع **ESLint** rules
- كتابة **تعليقات** باللغة العربية
- **اختبار** الميزات قبل الـ commit

---

## 📞 التواصل والدعم

### 🆘 الحصول على المساعدة
- **GitHub Issues**: للأخطاء والاقتراحات
- **Documentation**: هذا الملف للمرجعية
- **Expo Docs**: [docs.expo.dev](https://docs.expo.dev)
- **Supabase Docs**: [supabase.com/docs](https://supabase.com/docs)

### 📧 معلومات الاتصال
- **المطور**: Dualite Alpha
- **المشروع**: تطبيق وصل للدردشة
- **الإصدار**: 1.0.0
- **الترخيص**: MIT

---

**🎉 شكراً لاختيارك تطبيق وصل! نتمنى لك تجربة تطوير ممتعة ومثمرة.**

---

*آخر تحديث: يناير 2025*
