import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class RegisterInstitutionScreen extends ConsumerStatefulWidget {
  const RegisterInstitutionScreen({super.key});

  @override
  ConsumerState<RegisterInstitutionScreen> createState() =>
      _RegisterInstitutionScreenState();
}

class _RegisterInstitutionScreenState
    extends ConsumerState<RegisterInstitutionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _institutionController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _institutionController.dispose();
    _adminNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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
          .createInstitutionAdminAccount(
            adminName: _adminNameController.text,
            adminEmail: _emailController.text,
            password: _passwordController.text,
            institutionName: _institutionController.text,
          );
      if (mounted) {
        context.go(AppRoute.verifyEmail);
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(error.message ?? 'Institution registration failed.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AuthBackgroundScaffold(
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
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _isSubmitting
                      ? null
                      : () => context.go(AppRoute.login),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 17,
                          color: Color(0xFF93A3BA),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Back to Login',
                          style: TextStyle(
                            color: Color(0xFF93A3BA),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F3F1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: Color(0xFF0E9B90),
                  size: 33,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Register Institution',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF071937),
                  fontSize: 48 / 2,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Create your institution workspace, admin account, and join code in one step.',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF516784),
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              const _FieldLabel(text: 'INSTITUTION NAME'),
              const SizedBox(height: 8),
              _RoundedInput(
                child: TextFormField(
                  controller: _institutionController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'MindNest University',
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().length < 2) {
                      return 'Enter an institution name.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel(text: 'ADMIN FULL NAME'),
              const SizedBox(height: 8),
              _RoundedInput(
                child: TextFormField(
                  controller: _adminNameController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Alex Rivera',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().length < 2) {
                      return 'Enter admin name.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel(text: 'ADMIN EMAIL ADDRESS'),
              const SizedBox(height: 8),
              _RoundedInput(
                child: TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'alex@example.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty || !trimmed.contains('@')) {
                      return 'Enter a valid email.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel(text: 'PASSWORD'),
              const SizedBox(height: 8),
              _RoundedInput(
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Minimum 8 characters',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  validator: (value) {
                    if ((value ?? '').length < 8) {
                      return 'Use at least 8 characters.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 22),
              Container(
                height: 62,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
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
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      _isSubmitting
                          ? 'Creating institution...'
                          : 'Create Institution  ->',
                      key: ValueKey(_isSubmitting),
                      style: const TextStyle(
                        fontSize: 35 / 2,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
        border: Border.all(color: const Color(0xFFD2DCE9)),
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
