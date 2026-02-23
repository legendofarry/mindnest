enum AssistantActionType {
  openLiveHub,
  goLiveCreate,
  openCounselors,
  openSessions,
  openNotifications,
  openCarePlan,
  openJoinInstitution,
  openPrivacy,
}

class AssistantAction {
  const AssistantAction({required this.type});

  final AssistantActionType type;
}

class AssistantReply {
  const AssistantReply({
    required this.text,
    this.action,
    this.usedExternalModel = false,
  });

  final String text;
  final AssistantAction? action;
  final bool usedExternalModel;
}

class AssistantConversationMessage {
  const AssistantConversationMessage({required this.role, required this.text});

  final String role; // "user" | "assistant"
  final String text;
}
