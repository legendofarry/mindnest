import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/onboarding/data/onboarding_providers.dart';
import 'package:mindnest/features/onboarding/data/onboarding_question_bank.dart';
import 'package:mindnest/features/onboarding/models/onboarding_question.dart';

class OnboardingQuestionnaireScreen extends ConsumerStatefulWidget {
  const OnboardingQuestionnaireScreen({super.key});

  @override
  ConsumerState<OnboardingQuestionnaireScreen> createState() =>
      _OnboardingQuestionnaireScreenState();
}

class _OnboardingQuestionnaireScreenState
    extends ConsumerState<OnboardingQuestionnaireScreen> {
  final Map<String, dynamic> _answers = <String, dynamic>{};
  int _currentStep = 0;
  bool _isSubmitting = false;

  Future<void> _submit(UserRole role) async {
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(onboardingRepositoryProvider)
          .submitResponses(role: role, answers: _answers);
      if (!mounted) {
        return;
      }
      context.go(AppRoute.onboardingLoading);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _onContinue({
    required List<OnboardingQuestion> questions,
    required UserRole role,
  }) async {
    final question = questions[_currentStep];
    final error = _validationError(question);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    if (_currentStep == questions.length - 1) {
      await _submit(role);
      return;
    }

    setState(() => _currentStep += 1);
  }

  void _onBack() {
    if (_currentStep == 0) {
      return;
    }
    setState(() => _currentStep -= 1);
  }

  String? _validationError(OnboardingQuestion question) {
    final value = _answers[question.id];

    if (question.isMultiSelect) {
      final selected = (value as List<String>? ?? const <String>[]);
      if (selected.length < question.minSelections) {
        return 'Please choose at least one option to continue.';
      }
      return null;
    }

    if (question.isSingleSelect) {
      if (value is! String || value.isEmpty) {
        return 'Please choose one option to continue.';
      }
      return null;
    }

    if (question.isReminderTime) {
      if (value is! Map<String, dynamic>) {
        return 'Please choose your reminder time preference.';
      }
      final slot = value['slot'] as String?;
      if (slot == null || slot.isEmpty) {
        return 'Please choose your reminder time preference.';
      }
      if (slot == 'custom') {
        final customTime = value['customTime'] as String?;
        if (customTime == null || customTime.isEmpty) {
          return 'Please select your custom reminder time.';
        }
      }
      return null;
    }

    return null;
  }

  void _toggleMulti(OnboardingQuestion question, OnboardingOption option) {
    final selected = List<String>.from(
      _answers[question.id] as List<String>? ?? const [],
    );
    if (selected.contains(option.id)) {
      selected.remove(option.id);
    } else {
      selected.add(option.id);
    }
    setState(() => _answers[question.id] = selected);
  }

  void _setSingle(OnboardingQuestion question, OnboardingOption option) {
    setState(() => _answers[question.id] = option.id);
  }

  Future<void> _setReminderSlot(
    OnboardingQuestion question,
    OnboardingOption option,
  ) async {
    final current = Map<String, dynamic>.from(
      _answers[question.id] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );

    current['slot'] = option.id;

    if (!option.customTime) {
      current.remove('customTime');
      setState(() => _answers[question.id] = current);
      return;
    }

    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: now);
    if (!mounted) {
      return;
    }

    if (picked != null) {
      current['customTime'] = _formatTime(picked);
      setState(() => _answers[question.id] = current);
      return;
    }

    setState(() => _answers[question.id] = current);
  }

  Future<void> _pickCustomTime(OnboardingQuestion question) async {
    final current = Map<String, dynamic>.from(
      _answers[question.id] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );

    final initial = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (!mounted || picked == null) {
      return;
    }

    current['slot'] = 'custom';
    current['customTime'] = _formatTime(picked);
    setState(() => _answers[question.id] = current);
  }

  String _formatTime(TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return AuthBackgroundScaffold(
      maxWidth: 480,
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const _StateCard(message: 'Profile not found.');
          }

          final role = profile.role;
          final questions = OnboardingQuestionBank.forRole(role);
          if (questions.isEmpty) {
            return _StateCard(
              message:
                  'No onboarding questionnaire is required for ${role.label}.',
              actionLabel: 'Continue',
              onAction: () => context.go(AppRoute.home),
            );
          }

          if (_currentStep >= questions.length) {
            _currentStep = questions.length - 1;
          }

          final question = questions[_currentStep];
          final progress = (_currentStep + 1) / questions.length;
          final isLastStep = _currentStep == questions.length - 1;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            decoration: BoxDecoration(
              color: const Color(0xFCFFFFFF),
              borderRadius: BorderRadius.circular(34),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Step ${_currentStep + 1} of ${questions.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF95A4BA),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: progress,
                    backgroundColor: const Color(0xFFE6EEF8),
                    color: const Color(0xFF0E9B90),
                  ),
                ),
                const SizedBox(height: 22),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, animation) {
                    final slide =
                        Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        );
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: _QuestionStep(
                    key: ValueKey(question.id),
                    question: question,
                    answers: _answers,
                    onMultiToggle: (option) => _toggleMulti(question, option),
                    onSingleSelect: (option) => _setSingle(question, option),
                    onReminderSelect: (option) =>
                        _setReminderSlot(question, option),
                    onPickCustomTime: () => _pickCustomTime(question),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (_isSubmitting || _currentStep == 0)
                            ? null
                            : _onBack,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          foregroundColor: const Color(0xFF5E728D),
                          side: const BorderSide(color: Color(0xFFCFD8E6)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        child: const Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0E9B90), Color(0xFF18A89D)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4D72ECDC),
                              blurRadius: 28,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => _onContinue(
                                  questions: questions,
                                  role: role,
                                ),
                          style: ElevatedButton.styleFrom(
                            shadowColor: Colors.transparent,
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          child: Text(
                            _isSubmitting
                                ? 'Saving...'
                                : (isLastStep
                                      ? 'Enter MindNest  ->'
                                      : 'Continue  ->'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _StateCard(message: error.toString()),
      ),
    );
  }
}

class _QuestionStep extends StatelessWidget {
  const _QuestionStep({
    super.key,
    required this.question,
    required this.answers,
    required this.onMultiToggle,
    required this.onSingleSelect,
    required this.onReminderSelect,
    required this.onPickCustomTime,
  });

  final OnboardingQuestion question;
  final Map<String, dynamic> answers;
  final ValueChanged<OnboardingOption> onMultiToggle;
  final ValueChanged<OnboardingOption> onSingleSelect;
  final ValueChanged<OnboardingOption> onReminderSelect;
  final VoidCallback onPickCustomTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          question.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF071937),
            fontSize: 48 / 2,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          question.subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF5E728D),
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        if (question.id == 'today_mood')
          _buildMoodGrid(context)
        else
          _buildList(context),
        if (question.isReminderTime) ...[
          const SizedBox(height: 12),
          _buildReminderTimeDetails(context),
        ],
      ],
    );
  }

  Widget _buildMoodGrid(BuildContext context) {
    final selectedId = answers[question.id] as String?;

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final width = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final option in question.options)
              _MoodCard(
                option: option,
                width: width,
                selected: selectedId == option.id,
                onTap: () => onSingleSelect(option),
              ),
          ],
        );
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final rawValue = answers[question.id];
    final multiSelected = rawValue is List
        ? rawValue.whereType<String>().toSet()
        : <String>{};
    final singleSelected = rawValue is String ? rawValue : null;
    final reminderSelected = rawValue is Map<String, dynamic>
        ? rawValue['slot'] as String?
        : null;

    return Column(
      children: [
        for (final option in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SelectableCard(
              title: option.label,
              subtitle: option.description,
              badge: option.recommended ? 'RECOMMENDED' : null,
              emoji: option.emoji,
              selected: question.isMultiSelect
                  ? multiSelected.contains(option.id)
                  : question.isSingleSelect
                  ? singleSelected == option.id
                  : reminderSelected == option.id,
              onTap: () {
                if (question.isMultiSelect) {
                  onMultiToggle(option);
                  return;
                }
                if (question.isSingleSelect) {
                  onSingleSelect(option);
                  return;
                }
                onReminderSelect(option);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildReminderTimeDetails(BuildContext context) {
    final value =
        answers[question.id] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final customTime = value['customTime'] as String?;
    final selectedSlot = value['slot'] as String?;

    if (selectedSlot != 'custom') {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFFFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB3ECDD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded, color: Color(0xFF0E9B90)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              customTime == null
                  ? 'No custom time selected yet.'
                  : 'Selected custom time: $customTime',
              style: const TextStyle(
                color: Color(0xFF0D6F69),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onPickCustomTime,
            child: const Text('Pick time'),
          ),
        ],
      ),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.title,
    this.subtitle,
    this.badge,
    this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final String? emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFFFFC) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? const Color(0xFF6EE2C7) : const Color(0xFFD2DCE9),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: selected ? const Color(0x122CBFA9) : const Color(0x120F172A),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F2F6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    emoji ?? '•',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF071937),
                          fontWeight: FontWeight.w800,
                          fontSize: 31 / 2,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          badge!,
                          style: const TextStyle(
                            color: Color(0xFF95A4BA),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3,
                          ),
                        ),
                      ],
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Color(0xFF5E728D),
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? const Color(0xFF0E9B90)
                      : const Color(0xFFA3B3C9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({
    required this.option,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final OnboardingOption option;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFFFFC) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? const Color(0xFF6EE2C7) : const Color(0xFFD2DCE9),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  option.emoji ?? '🙂',
                  style: const TextStyle(fontSize: 34),
                ),
                const SizedBox(height: 8),
                Text(
                  option.label,
                  style: const TextStyle(
                    color: Color(0xFF071937),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
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

class _StateCard extends StatelessWidget {
  const _StateCard({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFCFFFFFF),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandMark(compact: true),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF4A607C),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
