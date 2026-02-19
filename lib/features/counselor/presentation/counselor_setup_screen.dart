import 'package:flutter/material.dart';
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

  String _specialization = 'General Counseling';
  String _sessionMode = 'Hybrid';
  String _timezone = 'UTC';
  bool _isSubmitting = false;

  static const List<String> _specializations = [
    'General Counseling',
    'Academic Counseling',
    'Workplace Wellbeing',
    'Anxiety & Stress Support',
    'Burnout Recovery',
    'Relationship Counseling',
  ];

  static const List<String> _sessionModes = ['In-person', 'Online', 'Hybrid'];

  static const List<String> _timezones = [
    'UTC',
    'Africa/Nairobi',
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
    'Asia/Dubai',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _yearsController.dispose();
    _languagesController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final languages = _languagesController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      final years = int.tryParse(_yearsController.text.trim()) ?? 0;

      await ref
          .read(counselorRepositoryProvider)
          .completeSetup(
            title: _titleController.text,
            specialization: _specialization,
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

  @override
  Widget build(BuildContext context) {
    return AuthBackgroundScaffold(
      maxWidth: 520,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Counselor Setup',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF071937),
                  fontSize: 48 / 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set up your professional profile before entering your counselor workspace.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF516784),
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Professional Title',
                  hintText: 'Licensed Counselor',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) {
                  if ((value ?? '').trim().length < 2) {
                    return 'Please provide a professional title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _specialization,
                decoration: const InputDecoration(
                  labelText: 'Specialization',
                  prefixIcon: Icon(Icons.psychology_alt_outlined),
                ),
                items: _specializations
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _specialization = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _yearsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Years of Experience',
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _sessionMode,
                decoration: const InputDecoration(
                  labelText: 'Session Mode',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
                items: _sessionModes
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _sessionMode = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _timezone,
                decoration: const InputDecoration(
                  labelText: 'Timezone',
                  prefixIcon: Icon(Icons.public_rounded),
                ),
                items: _timezones
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _timezone = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _languagesController,
                decoration: const InputDecoration(
                  labelText: 'Languages (comma separated)',
                  hintText: 'English, Swahili',
                  prefixIcon: Icon(Icons.language_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _bioController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Professional Bio',
                  hintText: 'Brief overview of your counseling approach.',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(_isSubmitting ? 'Saving...' : 'Complete Setup'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
