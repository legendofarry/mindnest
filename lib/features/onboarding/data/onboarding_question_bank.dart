import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/onboarding/models/onboarding_question.dart';

class OnboardingQuestionBank {
  static const int version = 4;

  static bool roleRequiresQuestionnaire(UserRole role) {
    return role == UserRole.individual ||
        role == UserRole.student ||
        role == UserRole.staff;
  }

  static List<OnboardingQuestion> forRole(
    UserRole role, {
    Map<String, dynamic> answers = const <String, dynamic>{},
  }) {
    if (!roleRequiresQuestionnaire(role)) {
      return const [];
    }
    return _adaptiveQuestions(answers);
  }

  static List<OnboardingQuestion> _adaptiveQuestions(
    Map<String, dynamic> answers,
  ) {
    final mood = _single(answers, 'today_mood');
    final focusAreas = _multi(answers, 'focus_areas');
    final supportPreferences = _multi(answers, 'support_preference');

    final isDistressMood = mood == 'stressed' || mood == 'low';
    final isStableMood = mood == 'great' || mood == 'good' || mood == 'neutral';
    final hasSleepFocus = focusAreas.contains('sleep_problems');
    final wantsAiSupport = supportPreferences.contains('ai_guidance');

    final questions = <OnboardingQuestion>[
      _focusAreasQuestion,
      _todayMoodQuestion,
    ];

    if (isDistressMood) {
      questions
        ..add(_distressDurationQuestion)
        ..add(_distressIntensityQuestion)
        ..add(_immediateReliefQuestion);
    }

    if (isStableMood) {
      questions.add(_wellbeingDriversQuestion);
    }

    if (hasSleepFocus) {
      questions.add(_sleepImpactQuestion);
    }

    questions.add(_supportPreferenceQuestion);

    if (wantsAiSupport) {}

    questions.add(_reminderFrequencyQuestion);

    return questions;
  }

  static String _single(Map<String, dynamic> answers, String key) {
    final value = answers[key];
    if (value is String) {
      return value;
    }
    return '';
  }

  static Set<String> _multi(Map<String, dynamic> answers, String key) {
    final value = answers[key];
    if (value is List) {
      return value.whereType<String>().toSet();
    }
    return <String>{};
  }

  static const OnboardingQuestion _focusAreasQuestion = OnboardingQuestion(
    id: 'focus_areas',
    title: 'What brings you to MindNest?',
    subtitle: 'Select the areas you want help with first.',
    type: OnboardingQuestionType.multiSelect,
    minSelections: 1,
    options: [
      OnboardingOption(
        id: 'stress',
        label: 'Stress',
        recommended: true,
        emoji: '💧',
      ),
      OnboardingOption(
        id: 'anxiety',
        label: 'Anxiety',
        recommended: true,
        emoji: '💭',
      ),
      OnboardingOption(
        id: 'burnout',
        label: 'Burnout',
        recommended: true,
        emoji: '🔥',
      ),
      OnboardingOption(
        id: 'depression_low_mood',
        label: 'Depression / low mood',
        emoji: '🌥️',
      ),
      OnboardingOption(
        id: 'academic_pressure',
        label: 'Academic pressure',
        emoji: '📚',
      ),
      OnboardingOption(
        id: 'work_pressure',
        label: 'Work pressure',
        emoji: '💼',
      ),
      OnboardingOption(
        id: 'relationship_issues',
        label: 'Relationship issues',
        emoji: '💬',
      ),
    ],
  );

  static const OnboardingQuestion _todayMoodQuestion = OnboardingQuestion(
    id: 'today_mood',
    title: 'How are you feeling right now?',
    subtitle: 'Choose one mood that best matches your current state.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(id: 'great', label: 'Great', emoji: '😃'),
      OnboardingOption(id: 'good', label: 'Good', emoji: '🙂'),
      OnboardingOption(id: 'neutral', label: 'Neutral', emoji: '😐'),
      OnboardingOption(id: 'stressed', label: 'Stressed', emoji: '😰'),
      OnboardingOption(id: 'low', label: 'Low', emoji: '😔'),
    ],
  );

  static const OnboardingQuestion _distressDurationQuestion =
      OnboardingQuestion(
        id: 'distress_duration',
        title: 'How long have you been feeling this way?',
        subtitle: 'This helps us choose the right level of support.',
        type: OnboardingQuestionType.singleSelect,
        options: [
          OnboardingOption(id: 'few_days', label: 'A few days', emoji: '📆'),
          OnboardingOption(
            id: 'one_to_four_weeks',
            label: '1-4 weeks',
            emoji: '🗓️',
          ),
          OnboardingOption(
            id: 'one_to_three_months',
            label: '1-3 months',
            emoji: '📅',
          ),
          OnboardingOption(
            id: 'more_than_three_months',
            label: '3+ months',
            emoji: '🕰️',
          ),
        ],
      );

  static const OnboardingQuestion _distressIntensityQuestion =
      OnboardingQuestion(
        id: 'intensity_recent',
        title: 'How intense has it been recently?',
        subtitle: 'We use this to prioritize suggestions and pacing.',
        type: OnboardingQuestionType.singleSelect,
        options: [
          OnboardingOption(id: 'mild', label: 'Mild', emoji: '🌤️'),
          OnboardingOption(id: 'moderate', label: 'Moderate', emoji: '⛅'),
          OnboardingOption(id: 'severe', label: 'Severe', emoji: '🌧️'),
        ],
      );

  static const OnboardingQuestion _immediateReliefQuestion = OnboardingQuestion(
    id: 'immediate_relief_need',
    title: 'Would you like quick relief steps now?',
    subtitle: 'We can prioritize short actions you can do in under 5 minutes.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(
        id: 'yes_now',
        label: 'Yes, show quick steps',
        emoji: '⚡',
      ),
      OnboardingOption(id: 'later', label: 'Later is fine', emoji: '🕗'),
    ],
  );

  static const OnboardingQuestion _wellbeingDriversQuestion =
      OnboardingQuestion(
        id: 'wellbeing_drivers',
        title: 'What is helping you feel okay today?',
        subtitle: 'Choose what is currently working so we can reinforce it.',
        type: OnboardingQuestionType.multiSelect,
        minSelections: 1,
        options: [
          OnboardingOption(id: 'sleep', label: 'Good sleep', emoji: '🛌'),
          OnboardingOption(
            id: 'routine',
            label: 'Routine / structure',
            emoji: '📋',
          ),
          OnboardingOption(
            id: 'exercise',
            label: 'Movement / exercise',
            emoji: '🏃',
          ),
          OnboardingOption(
            id: 'support_network',
            label: 'Family or friends',
            emoji: '🤝',
          ),
          OnboardingOption(
            id: 'mindfulness',
            label: 'Mindfulness / reflection',
            emoji: '🧘',
          ),
          OnboardingOption(id: 'other', label: 'Other', emoji: '✨'),
        ],
      );

  static const OnboardingQuestion _sleepImpactQuestion = OnboardingQuestion(
    id: 'sleep_impact',
    title: 'Which sleep issue affects you most?',
    subtitle: 'Pick the one that best describes your recent pattern.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(
        id: 'falling_asleep',
        label: 'Falling asleep',
        emoji: '😴',
      ),
      OnboardingOption(
        id: 'staying_asleep',
        label: 'Staying asleep',
        emoji: '🛏️',
      ),
      OnboardingOption(
        id: 'waking_early',
        label: 'Waking up too early',
        emoji: '⏰',
      ),
      OnboardingOption(
        id: 'inconsistent_schedule',
        label: 'Irregular schedule',
        emoji: '📉',
      ),
    ],
  );

  static const OnboardingQuestion _supportPreferenceQuestion =
      OnboardingQuestion(
        id: 'support_preference',
        title: 'What support to prioritize?',
        subtitle: '',
        type: OnboardingQuestionType.multiSelect,
        minSelections: 1,
        options: [
          OnboardingOption(
            id: 'guided_exercises',
            label: 'Guided exercises',
            description: 'Breathing, grounding, reset practices',
            emoji: '🌬️',
          ),
          OnboardingOption(
            id: 'talk_to_counselor',
            label: 'Talk to a counselor',
            description: 'Book sessions with professionals',
            emoji: '🩺',
          ),
          OnboardingOption(
            id: 'ai_guidance',
            label: 'AI guidance',
            description: 'Chat support, check-ins, and action suggestions',
            emoji: '🤖',
          ),
        ],
      );

  static const OnboardingQuestion _reminderFrequencyQuestion =
      OnboardingQuestion(
        id: 'reminder_frequency',
        title: 'How often do you want reminders?',
        subtitle: 'Gentle reminders can improve consistency over time.',
        type: OnboardingQuestionType.singleSelect,
        options: [
          OnboardingOption(id: 'daily', label: 'Daily', emoji: '📆'),
          OnboardingOption(
            id: 'three_per_week',
            label: '3 times a week',
            emoji: '📌',
          ),
          OnboardingOption(id: 'weekly', label: 'Weekly', emoji: '🗓️'),
          OnboardingOption(id: 'never', label: 'Never', emoji: '🚫'),
        ],
      );
}
