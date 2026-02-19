import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/onboarding/models/onboarding_question.dart';

class OnboardingQuestionBank {
  static const int version = 3;

  static bool roleRequiresQuestionnaire(UserRole role) {
    return role == UserRole.individual ||
        role == UserRole.student ||
        role == UserRole.staff;
  }

  static List<OnboardingQuestion> forRole(UserRole role) {
    if (!roleRequiresQuestionnaire(role)) {
      return const [];
    }
    return _questions;
  }

  static const List<OnboardingQuestion> _questions = [
    OnboardingQuestion(
      id: 'focus_areas',
      title: 'What brings you to MindNest?',
      subtitle: 'Select the areas you\'d like to focus on first.',
      type: OnboardingQuestionType.multiSelect,
      minSelections: 1,
      options: [
        OnboardingOption(
          id: 'stress',
          label: 'Stress',
          emoji: '⚡',
          recommended: true,
        ),
        OnboardingOption(
          id: 'anxiety',
          label: 'Anxiety',
          emoji: '✨',
          recommended: true,
        ),
        OnboardingOption(
          id: 'burnout',
          label: 'Burnout',
          emoji: '☕',
          recommended: true,
        ),
        OnboardingOption(
          id: 'depression_low_mood',
          label: 'Depression / low mood',
          emoji: '🌧',
        ),
        OnboardingOption(
          id: 'academic_pressure',
          label: 'Academic pressure',
          emoji: '🎓',
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
        OnboardingOption(
          id: 'sleep_problems',
          label: 'Sleep problems',
          emoji: '🌙',
        ),
        OnboardingOption(
          id: 'motivation_productivity',
          label: 'Motivation / productivity',
          emoji: '🎯',
        ),
        OnboardingOption(
          id: 'self_improvement',
          label: 'Self improvement',
          emoji: '🚀',
        ),
        OnboardingOption(id: 'other', label: 'Other', emoji: '➕'),
      ],
    ),
    OnboardingQuestion(
      id: 'today_mood',
      title: 'How are you feeling today?',
      subtitle: 'Select one mood that best matches how you feel right now.',
      type: OnboardingQuestionType.singleSelect,
      options: [
        OnboardingOption(id: 'great', label: 'Great', emoji: '😄'),
        OnboardingOption(id: 'good', label: 'Good', emoji: '🙂'),
        OnboardingOption(id: 'neutral', label: 'Neutral', emoji: '😐'),
        OnboardingOption(id: 'stressed', label: 'Stressed', emoji: '😟'),
        OnboardingOption(id: 'low', label: 'Low', emoji: '😢'),
      ],
    ),
    OnboardingQuestion(
      id: 'intensity_recent',
      title: 'How intense has it been recently?',
      subtitle:
          'This helps us rank recommendations without asking sensitive questions.',
      type: OnboardingQuestionType.singleSelect,
      options: [
        OnboardingOption(id: 'mild', label: 'Mild'),
        OnboardingOption(id: 'moderate', label: 'Moderate'),
        OnboardingOption(id: 'severe', label: 'Severe'),
      ],
    ),
    OnboardingQuestion(
      id: 'support_preference',
      title: 'What support do you prefer?',
      subtitle: 'Choose all support styles you want MindNest to prioritize.',
      type: OnboardingQuestionType.multiSelect,
      minSelections: 1,
      options: [
        OnboardingOption(
          id: 'self_help_tools',
          label: 'Self-help tools',
          description: 'Mood tracking, journaling',
        ),
        OnboardingOption(
          id: 'guided_exercises',
          label: 'Guided exercises',
          description: 'Breathing, meditation',
        ),
        OnboardingOption(
          id: 'reading_resources',
          label: 'Reading resources',
          description: 'Articles, PDFs',
        ),
        OnboardingOption(
          id: 'talk_to_counselor',
          label: 'Talking to a counselor',
          description: 'Appointments',
        ),
        OnboardingOption(
          id: 'peer_support',
          label: 'Peer support',
          description: 'Forum, community',
        ),
      ],
    ),
    OnboardingQuestion(
      id: 'reminder_frequency',
      title: 'How often do you want reminders?',
      subtitle: 'MindNest works best with gentle daily reminders.',
      type: OnboardingQuestionType.singleSelect,
      options: [
        OnboardingOption(id: 'daily', label: 'Daily'),
        OnboardingOption(id: 'three_per_week', label: '3 times a week'),
        OnboardingOption(id: 'weekly', label: 'Weekly'),
        OnboardingOption(id: 'never', label: 'Never'),
      ],
    ),
    OnboardingQuestion(
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
    ),
  ];
}
