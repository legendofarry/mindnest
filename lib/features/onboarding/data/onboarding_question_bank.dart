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
    final reminderFrequency = _single(answers, 'reminder_frequency');

    final isDistressMood = mood == 'stressed' || mood == 'low';
    final isStableMood = mood == 'great' || mood == 'good' || mood == 'neutral';
    final hasPressureFocus =
        focusAreas.contains('academic_pressure') ||
        focusAreas.contains('work_pressure');
    final hasSleepFocus = focusAreas.contains('sleep_problems');
    final wantsCounselorSupport = supportPreferences.contains(
      'talk_to_counselor',
    );
    final wantsAiSupport = supportPreferences.contains('ai_guidance');
    final wantsReminders = reminderFrequency != 'never';

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

    if (hasPressureFocus) {
      questions.add(_pressureContextQuestion);
    }

    if (hasSleepFocus) {
      questions.add(_sleepImpactQuestion);
    }

    questions.add(_supportPreferenceQuestion);

    if (wantsCounselorSupport) {
      questions.add(_counselorGoalQuestion);
    }

    if (wantsAiSupport) {
      questions.add(_aiCoachStyleQuestion);
      if (isDistressMood) {
        questions.add(_aiCheckInCadenceQuestion);
      }
    }

    questions.add(_reminderFrequencyQuestion);
    if (wantsReminders) {
      questions.add(_reminderTimeQuestion);
    }

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
      OnboardingOption(id: 'stress', label: 'Stress', recommended: true),
      OnboardingOption(id: 'anxiety', label: 'Anxiety', recommended: true),
      OnboardingOption(id: 'burnout', label: 'Burnout', recommended: true),
      OnboardingOption(
        id: 'depression_low_mood',
        label: 'Depression / low mood',
      ),
      OnboardingOption(id: 'academic_pressure', label: 'Academic pressure'),
      OnboardingOption(id: 'work_pressure', label: 'Work pressure'),
      OnboardingOption(id: 'relationship_issues', label: 'Relationship issues'),
    ],
  );

  static const OnboardingQuestion _todayMoodQuestion = OnboardingQuestion(
    id: 'today_mood',
    title: 'How are you feeling right now?',
    subtitle: 'Choose one mood that best matches your current state.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(id: 'great', label: 'Great'),
      OnboardingOption(id: 'good', label: 'Good'),
      OnboardingOption(id: 'neutral', label: 'Neutral'),
      OnboardingOption(id: 'stressed', label: 'Stressed'),
      OnboardingOption(id: 'low', label: 'Low'),
    ],
  );

  static const OnboardingQuestion _distressDurationQuestion =
      OnboardingQuestion(
        id: 'distress_duration',
        title: 'How long have you been feeling this way?',
        subtitle: 'This helps us choose the right level of support.',
        type: OnboardingQuestionType.singleSelect,
        options: [
          OnboardingOption(id: 'few_days', label: 'A few days'),
          OnboardingOption(id: 'one_to_four_weeks', label: '1-4 weeks'),
          OnboardingOption(id: 'one_to_three_months', label: '1-3 months'),
          OnboardingOption(id: 'more_than_three_months', label: '3+ months'),
        ],
      );

  static const OnboardingQuestion _distressIntensityQuestion =
      OnboardingQuestion(
        id: 'intensity_recent',
        title: 'How intense has it been recently?',
        subtitle: 'We use this to prioritize suggestions and pacing.',
        type: OnboardingQuestionType.singleSelect,
        options: [
          OnboardingOption(id: 'mild', label: 'Mild'),
          OnboardingOption(id: 'moderate', label: 'Moderate'),
          OnboardingOption(id: 'severe', label: 'Severe'),
        ],
      );

  static const OnboardingQuestion _immediateReliefQuestion = OnboardingQuestion(
    id: 'immediate_relief_need',
    title: 'Would you like quick relief steps now?',
    subtitle: 'We can prioritize short actions you can do in under 5 minutes.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(id: 'yes_now', label: 'Yes, show quick steps'),
      OnboardingOption(id: 'later', label: 'Later is fine'),
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
          OnboardingOption(id: 'sleep', label: 'Good sleep'),
          OnboardingOption(id: 'routine', label: 'Routine / structure'),
          OnboardingOption(id: 'exercise', label: 'Movement / exercise'),
          OnboardingOption(id: 'support_network', label: 'Family or friends'),
          OnboardingOption(
            id: 'mindfulness',
            label: 'Mindfulness / reflection',
          ),
          OnboardingOption(id: 'other', label: 'Other'),
        ],
      );

  static const OnboardingQuestion _pressureContextQuestion = OnboardingQuestion(
    id: 'pressure_context',
    title: 'Where is pressure highest right now?',
    subtitle: 'This helps tailor recommendations for your environment.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(id: 'school', label: 'School'),
      OnboardingOption(id: 'work', label: 'Work'),
      OnboardingOption(id: 'both', label: 'Both'),
      OnboardingOption(id: 'other', label: 'Other'),
    ],
  );

  static const OnboardingQuestion _sleepImpactQuestion = OnboardingQuestion(
    id: 'sleep_impact',
    title: 'Which sleep issue affects you most?',
    subtitle: 'Pick the one that best describes your recent pattern.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(id: 'falling_asleep', label: 'Falling asleep'),
      OnboardingOption(id: 'staying_asleep', label: 'Staying asleep'),
      OnboardingOption(id: 'waking_early', label: 'Waking up too early'),
      OnboardingOption(
        id: 'inconsistent_schedule',
        label: 'Irregular schedule',
      ),
    ],
  );

  static const OnboardingQuestion _supportPreferenceQuestion =
      OnboardingQuestion(
        id: 'support_preference',
        title: 'What support should MindNest prioritize?',
        subtitle: 'Choose all styles you want to see first.',
        type: OnboardingQuestionType.multiSelect,
        minSelections: 1,
        options: [
          OnboardingOption(
            id: 'self_help_tools',
            label: 'Self-help tools',
            description: 'Mood tracking, journaling, habits',
          ),
          OnboardingOption(
            id: 'guided_exercises',
            label: 'Guided exercises',
            description: 'Breathing, grounding, reset practices',
          ),
          OnboardingOption(
            id: 'reading_resources',
            label: 'Reading resources',
            description: 'Articles and practical explainers',
          ),
          OnboardingOption(
            id: 'talk_to_counselor',
            label: 'Talk to a counselor',
            description: 'Book sessions with professionals',
          ),
          OnboardingOption(
            id: 'ai_guidance',
            label: 'AI guidance',
            description: 'Chat support, check-ins, and action suggestions',
          ),
          OnboardingOption(
            id: 'peer_support',
            label: 'Peer support',
            description: 'Community and shared experiences',
          ),
        ],
      );

  static const OnboardingQuestion _counselorGoalQuestion = OnboardingQuestion(
    id: 'counselor_goal',
    title: 'What do you want from counseling first?',
    subtitle: 'This helps us suggest a better first appointment path.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(id: 'first_session', label: 'First-time session'),
      OnboardingOption(id: 'structured_plan', label: 'Structured care plan'),
      OnboardingOption(id: 'urgent_support', label: 'Priority support'),
      OnboardingOption(id: 'not_sure', label: 'Not sure yet'),
    ],
  );

  static const OnboardingQuestion _aiCoachStyleQuestion = OnboardingQuestion(
    id: 'ai_coach_style',
    title: 'How should MindNest AI support you?',
    subtitle: 'Choose the interaction style you prefer most.',
    type: OnboardingQuestionType.singleSelect,
    options: [
      OnboardingOption(id: 'gentle', label: 'Gentle and encouraging'),
      OnboardingOption(id: 'practical', label: 'Direct and action-focused'),
      OnboardingOption(id: 'reflective', label: 'Reflective and thoughtful'),
    ],
  );

  static const OnboardingQuestion _aiCheckInCadenceQuestion =
      OnboardingQuestion(
        id: 'ai_checkin_cadence',
        title: 'If mood drops, how often should AI check in?',
        subtitle: 'You can change this later in settings.',
        type: OnboardingQuestionType.singleSelect,
        options: [
          OnboardingOption(id: 'daily_short', label: 'Daily short check-ins'),
          OnboardingOption(id: 'every_two_days', label: 'Every 2 days'),
          OnboardingOption(id: 'weekly', label: 'Weekly'),
          OnboardingOption(
            id: 'manual_only',
            label: 'Only when I open AI chat',
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
          OnboardingOption(id: 'daily', label: 'Daily'),
          OnboardingOption(id: 'three_per_week', label: '3 times a week'),
          OnboardingOption(id: 'weekly', label: 'Weekly'),
          OnboardingOption(id: 'never', label: 'Never'),
        ],
      );

  static const OnboardingQuestion _reminderTimeQuestion = OnboardingQuestion(
    id: 'reminder_time',
    title: 'When should we remind you?',
    subtitle: 'Choose the best time for your check-ins.',
    type: OnboardingQuestionType.reminderTime,
    options: [
      OnboardingOption(id: 'morning', label: 'Morning'),
      OnboardingOption(id: 'afternoon', label: 'Afternoon'),
      OnboardingOption(id: 'evening', label: 'Evening'),
      OnboardingOption(id: 'custom', label: 'Custom time', customTime: true),
    ],
  );
}
