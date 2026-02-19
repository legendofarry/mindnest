enum OnboardingQuestionType { singleSelect, multiSelect, reminderTime }

class OnboardingOption {
  const OnboardingOption({
    required this.id,
    required this.label,
    this.description,
    this.emoji,
    this.recommended = false,
    this.customTime = false,
  });

  final String id;
  final String label;
  final String? description;
  final String? emoji;
  final bool recommended;
  final bool customTime;
}

class OnboardingQuestion {
  const OnboardingQuestion({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.options,
    this.minSelections = 1,
  });

  final String id;
  final String title;
  final String subtitle;
  final OnboardingQuestionType type;
  final List<OnboardingOption> options;
  final int minSelections;

  bool get isMultiSelect => type == OnboardingQuestionType.multiSelect;
  bool get isSingleSelect => type == OnboardingQuestionType.singleSelect;
  bool get isReminderTime => type == OnboardingQuestionType.reminderTime;
}
