import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AssistantLocalChatStore {
  const AssistantLocalChatStore();

  static const _storagePrefix = 'mindnest.ai.chat.v1.';

  String _storageKey(String userId) => '$_storagePrefix$userId';

  Future<AssistantLocalChatState> load({required String userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_storageKey(userId));
    if (payload == null || payload.trim().isEmpty) {
      return const AssistantLocalChatState.empty();
    }
    try {
      return AssistantLocalChatState.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AssistantLocalChatState.empty();
    }
  }

  Future<void> save({
    required String userId,
    required AssistantLocalChatState state,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(userId), jsonEncode(state.toJson()));
  }
}

class AssistantLocalChatState {
  const AssistantLocalChatState({
    required this.activeConversationId,
    required this.conversations,
  });

  const AssistantLocalChatState.empty()
    : activeConversationId = null,
      conversations = const <AssistantLocalConversation>[];

  factory AssistantLocalChatState.fromJson(Map<String, dynamic> json) {
    final rawConversations = json['conversations'];
    final parsedConversations = <AssistantLocalConversation>[];
    if (rawConversations is List) {
      for (final item in rawConversations) {
        if (item is Map<String, dynamic>) {
          parsedConversations.add(AssistantLocalConversation.fromJson(item));
        } else if (item is Map) {
          parsedConversations.add(
            AssistantLocalConversation.fromJson(item.cast<String, dynamic>()),
          );
        }
      }
    }
    return AssistantLocalChatState(
      activeConversationId: (json['activeConversationId'] as String?)?.trim(),
      conversations: parsedConversations,
    );
  }

  final String? activeConversationId;
  final List<AssistantLocalConversation> conversations;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'activeConversationId': activeConversationId,
      'conversations': conversations.map((item) => item.toJson()).toList(),
    };
  }
}

class AssistantLocalConversation {
  const AssistantLocalConversation({
    required this.id,
    required this.title,
    required this.updatedAtMs,
    required this.memorySummary,
    required this.messages,
  });

  factory AssistantLocalConversation.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final parsedMessages = <AssistantLocalMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map<String, dynamic>) {
          parsedMessages.add(AssistantLocalMessage.fromJson(item));
        } else if (item is Map) {
          parsedMessages.add(
            AssistantLocalMessage.fromJson(item.cast<String, dynamic>()),
          );
        }
      }
    }

    return AssistantLocalConversation(
      id: (json['id'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim() ?? 'Chat',
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      memorySummary: (json['memorySummary'] as String?)?.trim() ?? '',
      messages: parsedMessages,
    );
  }

  final String id;
  final String title;
  final int updatedAtMs;
  final String memorySummary;
  final List<AssistantLocalMessage> messages;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'updatedAtMs': updatedAtMs,
      'memorySummary': memorySummary,
      'messages': messages.map((item) => item.toJson()).toList(),
    };
  }
}

class AssistantLocalMessage {
  const AssistantLocalMessage({
    required this.role,
    required this.text,
    required this.createdAtMs,
    required this.usedExternalModel,
    this.quickActions = const <AssistantLocalQuickAction>[],
  });

  factory AssistantLocalMessage.fromJson(Map<String, dynamic> json) {
    final rawQuickActions = json['quickActions'];
    final parsedQuickActions = <AssistantLocalQuickAction>[];
    if (rawQuickActions is List) {
      for (final item in rawQuickActions) {
        if (item is Map<String, dynamic>) {
          parsedQuickActions.add(AssistantLocalQuickAction.fromJson(item));
        } else if (item is Map) {
          parsedQuickActions.add(
            AssistantLocalQuickAction.fromJson(item.cast<String, dynamic>()),
          );
        }
      }
    }
    return AssistantLocalMessage(
      role: (json['role'] as String?)?.trim() ?? 'assistant',
      text: (json['text'] as String?)?.trim() ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      usedExternalModel: (json['usedExternalModel'] as bool?) ?? false,
      quickActions: parsedQuickActions,
    );
  }

  final String role;
  final String text;
  final int createdAtMs;
  final bool usedExternalModel;
  final List<AssistantLocalQuickAction> quickActions;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'role': role,
      'text': text,
      'createdAtMs': createdAtMs,
      'usedExternalModel': usedExternalModel,
      'quickActions': quickActions.map((item) => item.toJson()).toList(),
    };
  }
}

class AssistantLocalQuickAction {
  const AssistantLocalQuickAction({
    required this.label,
    required this.type,
    this.params = const <String, String>{},
  });

  factory AssistantLocalQuickAction.fromJson(Map<String, dynamic> json) {
    final paramsRaw = json['params'];
    final params = <String, String>{};
    if (paramsRaw is Map) {
      for (final entry in paramsRaw.entries) {
        params[entry.key.toString()] = entry.value.toString();
      }
    }
    return AssistantLocalQuickAction(
      label: (json['label'] as String?)?.trim() ?? '',
      type: (json['type'] as String?)?.trim() ?? '',
      params: params,
    );
  }

  final String label;
  final String type;
  final Map<String, String> params;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'label': label, 'type': type, 'params': params};
  }
}
