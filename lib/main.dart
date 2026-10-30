import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SocialApp());
}

class SocialApp extends StatelessWidget {
  const SocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SocialApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const AuthWrapper(),
    );
  }
}

/// 1. فحص الحالة: تسجيل دخول تلقائي مجهول في الخلفية ثم التحقق من إدخال الرقم واليوزر
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  User? _user;

  @override
  void initState() {
    super.initState();
    _initAnonymousAuth();
  }

  Future<void> _initAnonymousAuth() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        // تسجيل دخول تلقائي بدون إزعاج المستخدم بشاشات إيميل وباسورد
        UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
        currentUser = userCredential.user;
      }
      setState(() {
        _user = currentUser;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return const Scaffold(body: Center(child: Text('فشل الاتصال بالخدمة')));
    }

    // التحقق هل قام المستخدم بتسجيل رقمه واسم اليوزر مسبقاً في قاعدة البيانات أم لا
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(_user!.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          return HomeScreen(userData: snapshot.data!.data() as Map<String, dynamic>);
        } else {
          return RegisterProfileScreen(user: _user!);
        }
      },
    );
  }
}

/// 2. شاشة تسجيل البيانات لأول مرة (رقم التليفون واسم اليوزر)
class RegisterProfileScreen extends StatefulWidget {
  final User user;
  const RegisterProfileScreen({super.key, required this.user});

  @override
  State<RegisterProfileScreen> createState() => _RegisterProfileScreenState();
}

class _RegisterProfileScreenState extends State<RegisterProfileScreen> {
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _saveProfile() async {
    String phone = _phoneController.text.trim();
    String username = _usernameController.text.trim();

    if (phone.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('من فضلك ادخل رقم التليفون واسم المستخدم')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // التحقق هل رقم التليفون مستخدم من قبل
      final phoneQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .get();

      if (phoneQuery.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رقم التليفون هذا مستخدم بالفعل.')),
        );
        setState(() => _isLoading = false);
        return;
      }

      Map<String, dynamic> userData = {
        'uid': widget.user.uid,
        'phone': phone,
        'username': username,
        'createdAt': Timestamp.now(),
      };

      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).set(userData);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(userData: userData)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعداد الملف الشخصي')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'أهلاً بك! أدخل رقم هاتفك واسم المستخدم للبدء فوراً:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف (مثال: 012xxxxxxxx)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'اسم المستخدم (Username)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _saveProfile,
                    child: const Text('دخول إلى التطبيق'),
                  ),
          ],
        ),
      ),
    );
  }
}

/// 3. الشاشة الرئيسية وإمكانية البحث عن شخص برقم هاتفه
class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> userData;
  const HomeScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('مرحباً, @${userData['username']}'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble, size: 80, color: Colors.blue),
              const SizedBox(height: 20),
              Text(
                'رقم هاتفك: ${userData['phone']}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SearchUserScreen()),
                  );
                },
                icon: const Icon(Icons.search),
                label: const Text('البحث عن شخص برقم الهاتف والتواصل', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 4. شاشة البحث عن مستخدم برقم التليفون
class SearchUserScreen extends StatefulWidget {
  const SearchUserScreen({super.key});

  @override
  State<SearchUserScreen> createState() => _SearchUserScreenState();
}

class _SearchUserScreenState extends State<SearchUserScreen> {
  final _searchController = TextEditingController();
  Map<String, dynamic> যন্ত্রResult = {};
  bool _searched = false;
  bool _loading = false;

  void _searchByPhone() async {
    String phone = _searchController.text.trim();
    if (phone.isEmpty) return;

    setState(() {
      _loading = true;
      _searched = false;
    });

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('phone', isEqualTo: phone)
        .get();

    setState(() {
      _loading = false;
      _searched = true;
      if (query.docs.isNotEmpty) {
         যন্ত্রResult = query.docs.first.data();
      } else {
         যন্ত্রResult = {};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('بحث برقم الهاتف')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'ادخل رقم هاتف الشخص...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.blue, size: 30),
                  onPressed: _searchByPhone,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : _searched
                    ? যন্ত্রResult.isEmpty
                        ? const Text('لم يتم العثور على مستخدم بهذا الرقم', style: TextStyle(color: Colors.red))
                        : যন্ত্রResult['uid'] == currentUserId
                            ? const Text('هذا هو رقمك الشخصي!', style: TextStyle(color: Colors.grey))
                            : Card(
                                child: ListTile(
                                  leading: const Icon(Icons.person, size: 40, color: Colors.blue),
                                  title: Text( যন্ত্রResult['username']),
                                  subtitle: Text( যন্ত্রResult['phone']),
                                  trailing: ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChatScreen(
                                            peerUid:  যন্ত্রResult['uid'],
                                            peerUsername:  যন্ত্রResult['username'],
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text('مراسلة'),
                                  ),
                                ),
                              )
                    : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

/// 5. شاشة الدردشة الثنائية اللحظية بين الشخصين
class ChatScreen extends StatefulWidget {
  final String peerUid;
  final String peerUsername;

  const ChatScreen({super.key, required this.peerUid, required this.peerUsername});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final currentUser = FirebaseAuth.instance.currentUser!;

  String getChatRoomId(String uid1, String uid2) {
    if (uid1.compareTo(uid2) > 0) {
      return '$uid1\_$uid2';
    } else {
      return '$uid2\_$uid1';
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    String messageText = _messageController.text.trim();
    _messageController.clear();

    String chatRoomId = getChatRoomId(currentUser.uid, widget.peerUid);

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .add({
      'senderId': currentUser.uid,
      'receiverId': widget.peerUid,
      'message': messageText,
      'createdAt': Timestamp.now(),
    });
  }

  @override
  Widget build(BuildContext context) {
    String chatRoomId = getChatRoomId(currentUser.uid, widget.peerUid);

    return Scaffold(
      appBar: AppBar(title: Text('محادثة مع @${widget.peerUsername}')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatRoomId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msgData = messages[index].data() as Map<String, dynamic>;
                    bool isMe = msgData['senderId'] == currentUser.uid;

                    return Align(
                      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue[100] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          msgData['message'],
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالتك...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
