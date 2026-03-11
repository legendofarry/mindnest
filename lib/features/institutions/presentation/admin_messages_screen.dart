import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String? _inlineError;
  final Set<String> _markingThreads = {};
  Map<String, int> _unreadCounts = const {};
  bool _listeningUnread = false;

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
        .where('adminId', isEqualTo: adminId)
        .where('counselorId', isEqualTo: counselorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => _ChatMessage.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  void _listenUnread(String adminId) {
    if (_listeningUnread) return;
    _listeningUnread = true;
    final firestore = ref.read(firestoreProvider);
    firestore
        .collection('admin_counselor_messages')
        .where('adminId', isEqualTo: adminId)
        .where('senderRole', isEqualTo: 'counselor')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final cid = (data['counselorId'] as String?) ?? '';
        if (cid.isEmpty) continue;
        counts[cid] = (counts[cid] ?? 0) + 1;
      }
      if (mounted) {
        setState(() => _unreadCounts = counts);
      }
    });
  }

  Future<void> _markThreadRead({
    required String adminId,
    required String counselorId,
  }) async {
    final threadKey = _threadKey(adminId, counselorId);
    if (_markingThreads.contains(threadKey)) return;
    _markingThreads.add(threadKey);
    final firestore = ref.read(firestoreProvider);
    try {
      final unreadSnap = await firestore
          .collection('admin_counselor_messages')
          .where('adminId', isEqualTo: adminId)
          .where('counselorId', isEqualTo: counselorId)
          .where('senderRole', isEqualTo: 'counselor')
          .where('isRead', isEqualTo: false)
          .limit(50)
          .get();
      if (unreadSnap.docs.isEmpty) return;
      final batch = firestore.batch();
      for (final doc in unreadSnap.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (_) {
      // ignore to keep UI responsive
    } finally {
      _markingThreads.remove(threadKey);
    }
  }

  void _showConversationMenu(String counselorId, String counselorName) {
    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    if (profile == null) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('Mark as read'),
                onTap: () async {
                  Navigator.pop(context);
                  await _markThreadRead(
                    adminId: profile.id,
                    counselorId: counselorId,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('View counselor profile'),
                onTap: () {
                  Navigator.pop(context);
                  // Hook up to counselor profile route if available.
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete conversation'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Delete conversation is not available yet.'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
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
    setState(() => _inlineError = null);
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
    } catch (error) {
      if (mounted) {
        setState(() => _inlineError = error.toString());
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    if (profile == null || profile.role != UserRole.institutionAdmin) {
      return const Scaffold(
        body: Center(
          child: Text('Only institution admins can message counselors.'),
        ),
      );
    }

    final institutionId = profile.institutionId ?? '';
    _listenUnread(profile.id);
    final firestore = ref.watch(firestoreProvider);
    final counselorsQuery = firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.counselor.name)
        .where('institutionId', isEqualTo: institutionId);

    final isWide = MediaQuery.sizeOf(context).width >= 960;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 14,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Counselor Messages',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: isWide
                ? Row(
                    children: [
                      SizedBox(
                        width: 280,
                        child: _CounselorListPane(
                          stream: counselorsQuery.snapshots(),
                          selectedId: _selectedCounselorId,
                          onSelected: (id, name) {
                            setState(() {
                              _selectedCounselorId = id;
                              _selectedCounselorName = name;
                            });
                          },
                          unreadCounts: _unreadCounts,
                          onMenu: _showConversationMenu,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _ChatPane(
                          profile: profile,
                          counselorId: _selectedCounselorId,
                          counselorName: _selectedCounselorName,
                          messagesBuilder: (cid) =>
                              _messages(adminId: profile.id, counselorId: cid),
                          onThreadSeen: (cid) => _markThreadRead(
                            adminId: profile.id,
                            counselorId: cid,
                          ),
                          messageController: _message,
                          sending: _sending,
                          inlineError: _inlineError,
                          onSend: () => _send(
                            admin: profile,
                            counselorId: _selectedCounselorId!,
                            counselorName:
                                _selectedCounselorName ?? 'Counselor',
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _MobileCounselorDropdown(
                        stream: counselorsQuery.snapshots(),
                        selectedId: _selectedCounselorId,
                        onSelected: (id, name) {
                          setState(() {
                            _selectedCounselorId = id;
                            _selectedCounselorName = name;
                          });
                        },
                      ),
                      const Divider(height: 24),
                      Expanded(
                        child: _ChatPane(
                          profile: profile,
                          counselorId: _selectedCounselorId,
                          counselorName: _selectedCounselorName,
                          messagesBuilder: (cid) =>
                              _messages(adminId: profile.id, counselorId: cid),
                          onThreadSeen: (cid) => _markThreadRead(
                            adminId: profile.id,
                            counselorId: cid,
                          ),
                          messageController: _message,
                          sending: _sending,
                          inlineError: _inlineError,
                          onSend: () => _send(
                            admin: profile,
                            counselorId: _selectedCounselorId!,
                            counselorName:
                                _selectedCounselorName ?? 'Counselor',
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CounselorListPane extends StatelessWidget {
  const _CounselorListPane({
    required this.stream,
    required this.selectedId,
    required this.onSelected,
    required this.unreadCounts,
    required this.onMenu,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String? selectedId;
  final void Function(String id, String name) onSelected;
  final Map<String, int> unreadCounts;
  final void Function(String counselorId, String counselorName) onMenu;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load counselors.\n${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('No counselors found.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final name =
                (data['name'] as String?) ?? (data['email'] as String?) ?? '';
            final selected = doc.id == selectedId;
            final unread = unreadCounts[doc.id] ?? 0;
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: selected
                  ? const Color(0xFFEFF6FF)
                  : (unread > 0 ? const Color(0xFFFEF3C7) : null),
              title: Text(
                name.isEmpty ? 'Counselor' : name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF0F172A)
                      : (unread > 0 ? const Color(0xFF92400E) : null),
                ),
              ),
              subtitle: Text(
                data['email'] as String? ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unread > 0)
                    _Badge(count: unread, color: const Color(0xFFDC2626)),
                  IconButton(
                    tooltip: 'Conversation options',
                    onPressed: () => onMenu(doc.id, name.isEmpty ? 'Counselor' : name),
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
              onTap: () =>
                  onSelected(doc.id, name.isEmpty ? 'Counselor' : name),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF0E9B90),
                child: Text(
                  _initials(name.isEmpty ? 'C' : name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemCount: docs.length,
        );
      },
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    return parts.take(2).map((e) => e[0].toUpperCase()).join();
  }
}

class _MobileCounselorDropdown extends StatelessWidget {
  const _MobileCounselorDropdown({
    required this.stream,
    required this.selectedId,
    required this.onSelected,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String? selectedId;
  final void Function(String id, String name) onSelected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        return DropdownButtonFormField<String>(
          value: selectedId,
          decoration: const InputDecoration(
            labelText: 'Select counselor',
            prefixIcon: Icon(Icons.person_rounded),
            filled: true,
          ),
          items: docs
              .map(
                (doc) => DropdownMenuItem(
                  value: doc.id,
                  child: Text(
                    doc.data()['name'] ?? doc.data()['email'] ?? 'Counselor',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSelected(
                    doc.id,
                    (doc.data()['name'] as String?) ??
                        (doc.data()['email'] as String?) ??
                        'Counselor',
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            final doc = docs.firstWhere(
              (element) => element.id == value,
              orElse: () => docs.isNotEmpty
                  ? docs.first
                  : (throw StateError('No counselors')),
            );
            final name =
                (doc.data()['name'] as String?) ??
                (doc.data()['email'] as String?) ??
                'Counselor';
            onSelected(value, name);
          },
        );
      },
    );
  }
}

class _ChatPane extends StatelessWidget {
  const _ChatPane({
    required this.profile,
    required this.counselorId,
    required this.counselorName,
    required this.messagesBuilder,
    required this.onThreadSeen,
    required this.messageController,
    required this.sending,
    required this.onSend,
    required this.inlineError,
  });

  final UserProfile profile;
  final String? counselorId;
  final String? counselorName;
  final Stream<List<_ChatMessage>> Function(String counselorId) messagesBuilder;
  final void Function(String counselorId) onThreadSeen;
  final TextEditingController messageController;
  final bool sending;
  final VoidCallback onSend;
  final String? inlineError;

  @override
  Widget build(BuildContext context) {
    if (counselorId == null) {
      return const Center(
        child: Text(
          'Select a counselor to start chatting.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF0E9B90),
                child: Text(
                  _initials(counselorName ?? 'Counselor'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    counselorName ?? 'Counselor',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Direct line • secure',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<_ChatMessage>>(
            stream: messagesBuilder(counselorId!),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ChatError(message: snapshot.error.toString());
              }
              final messages = snapshot.data ?? const [];
              if (messages.isNotEmpty) {
                onThreadSeen(counselorId!);
              }
              if (snapshot.connectionState == ConnectionState.waiting &&
                  messages.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (messages.isEmpty) {
                return const Center(child: Text('No messages yet.'));
              }
              return ListView.separated(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isAdmin = msg.senderRole == 'admin';
                  return Align(
                    alignment: isAdmin
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onLongPress: () async {
                          await Clipboard.setData(
                            ClipboardData(text: msg.body),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Message copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isAdmin
                                ? const Color(0xFF0E9B90)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
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
                                  _formatTimestamp(msg.createdAt),
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
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'typing...',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    prefixIcon: const Icon(Icons.chat_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: messageController,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Clear message',
                        onPressed: hasText ? messageController.clear : null,
                        icon: const Icon(Icons.close_rounded),
                      ),
                      FilledButton.icon(
                        onPressed: (!sending && hasText) ? onSend : null,
                        icon: sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(sending ? 'Sending...' : 'Send'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (inlineError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              inlineError!,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    return parts.take(2).map((e) => e[0].toUpperCase()).join();
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) return 'pending...';
    final local = value.toLocal();
    final twoDigits = (int v) => v.toString().padLeft(2, '0');
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    final date = '${local.month}/${local.day}/${local.year}';
    return '$date ${hour12}:${twoDigits(local.minute)} $suffix';
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

class _ChatError extends StatelessWidget {
  const _ChatError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFB91C1C), size: 40),
            const SizedBox(height: 12),
            const Text(
              'Unable to load messages',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, this.color = const Color(0xFF0E9B90)});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
