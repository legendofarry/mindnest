import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class JoinInstitutionScreen extends ConsumerStatefulWidget {
  const JoinInstitutionScreen({super.key});

  @override
  ConsumerState<JoinInstitutionScreen> createState() =>
      _JoinInstitutionScreenState();
}

class _JoinInstitutionScreenState extends ConsumerState<JoinInstitutionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  UserRole _selectedRole = UserRole.student;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .joinInstitutionByCode(
            code: _codeController.text,
            role: _selectedRole,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Institution joined successfully.')),
      );
      final isVerified =
          ref.read(authRepositoryProvider).currentAuthUser?.emailVerified ??
          false;
      context.go(isVerified ? AppRoute.home : AppRoute.verifyEmail);
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
    return MindNestShell(
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Join your institution',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use the join code from your institution admin and select your role.',
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Join code'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Join code is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SegmentedButton<UserRole>(
                  selected: {_selectedRole},
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: UserRole.student,
                      label: Text('Student'),
                    ),
                    ButtonSegment(value: UserRole.staff, label: Text('Staff')),
                  ],
                  onSelectionChanged: (value) {
                    setState(() => _selectedRole = value.first);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Counselor role is created by Institution Admin invite only.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: Text(
                    _isSubmitting ? 'Joining...' : 'Join institution',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => context.go(AppRoute.postSignup),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
