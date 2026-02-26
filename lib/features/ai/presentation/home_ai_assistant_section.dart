// features/ai/presentation/home_ai_assistant_section.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/ai/data/assistant_providers.dart';
import 'package:mindnest/features/ai/data/local_assistant_chat_store.dart';
import 'package:mindnest/features/ai/models/assistant_models.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class HomeAiAssistantSection extends ConsumerWidget {
  const HomeAiAssistantSection({
    super.key,
    required this.profile,
    required this.onActionRequested,
  });

  final UserProfile profile;
  final Future<void> Function(AssistantAction action) onActionRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE6F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF15A39A), Color(0xFF0E9B90)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'MindNest AI Assistant',
                  style: TextStyle(
                    color: Color(0xFF071937),
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await showMindNestAssistantSheet(
                  context: context,
                  profile: profile,
                  onActionRequested: onActionRequested,
                );
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Ask MindNest AI'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showMindNestAssistantSheet({
  required BuildContext context,
  required UserProfile profile,
  required Future<void> Function(AssistantAction action) onActionRequested,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return AssistantChatSheet(
        profile: profile,
        onActionRequested: onActionRequested,
      );
    },
  );
}

class AssistantChatSheet extends ConsumerStatefulWidget {
  const AssistantChatSheet({
    super.key,
    required this.profile,
    required this.onActionRequested,
  });

  final UserProfile profile;
  final Future<void> Function(AssistantAction action) onActionRequested;

  @override
  ConsumerState<AssistantChatSheet> createState() => _AssistantChatSheetState();
}

class _AssistantChatSheetState extends ConsumerState<AssistantChatSheet> {
  static const _defaultAssistantGreeting =
      'Hi, I am MindNest AI. Ask me to open app sections, find counselor slots, or chat for support.';
  static const _maxConversations = 24;
  static const _maxMessagesPerConversation = 180;
  static const _maxMemoryEntries = 10;

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  List<_UiConversation> _conversations = <_UiConversation>[];
  String? _activeConversationId;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _storageUserId {
    final rawId = widget.profile.id.trim().isNotEmpty
        ? widget.profile.id.trim()
        : widget.profile.email.trim().toLowerCase();
    return rawId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  Future<void> _loadConversations() async {
    final store = ref.read(assistantLocalChatStoreProvider);
    final state = await store.load(userId: _storageUserId);
    var conversations = state.conversations
        .map(_UiConversation.fromLocal)
        .toList(growable: true);
    conversations.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));

    if (conversations.isEmpty) {
      conversations = <_UiConversation>[
        _UiConversation.newConversation(
          id: _newId('conv'),
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          welcomeText: _defaultAssistantGreeting,
        ),
      ];
    }

    final restoredActive = state.activeConversationId;
    final activeId = conversations.any((item) => item.id == restoredActive)
        ? restoredActive
        : conversations.first.id;

    if (!mounted) {
      return;
    }
    setState(() {
      _conversations = conversations;
      _activeConversationId = activeId;
      _loading = false;
    });
    _scrollToBottom(jump: true);
  }

  Future<void> _persistConversations() async {
    if (_conversations.isEmpty) {
      return;
    }
    final state = AssistantLocalChatState(
      activeConversationId: _activeConversationId,
      conversations: _conversations
          .map((item) => item.toLocal())
          .toList(growable: false),
    );
    await ref
        .read(assistantLocalChatStoreProvider)
        .save(userId: _storageUserId, state: state);
  }

  _UiConversation? get _activeConversationOrNull {
    if (_conversations.isEmpty) {
      return null;
    }
    final activeId = _activeConversationId;
    if (activeId == null) {
      return _conversations.first;
    }
    final index = _conversations.indexWhere((item) => item.id == activeId);
    if (index < 0) {
      return _conversations.first;
    }
    return _conversations[index];
  }

  List<AssistantConversationMessage> _historyForModel(_UiConversation convo) {
    return convo.messages
        .map(
          (entry) => AssistantConversationMessage(
            role: entry.isUser ? 'user' : 'assistant',
            text: entry.text,
          ),
        )
        .toList(growable: false);
  }

  String _newId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = math.Random().nextInt(1000000);
    return '$prefix-$now-$rand';
  }

  String _titleFromUserText(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'New chat';
    }
    if (normalized.length <= 36) {
      return normalized;
    }
    return '${normalized.substring(0, 36)}...';
  }

  String _timeLabel(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _rollMemorySummary({
    required String existing,
    required String userPrompt,
    required String assistantReply,
  }) {
    String compact(String value, int limit) {
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length <= limit) {
        return normalized;
      }
      return '${normalized.substring(0, limit)}...';
    }

    final entry =
        'U: ${compact(userPrompt, 120)} | A: ${compact(assistantReply, 160)}';
    var previous = existing
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    previous.add(entry);
    if (previous.length > _maxMemoryEntries) {
      previous = previous.sublist(previous.length - _maxMemoryEntries);
    }
    final merged = previous.join('\n');
    if (merged.length <= 1500) {
      return merged;
    }
    return merged.substring(merged.length - 1500);
  }

  List<_UiMessage> _trimMessages(List<_UiMessage> source) {
    if (source.length <= _maxMessagesPerConversation) {
      return source;
    }
    final head = source.first;
    final tail = source.sublist(
      source.length - (_maxMessagesPerConversation - 1),
    );
    return <_UiMessage>[head, ...tail];
  }

  void _updateConversation(
    String id,
    _UiConversation Function(_UiConversation) map,
  ) {
    final index = _conversations.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    final updated = map(_conversations[index]);
    final next = List<_UiConversation>.from(_conversations);
    next[index] = updated;
    next.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    _conversations = next;
  }

  Future<void> _createConversation({bool makeActive = true}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final conversation = _UiConversation.newConversation(
      id: _newId('conv'),
      createdAtMs: now,
      welcomeText: _defaultAssistantGreeting,
    );
    setState(() {
      _conversations = <_UiConversation>[conversation, ..._conversations];
      if (_conversations.length > _maxConversations) {
        _conversations = _conversations.take(_maxConversations).toList();
      }
      if (makeActive) {
        _activeConversationId = conversation.id;
      }
    });
    await _persistConversations();
    _scrollToBottom(jump: true);
  }

  Future<void> _deleteActiveConversation() async {
    final active = _activeConversationOrNull;
    if (active == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text(
          'This chat history will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      if (_conversations.length == 1) {
        _conversations = <_UiConversation>[
          _UiConversation.newConversation(
            id: _newId('conv'),
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
            welcomeText: _defaultAssistantGreeting,
          ),
        ];
        _activeConversationId = _conversations.first.id;
      } else {
        _conversations = _conversations
            .where((item) => item.id != active.id)
            .toList(growable: false);
        _activeConversationId = _conversations.first.id;
      }
    });
    await _persistConversations();
    _scrollToBottom(jump: true);
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending || _loading) {
      return;
    }
    final active = _activeConversationOrNull;
    if (active == null) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final historyBefore = _historyForModel(active);
    final memorySummaryBefore = active.memorySummary;

    setState(() {
      _sending = true;
      _inputController.clear();
      _updateConversation(active.id, (conversation) {
        final updatedMessages = _trimMessages(<_UiMessage>[
          ...conversation.messages,
          _UiMessage(
            id: _newId('msg'),
            text: text,
            isUser: true,
            createdAtMs: now,
          ),
        ]);
        final nextTitle = conversation.title == 'New chat'
            ? _titleFromUserText(text)
            : conversation.title;
        return conversation.copyWith(
          title: nextTitle,
          updatedAtMs: now,
          messages: updatedMessages,
        );
      });
    });
    await _persistConversations();
    _scrollToBottom();

    final reply = await ref
        .read(assistantRepositoryProvider)
        .processPrompt(
          prompt: text,
          profile: widget.profile,
          history: historyBefore,
          memorySummary: memorySummaryBefore,
        );

    if (!mounted) {
      return;
    }

    final replyAt = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _updateConversation(active.id, (conversation) {
        final nextMessages = _trimMessages(<_UiMessage>[
          ...conversation.messages,
          _UiMessage(
            id: _newId('msg'),
            text: reply.text,
            isUser: false,
            createdAtMs: replyAt,
            usedExternalModel: reply.usedExternalModel,
          ),
        ]);
        final nextSummary = _rollMemorySummary(
          existing: conversation.memorySummary,
          userPrompt: text,
          assistantReply: reply.text,
        );
        return conversation.copyWith(
          updatedAtMs: replyAt,
          messages: nextMessages,
          memorySummary: nextSummary,
        );
      });
      _sending = false;
    });
    await _persistConversations();
    _scrollToBottom();

    if (reply.action != null) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      await widget.onActionRequested(reply.action!);
    }
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final activeConversation = _activeConversationOrNull;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 10 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD2DCE9),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ask MindNest AI',
                    style: TextStyle(
                      color: Color(0xFF071937),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (activeConversation != null &&
                    activeConversation.memorySummary.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6FFFA),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFF99F6E4)),
                    ),
                    child: const Text(
                      'Memory on',
                      style: TextStyle(
                        color: Color(0xFF0F766E),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              )
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDCE6F2)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: Color(0xFF4A607C),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: activeConversation?.id,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(12),
                          items: _conversations
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item.id,
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _sending
                              ? null
                              : (value) async {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() => _activeConversationId = value);
                                  await _persistConversations();
                                  _scrollToBottom(jump: true);
                                },
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'New chat',
                      onPressed: _sending ? null : () => _createConversation(),
                      icon: const Icon(Icons.add_comment_rounded),
                    ),
                    IconButton(
                      tooltip: 'Delete current chat',
                      onPressed: _sending ? null : _deleteActiveConversation,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  controller: _scrollController,
                  shrinkWrap: true,
                  itemCount: activeConversation?.messages.length ?? 0,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final message = activeConversation!.messages[index];
                    return Align(
                      alignment: message.isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Column(
                          crossAxisAlignment: message.isUser
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: message.isUser
                                    ? const Color(0xFF0E9B90)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                message.text,
                                style: TextStyle(
                                  color: message.isUser
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
                                  height: 1.3,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _timeLabel(message.createdAtMs),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask anything...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UiConversation {
  const _UiConversation({
    required this.id,
    required this.title,
    required this.updatedAtMs,
    required this.memorySummary,
    required this.messages,
  });

  factory _UiConversation.newConversation({
    required String id,
    required int createdAtMs,
    required String welcomeText,
  }) {
    return _UiConversation(
      id: id,
      title: 'New chat',
      updatedAtMs: createdAtMs,
      memorySummary: '',
      messages: <_UiMessage>[
        _UiMessage(
          id: 'welcome-$id',
          text: welcomeText,
          isUser: false,
          createdAtMs: createdAtMs,
        ),
      ],
    );
  }

  factory _UiConversation.fromLocal(AssistantLocalConversation local) {
    final mappedMessages = local.messages
        .map(
          (entry) => _UiMessage(
            id: 'local-${entry.createdAtMs}-${entry.role}',
            text: entry.text,
            isUser: entry.role == 'user',
            createdAtMs: entry.createdAtMs,
            usedExternalModel: entry.usedExternalModel,
          ),
        )
        .where((entry) => entry.text.trim().isNotEmpty)
        .toList(growable: false);

    return _UiConversation(
      id: local.id,
      title: local.title.trim().isEmpty ? 'Chat' : local.title,
      updatedAtMs: local.updatedAtMs,
      memorySummary: local.memorySummary,
      messages: mappedMessages,
    );
  }

  final String id;
  final String title;
  final int updatedAtMs;
  final String memorySummary;
  final List<_UiMessage> messages;

  _UiConversation copyWith({
    String? title,
    int? updatedAtMs,
    String? memorySummary,
    List<_UiMessage>? messages,
  }) {
    return _UiConversation(
      id: id,
      title: title ?? this.title,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      memorySummary: memorySummary ?? this.memorySummary,
      messages: messages ?? this.messages,
    );
  }

  AssistantLocalConversation toLocal() {
    return AssistantLocalConversation(
      id: id,
      title: title,
      updatedAtMs: updatedAtMs,
      memorySummary: memorySummary,
      messages: messages
          .map(
            (item) => AssistantLocalMessage(
              role: item.isUser ? 'user' : 'assistant',
              text: item.text,
              createdAtMs: item.createdAtMs,
              usedExternalModel: item.usedExternalModel,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _UiMessage {
  const _UiMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.createdAtMs,
    this.usedExternalModel = false,
  });

  final String id;
  final String text;
  final bool isUser;
  final int createdAtMs;
  final bool usedExternalModel;
}
