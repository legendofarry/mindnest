import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class AdminMessagesScreen extends ConsumerStatefulWidget {
  const AdminMessagesScreen({super.key});

  @override
  ConsumerState<AdminMessagesScreen> createState() =>
      _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends ConsumerState<AdminMessagesScreen> {
  String? _selectedCounselorId;
  String? _selectedCounselorName;
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String _threadKey(String adminId, String counselorId) =>
      '$adminId|$counselorId';

  Stream<List<_ChatMessage>> _messages({
    required String adminId,
    required String counselorId,
  }) {
    final firestore = ref.read(firestoreProvider);
    return firestore
        .collection('admin_counselor_messages')
        .where('threadKey', isEqualTo: _threadKey(adminId, counselorId))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => _ChatMessage.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> _send({
    required UserProfile admin,
    required String counselorId,
    required String counselorName,
  }) async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final firestore = ref.read(firestoreProvider);
    try {
      final threadKey = _threadKey(admin.id, counselorId);
      final batch = firestore.batch();
      final msgRef = firestore.collection('admin_counselor_messages').doc();
      batch.set(msgRef, {
        'threadKey': threadKey,
        'adminId': admin.id,
        'counselorId': counselorId,
        'institutionId': admin.institutionId ?? '',
        'senderRole': 'admin',
        'senderId': admin.id,
        'body': text,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final notifRef = firestore.collection('notifications').doc();
      batch.set(notifRef, {
        'userId': counselorId,
        'institutionId': admin.institutionId ?? '',
        'type': 'admin_message',
        'title': 'Message from ${admin.name}',
        'body': text,
        'priority': 'normal',
        'actionRequired': false,
        'route': AppRoute.notifications,
        'relatedId': msgRef.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'isPinned': false,
        'isArchived': false,
      });

      await batch.commit();
      _message.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent to counselor.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    if (profile == null || profile.role != UserRole.institutionAdmin) {
      return const Scaffold(
        body: Center(child: Text('Only institution admins can message counselors.')),
      );
    }

    final institutionId = profile.institutionId ?? '';
    final firestore = ref.watch(firestoreProvider);
    final counselorsQuery = firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.counselor.name)
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('name');

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Counselor Messages'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: counselorsQuery.snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? const [];
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedCounselorId,
                    decoration: const InputDecoration(
                      labelText: 'Select counselor',
                      prefixIcon: Icon(Icons.person_rounded),
                      filled: true,
                    ),
                    items: docs
                        .map(
                          (doc) => DropdownMenuItem(
                            value: doc.id,
                            child: Text(doc.data()['name'] ?? doc.data()['email'] ?? 'Counselor'),
                            onTap: () {
                              _selectedCounselorName =
                                  (doc.data()['name'] as String?) ??
                                      (doc.data()['email'] as String?) ??
                                      'Counselor';
                            },
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCounselorId = value;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              if (_selectedCounselorId != null)
                Expanded(
                  child: StreamBuilder<List<_ChatMessage>>(
                    stream: _messages(
                      adminId: profile.id,
                      counselorId: _selectedCounselorId!,
                    ),
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? const [];
                      if (messages.isEmpty) {
                        return const Center(
                          child: Text('No messages yet.'),
                        );
                      }
                      return ListView.separated(
                        reverse: true,
                        itemCount: messages.length,
                        separatorBuilder: (context, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isAdmin = msg.senderRole == 'admin';
                          return Align(
                            alignment: isAdmin
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: isWide ? 520 : MediaQuery.sizeOf(context).width * 0.8,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isAdmin
                                    ? const Color(0xFF0E9B90)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.body,
                                    style: TextStyle(
                                      color: isAdmin
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    msg.createdAt?.toLocal().toString() ??
                                        'pending...',
                                    style: TextStyle(
                                      color: isAdmin
                                          ? Colors.white70
                                          : const Color(0xFF64748B),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              if (_selectedCounselorId != null)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _message,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: 'Type a message to the counselor...',
                          filled: true,
                          prefixIcon: Icon(Icons.chat_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _sending
                          ? null
                          : () => _send(
                                admin: profile,
                                counselorId: _selectedCounselorId!,
                                counselorName: _selectedCounselorName ??
                                    'Counselor',
                              ),
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(_sending ? 'Sending...' : 'Send'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.id,
    required this.body,
    required this.senderRole,
    required this.createdAt,
  });

  final String id;
  final String body;
  final String senderRole;
  final DateTime? createdAt;

  factory _ChatMessage.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parse(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      return null;
    }

    return _ChatMessage(
      id: id,
      body: (data['body'] as String?) ?? '',
      senderRole: (data['senderRole'] as String?) ?? 'admin',
      createdAt: parse(data['createdAt']),
    );
  }
}
