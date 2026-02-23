import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/ai/data/assistant_providers.dart';
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
          const SizedBox(height: 10),
          const Text(
            'Ask app questions, open pages instantly, find counselor slots, or chat for support.',
            style: TextStyle(
              color: Color(0xFF516784),
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _QuickChip(label: 'I want to go live'),
              _QuickChip(label: 'Find open counselor slots'),
              _QuickChip(label: 'Open my sessions'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (sheetContext) {
                    return _AssistantChatSheet(
                      profile: profile,
                      onActionRequested: onActionRequested,
                    );
                  },
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

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF4A607C),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AssistantChatSheet extends ConsumerStatefulWidget {
  const _AssistantChatSheet({
    required this.profile,
    required this.onActionRequested,
  });

  final UserProfile profile;
  final Future<void> Function(AssistantAction action) onActionRequested;

  @override
  ConsumerState<_AssistantChatSheet> createState() =>
      _AssistantChatSheetState();
}

class _AssistantChatSheetState extends ConsumerState<_AssistantChatSheet> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_UiMessage> _messages = <_UiMessage>[
    const _UiMessage(
      text:
          'Hi, I am MindNest AI. Ask me to open app sections, find counselor slots, or chat for support.',
      isUser: false,
    ),
  ];

  bool _sending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<AssistantConversationMessage> _historyForModel() {
    return _messages
        .map(
          (entry) => AssistantConversationMessage(
            role: entry.isUser ? 'user' : 'assistant',
            text: entry.text,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }

    setState(() {
      _messages.add(_UiMessage(text: text, isUser: true));
      _sending = true;
      _inputController.clear();
    });
    _scrollToBottom();

    final reply = await ref
        .read(assistantRepositoryProvider)
        .processPrompt(
          prompt: text,
          profile: widget.profile,
          history: _historyForModel(),
        );

    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add(
        _UiMessage(
          text: reply.text,
          isUser: false,
          usedExternalModel: reply.usedExternalModel,
        ),
      );
      _sending = false;
    });
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
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
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ask MindNest AI',
                style: TextStyle(
                  color: Color(0xFF071937),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: _messages.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment: message.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: message.isUser
                              ? const Color(0xFF0E9B90)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.text,
                              style: TextStyle(
                                color: message.isUser
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
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
        ),
      ),
    );
  }
}

class _UiMessage {
  const _UiMessage({
    required this.text,
    required this.isUser,
    this.usedExternalModel = false,
  });

  final String text;
  final bool isUser;
  final bool usedExternalModel;
}
