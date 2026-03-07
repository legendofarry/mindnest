import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/counselor/data/counselor_providers.dart';

class CounselorSetupScreen extends ConsumerStatefulWidget {
  const CounselorSetupScreen({super.key});

  @override
  ConsumerState<CounselorSetupScreen> createState() =>
      _CounselorSetupScreenState();
}

class _CounselorSetupScreenState extends ConsumerState<CounselorSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _yearsController = TextEditingController();
  final _languagesController = TextEditingController();
  final _bioController = TextEditingController();

  final Set<String> _selectedSpecializations = <String>{};

  String _sessionMode = 'Hybrid';
  String _timezone = 'UTC';
  bool _isSubmitting = false;
  bool _specializationsError = false;
  String? _formError;

  static const List<String> _specializations = <String>[
    'Academic Stress',
    'Career Guidance',
    'Anxiety',
    'Depression',
    'Relationship Issues',
    'Family Problems',
    'Self-Esteem',
    'Trauma',
    'Substance Abuse',
    'Bullying',
    'Grief & Loss',
    'General Counseling',
  ];

  static const List<String> _sessionModes = <String>[
    'In-person',
    'Online',
    'Hybrid',
  ];

  static const List<String> _timezones = <String>[
    'UTC',
    'Africa/Nairobi',
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
    'Asia/Dubai',
  ];

  static const List<_StepItem> _steps = <_StepItem>[
    _StepItem(
      number: '01',
      title: 'Profile Core',
      description: 'Title, experience, and the way students will find you.',
      accent: Color(0xFF0E9B90),
    ),
    _StepItem(
      number: '02',
      title: 'Care Focus',
      description: 'Choose every area you actively support, not just one.',
      accent: Color(0xFF2563EB),
    ),
    _StepItem(
      number: '03',
      title: 'Go Live',
      description: 'Add language, bio, and access settings for your workspace.',
      accent: Color(0xFFF59E0B),
    ),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _yearsController.dispose();
    _languagesController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _clearTopError() {
    if (_formError == null) {
      return;
    }
    setState(() => _formError = null);
  }

  void _toggleSpecialization(String value) {
    setState(() {
      if (_selectedSpecializations.contains(value)) {
        _selectedSpecializations.remove(value);
      } else {
        _selectedSpecializations.add(value);
      }
      if (_selectedSpecializations.isNotEmpty) {
        _specializationsError = false;
      }
      _formError = null;
    });
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    final hasSpecializations = _selectedSpecializations.isNotEmpty;

    if (!hasSpecializations || !formValid) {
      setState(() {
        _specializationsError = !hasSpecializations;
        _formError = !hasSpecializations
            ? 'Select at least one specialization.'
            : 'Please correct the highlighted fields.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
      _specializationsError = false;
    });

    try {
      final languages = _languagesController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      final years = int.tryParse(_yearsController.text.trim()) ?? 0;
      final specialization = _specializations
          .where(_selectedSpecializations.contains)
          .join(', ');

      await ref
          .read(counselorRepositoryProvider)
          .completeSetup(
            title: _titleController.text,
            specialization: specialization,
            yearsExperience: years,
            sessionMode: _sessionMode,
            timezone: _timezone,
            bio: _bioController.text,
            languages: languages,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Counselor profile setup completed.')),
      );
      context.go(AppRoute.counselorDashboard);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 720;

    return AuthBackgroundScaffold(
      maxWidth: isWide ? 760 : 560,
      fallingSnow: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: const Color(0xFFBEE9E4),
            width: 1.1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 36,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isWide ? 34 : 24,
            isWide ? 30 : 24,
            isWide ? 34 : 24,
            isWide ? 28 : 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BrandMark(compact: true),
                const SizedBox(height: 26),
                Text(
                  'Counselor Setup',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF071937),
                    letterSpacing: -0.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Build your counselor profile before the workspace opens. Pick every specialization you actually handle and finish the last access details here.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF5E728D),
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5FAFF),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFD8E8F8)),
                  ),
                  child: isWide
                      ? Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _steps
                              .map(
                                (step) =>
                                    _SetupStepCard(step: step, wide: true),
                              )
                              .toList(growable: false),
                        )
                      : Column(
                          children: _steps
                              .map(
                                (step) => Padding(
                                  padding: EdgeInsets.only(
                                    bottom: step == _steps.last ? 0 : 12,
                                  ),
                                  child: _SetupStepCard(step: step, wide: false),
                                ),
                              )
                              .toList(growable: false),
                        ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: (_formError == null || _formError!.trim().isEmpty)
                      ? const SizedBox(height: 24)
                      : Container(
                          key: ValueKey(_formError),
                          margin: const EdgeInsets.only(top: 16, bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECDD3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFBE123C),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _formError!,
                                  style: const TextStyle(
                                    color: Color(0xFF9F1239),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const _FieldLabel(text: 'PROFESSIONAL TITLE'),
                const SizedBox(height: 8),
                _RoundedInput(
                  child: TextFormField(
                    controller: _titleController,
                    onChanged: (_) => _clearTopError(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Licensed Professional Counselor',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().length < 2) {
                        return 'Please provide a professional title.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 18),
                const _FieldLabel(text: 'SPECIALIZATIONS'),
                const SizedBox(height: 6),
                Text(
                  'Choose every focus area you actively support.',
                  style: const TextStyle(
                    color: Color(0xFF7A8CA4),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _specializationsError
                        ? const Color(0xFFFFF7F7)
                        : const Color(0xFFF7FBFF),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _specializationsError
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFD7E4F1),
                    ),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _specializations
                        .asMap()
                        .entries
                        .map(
                          (entry) => _SpecializationPill(
                            label: entry.value,
                            selected: _selectedSpecializations.contains(
                              entry.value,
                            ),
                            index: entry.key,
                            onTap: () => _toggleSpecialization(entry.value),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
                if (_specializationsError)
                  const Padding(
                    padding: EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      'Select at least one specialization.',
                      style: TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildYearsField()),
                      const SizedBox(width: 14),
                      Expanded(child: _buildSessionModeField()),
                    ],
                  )
                else ...[
                  _buildYearsField(),
                  const SizedBox(height: 18),
                  _buildSessionModeField(),
                ],
                const SizedBox(height: 18),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildTimezoneField()),
                      const SizedBox(width: 14),
                      Expanded(child: _buildLanguagesField()),
                    ],
                  )
                else ...[
                  _buildTimezoneField(),
                  const SizedBox(height: 18),
                  _buildLanguagesField(),
                ],
                const SizedBox(height: 18),
                const _FieldLabel(text: 'PROFESSIONAL BIO'),
                const SizedBox(height: 8),
                _RoundedInput(
                  child: TextFormField(
                    controller: _bioController,
                    minLines: 4,
                    maxLines: 6,
                    onChanged: (_) => _clearTopError(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText:
                          'Briefly explain your counseling approach, tone, and the kind of support students can expect.',
                      alignLabelWithHint: true,
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 64),
                        child: Icon(Icons.notes_rounded),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  height: 62,
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
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      shadowColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _isSubmitting ? 'Saving setup...' : 'Complete Setup  ->',
                        key: ValueKey(_isSubmitting),
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildYearsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel(text: 'YEARS OF EXPERIENCE'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: TextFormField(
            controller: _yearsController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: (_) => _clearTopError(),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '3',
              prefixIcon: Icon(Icons.timeline_rounded),
            ),
            validator: (value) {
              final years = int.tryParse((value ?? '').trim());
              if (years == null || years < 0 || years > 60) {
                return 'Enter a valid number (0-60).';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSessionModeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel(text: 'SESSION MODE'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: DropdownButtonFormField<String>(
            initialValue: _sessionMode,
            decoration: const InputDecoration(
              border: InputBorder.none,
              prefixIcon: Icon(Icons.meeting_room_outlined),
            ),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            items: _sessionModes
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _sessionMode = value;
                _formError = null;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimezoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel(text: 'TIMEZONE'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: DropdownButtonFormField<String>(
            initialValue: _timezone,
            decoration: const InputDecoration(
              border: InputBorder.none,
              prefixIcon: Icon(Icons.public_rounded),
            ),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            items: _timezones
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _timezone = value;
                _formError = null;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLanguagesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel(text: 'LANGUAGES'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: TextFormField(
            controller: _languagesController,
            onChanged: (_) => _clearTopError(),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'English, Swahili',
              prefixIcon: Icon(Icons.language_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepItem {
  const _StepItem({
    required this.number,
    required this.title,
    required this.description,
    required this.accent,
  });

  final String number;
  final String title;
  final String description;
  final Color accent;
}

class _SetupStepCard extends StatelessWidget {
  const _SetupStepCard({required this.step, required this.wide});

  final _StepItem step;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? 210 : null,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE7F3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: step.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              step.number,
              style: TextStyle(
                color: step.accent,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    color: Color(0xFF071937),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.description,
                  style: const TextStyle(
                    color: Color(0xFF70849E),
                    fontSize: 12.6,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecializationPill extends StatelessWidget {
  const _SpecializationPill({
    required this.label,
    required this.selected,
    required this.index,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final int index;
  final VoidCallback onTap;

  static const List<List<Color>> _gradients = <List<Color>>[
    <Color>[Color(0xFFE7F8F5), Color(0xFFD5F1EC)],
    <Color>[Color(0xFFEAF2FF), Color(0xFFDCE8FF)],
    <Color>[Color(0xFFFFF2DD), Color(0xFFFFE8B8)],
    <Color>[Color(0xFFF2EAFE), Color(0xFFE7D8FF)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[index % _gradients.length];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: 14 + (index % 3).toDouble() * 2,
            vertical: 11 + (index.isEven ? 1 : 0),
          ),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF0E9B90), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : const Color(0xFFD6E4F1),
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x331D4ED8),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_rounded
                    : Icons.add_circle_outline_rounded,
                size: 16,
                color: selected
                    ? Colors.white
                    : const Color(0xFF58708C),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF0B2442),
                  fontWeight: FontWeight.w700,
                  fontSize: 13.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF9AAAC0),
        letterSpacing: 1.6,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }
}

class _RoundedInput extends StatelessWidget {
  const _RoundedInput({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD2DCE9),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}
