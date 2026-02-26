enum AssistantActionType {
  openLiveHub,
  goLiveCreate,
  openCounselors,
  openCounselorProfile,
  openSessions,
  openNotifications,
  openCarePlan,
  openJoinInstitution,
  openPrivacy,
  setThemeLight,
  setThemeDark,
}

class AssistantAction {
  const AssistantAction({required this.type, this.params = const {}});

  final AssistantActionType type;
  final Map<String, String> params;
}

class AssistantSuggestedAction {
  const AssistantSuggestedAction({required this.label, required this.action});

  final String label;
  final AssistantAction action;
}

class AssistantReply {
  const AssistantReply({
    required this.text,
    this.action,
    this.usedExternalModel = false,
    this.suggestedActions = const <AssistantSuggestedAction>[],
  });

  final String text;
  final AssistantAction? action;
  final bool usedExternalModel;
  final List<AssistantSuggestedAction> suggestedActions;
}

class AssistantConversationMessage {
  const AssistantConversationMessage({required this.role, required this.text});

  final String role; // "user" | "assistant"
  final String text;
}
