import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/terms_and_privacy_screen.dart';

class RegisterDetailsScreen extends ConsumerStatefulWidget {
  const RegisterDetailsScreen({
    super.key,
    this.inviteId,
    this.invitedEmail,
    this.invitedName,
    this.institutionName,
    this.intendedRole,
    this.registrationIntent,
  });

  final String? inviteId;
  final String? invitedEmail;
  final String? invitedName;
  final String? institutionName;
  final String? intendedRole;
  final String? registrationIntent;

  @override
  ConsumerState<RegisterDetailsScreen> createState() =>
      _RegisterDetailsScreenState();
}

class _RegisterDetailsScreenState extends ConsumerState<RegisterDetailsScreen> {
  static const _kenyaPrefix = '+254';
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _additionalPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  Map<String, String> get _inviteQuery => AppRoute.inviteQuery(
    inviteId: widget.inviteId ?? '',
    invitedEmail: widget.invitedEmail,
    invitedName: widget.invitedName,
    institutionName: widget.institutionName,
    intendedRole: widget.intendedRole,
  );

  bool get _hasInviteContext => _inviteQuery.isNotEmpty;
  bool get _isCounselorIntent {
    if (_hasInviteContext) {
      return false;
    }
    return (widget.registrationIntent ?? '').trim() ==
        UserProfile.counselorRegistrationIntent;
  }

  String _routeWithCurrentContext(String path) {
    return AppRoute.withInviteAndRegistrationIntent(
      path,
      _inviteQuery,
      registrationIntent: _isCounselorIntent
          ? UserProfile.counselorRegistrationIntent
          : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _phoneController.text = _kenyaPrefix;
    _phoneController.addListener(_enforcePrimaryPhonePrefix);
    _additionalPhoneController.addListener(_enforceOptionalPhonePrefix);
    final invitedName = (widget.invitedName ?? '').trim();
    if (invitedName.isNotEmpty) {
      _nameController.text = invitedName;
    }
    final invitedEmail = (widget.invitedEmail ?? '').trim().toLowerCase();
    if (invitedEmail.isNotEmpty) {
      _emailController.text = invitedEmail;
    }
  }

  @override
  void dispose() {
    _phoneController.removeListener(_enforcePrimaryPhonePrefix);
    _additionalPhoneController.removeListener(_enforceOptionalPhonePrefix);
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _additionalPhoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _enforcePrimaryPhonePrefix() {
    final normalized = _normalizeKenyaPhoneInput(_phoneController.text);
    if (_phoneController.text == normalized) {
      return;
    }
    _phoneController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  void _enforceOptionalPhonePrefix() {
    final text = _additionalPhoneController.text.trim();
    if (text.isEmpty) {
      return;
    }
    final normalized = _normalizeKenyaPhoneInput(text);
    if (_additionalPhoneController.text == normalized) {
      return;
    }
    _additionalPhoneController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  String _normalizeKenyaPhoneInput(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('254')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '$_kenyaPrefix$digits';
  }

  bool _isValidKenyaPhone(String value) {
    return RegExp(r'^\+254\d{9}$').hasMatch(value);
  }

  Future<void> _openLegalDoc(LegalDocumentType type) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TermsAndPrivacyScreen(documentType: type),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .registerIndividual(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
            phoneNumber: _phoneController.text.trim(),
            additionalPhoneNumber: _additionalPhoneController.text.trim(),
            counselorRegistrationIntent: _isCounselorIntent,
          );
      if (!mounted) {
        return;
      }
      context.go(_routeWithCurrentContext(AppRoute.verifyEmail));
    } on FirebaseAuthException catch (error) {
      _showMessage(error.message ?? 'Registration failed.');
    } catch (error) {
      _showMessage(error.toString());
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _isSubmitting
                    ? null
                    : () => context.go(
                        _hasInviteContext
                            ? AppRoute.withInviteQuery(
                                AppRoute.login,
                                _inviteQuery,
                              )
                            : _routeWithCurrentContext(AppRoute.register),
                      ),
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
                        'Back',
                        style: TextStyle(
                          color: Color(0xFF93A3BA),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isCounselorIntent
                  ? 'Create your counselor account'
                  : 'Create your account',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF071937),
                letterSpacing: -0.5,
                fontSize: 48 / 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _hasInviteContext
                  ? 'Register with the invited email, then accept your invite instantly.'
                  : _isCounselorIntent
                  ? 'After verification, you will wait for an institution admin invite and skip basic onboarding questions.'
                  : 'You can join your institution later from Home using a join code.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF516784),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_hasInviteContext) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFFFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFB3ECDD)),
                ),
                child: Text(
                  'Invite: ${(widget.intendedRole ?? '').trim().isNotEmpty ? widget.intendedRole!.trim() : 'member'}${(widget.institutionName ?? '').trim().isNotEmpty ? ' at ${widget.institutionName!.trim()}' : ''}',
                  style: const TextStyle(
                    color: Color(0xFF0D6F69),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            const _FieldLabel(text: 'FULL NAME'),
            const SizedBox(height: 8),
            _RoundedInput(
              child: TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Alex Rivera',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) {
                  if ((value ?? '').trim().length < 2) {
                    return 'Enter your full name.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 18),
            const _FieldLabel(text: 'EMAIL ADDRESS'),
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
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 18),
            const _FieldLabel(text: 'MOBILE NUMBER'),
            const SizedBox(height: 8),
            _RoundedInput(
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '+254712345678',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
                validator: (value) {
                  final normalized = _normalizeKenyaPhoneInput(value ?? '');
                  if (!_isValidKenyaPhone(normalized)) {
                    return 'Enter a valid mobile number (example: +254712345678).';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 18),
            const _FieldLabel(text: 'ADDITIONAL MOBILE (OPTIONAL)'),
            const SizedBox(height: 8),
            _RoundedInput(
              child: TextFormField(
                controller: _additionalPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '+2547...',
                  prefixIcon: Icon(Icons.phone_android_rounded),
                ),
                validator: (value) {
                  final trimmed = (value ?? '').trim();
                  if (trimmed.isEmpty || trimmed == _kenyaPrefix) {
                    return null;
                  }
                  final normalized = _normalizeKenyaPhoneInput(trimmed);
                  if (!_isValidKenyaPhone(normalized)) {
                    return 'Use +254 format for additional mobile.';
                  }
                  if (normalized == _phoneController.text.trim()) {
                    return 'Additional mobile must differ from primary mobile.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 18),
            const _FieldLabel(text: 'PASSWORD'),
            const SizedBox(height: 8),
            _RoundedInput(
              child: TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '••••••••',
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
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFFFFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFB3ECDD)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF0E9B90),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      children: [
                        const Text(
                          'By joining, you agree to our ',
                          style: TextStyle(
                            color: Color(0xFF0D6F69),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        GestureDetector(
                          onTap: () =>
                              _openLegalDoc(LegalDocumentType.termsOfService),
                          child: const Text(
                            'Terms of Service',
                            style: TextStyle(
                              color: Color(0xFF0A6D66),
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Text(
                          ' and ',
                          style: TextStyle(
                            color: Color(0xFF0D6F69),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        GestureDetector(
                          onTap: () =>
                              _openLegalDoc(LegalDocumentType.privacyPolicy),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: Color(0xFF0A6D66),
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Text(
                          '. MindNest is not a substitute for professional medical advice.',
                          style: TextStyle(
                            color: Color(0xFF0D6F69),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
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
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    _isSubmitting ? 'Creating...' : 'Create Account  ->',
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
            if (_hasInviteContext)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => context.go(
                          AppRoute.withInviteQuery(
                            AppRoute.login,
                            _inviteQuery,
                          ),
                        ),
                  child: const Text('Already have an account? Log in instead'),
                ),
              ),
          ],
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
