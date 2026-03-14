import 'dart:async';

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
  static const _primaryDuplicateMessage =
      'This mobile number is already linked to another account.';
  static const _additionalDuplicateMessage =
      'This additional mobile is already linked to another account.';

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _additionalPhoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _additionalPhoneFocusNode = FocusNode();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _nameFieldError = false;
  bool _emailFieldError = false;
  bool _phoneFieldError = false;
  bool _additionalPhoneFieldError = false;
  bool _passwordFieldError = false;
  bool _confirmPasswordFieldError = false;

  String? _phoneDuplicateError;
  String? _additionalPhoneDuplicateError;
  String? _formError;

  int _phoneCheckToken = 0;
  int _additionalPhoneCheckToken = 0;

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

  bool get _isFormStructurallyValid {
    final hasName = _nameController.text.trim().length >= 2;
    final email = _emailController.text.trim();
    final hasEmail = email.isNotEmpty && email.contains('@');

    final primaryPhone = _normalizeKenyaPhoneInput(_phoneController.text);
    final hasPhone = _isValidKenyaPhone(primaryPhone);

    final additionalRaw = _additionalPhoneController.text.trim();
    final hasAdditional =
        additionalRaw.isNotEmpty && additionalRaw != _kenyaPrefix;
    final additionalPhone = hasAdditional
        ? _normalizeKenyaPhoneInput(additionalRaw)
        : null;
    final hasValidAdditional =
        additionalPhone == null || _isValidKenyaPhone(additionalPhone);
    final hasDistinctAdditional =
        additionalPhone == null || additionalPhone != primaryPhone;

    final hasPassword = _passwordController.text.length >= 8;
    final hasMatchingPassword =
        _confirmPasswordController.text == _passwordController.text;

    return hasName &&
        hasEmail &&
        hasPhone &&
        hasValidAdditional &&
        hasDistinctAdditional &&
        hasPassword &&
        hasMatchingPassword;
  }

  bool get _canSubmit {
    return !_isSubmitting &&
        _isFormStructurallyValid &&
        _phoneDuplicateError == null &&
        _additionalPhoneDuplicateError == null;
  }

  @override
  void initState() {
    super.initState();
    _isPasswordVisible = false;
    _isConfirmPasswordVisible = false;
    _phoneController.text = _kenyaPrefix;
    _phoneController.addListener(_enforcePrimaryPhonePrefix);
    _additionalPhoneController.addListener(_enforceOptionalPhonePrefix);
    _phoneFocusNode.addListener(_onPrimaryPhoneFocusChange);
    _additionalPhoneFocusNode.addListener(_onAdditionalPhoneFocusChange);

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
    _phoneFocusNode.removeListener(_onPrimaryPhoneFocusChange);
    _additionalPhoneFocusNode.removeListener(_onAdditionalPhoneFocusChange);
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _additionalPhoneController.dispose();
    _phoneFocusNode.dispose();
    _additionalPhoneFocusNode.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  void _onPrimaryPhoneFocusChange() {
    if (_phoneFocusNode.hasFocus) {
      return;
    }
    unawaited(_checkPrimaryPhoneDuplicate());
  }

  void _onAdditionalPhoneFocusChange() {
    if (_additionalPhoneFocusNode.hasFocus) {
      return;
    }
    unawaited(_checkAdditionalPhoneDuplicate());
  }

  Future<void> _checkPrimaryPhoneDuplicate() async {
    final normalized = _normalizeKenyaPhoneInput(_phoneController.text);
    if (!_isValidKenyaPhone(normalized)) {
      if (_phoneDuplicateError != null || _phoneFieldError) {
        setState(() {
          _phoneDuplicateError = null;
          _phoneFieldError = false;
        });
      }
      return;
    }

    final token = ++_phoneCheckToken;
    try {
      final isAvailable = await ref
          .read(authRepositoryProvider)
          .isPhoneNumberAvailableForRegistration(normalized);
      if (!mounted || token != _phoneCheckToken) {
        return;
      }
      setState(() {
        _phoneDuplicateError = isAvailable ? null : _primaryDuplicateMessage;
        _phoneFieldError = !isAvailable;
        if (!isAvailable) {
          _formError = _primaryDuplicateMessage;
        } else if (_formError == _primaryDuplicateMessage) {
          _formError = null;
        }
      });
    } catch (_) {
      if (!mounted || token != _phoneCheckToken) {
        return;
      }
      setState(() {
        _phoneDuplicateError = null;
        _phoneFieldError = false;
      });
    }
  }

  Future<void> _checkAdditionalPhoneDuplicate() async {
    final trimmed = _additionalPhoneController.text.trim();
    if (trimmed.isEmpty || trimmed == _kenyaPrefix) {
      if (_additionalPhoneDuplicateError != null ||
          _additionalPhoneFieldError) {
        setState(() {
          _additionalPhoneDuplicateError = null;
          _additionalPhoneFieldError = false;
          if (_formError == _additionalDuplicateMessage) {
            _formError = null;
          }
        });
      }
      return;
    }

    final normalized = _normalizeKenyaPhoneInput(trimmed);
    final primaryPhone = _normalizeKenyaPhoneInput(_phoneController.text);
    if (!_isValidKenyaPhone(normalized) || normalized == primaryPhone) {
      if (_additionalPhoneDuplicateError != null ||
          _additionalPhoneFieldError) {
        setState(() {
          _additionalPhoneDuplicateError = null;
          _additionalPhoneFieldError = false;
        });
      }
      return;
    }

    final token = ++_additionalPhoneCheckToken;
    try {
      final isAvailable = await ref
          .read(authRepositoryProvider)
          .isPhoneNumberAvailableForRegistration(normalized);
      if (!mounted || token != _additionalPhoneCheckToken) {
        return;
      }
      setState(() {
        _additionalPhoneDuplicateError = isAvailable
            ? null
            : _additionalDuplicateMessage;
        _additionalPhoneFieldError = !isAvailable;
        if (!isAvailable) {
          _formError = _additionalDuplicateMessage;
        } else if (_formError == _additionalDuplicateMessage) {
          _formError = null;
        }
      });
    } catch (_) {
      if (!mounted || token != _additionalPhoneCheckToken) {
        return;
      }
      setState(() {
        _additionalPhoneDuplicateError = null;
        _additionalPhoneFieldError = false;
      });
    }
  }

  Future<bool> _runPhoneDuplicationChecksBeforeSubmit() async {
    await _checkPrimaryPhoneDuplicate();
    await _checkAdditionalPhoneDuplicate();
    return _phoneDuplicateError != null ||
        _additionalPhoneDuplicateError != null;
  }

  Future<void> _openLegalDoc(LegalDocumentType type) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TermsAndPrivacyScreen(documentType: type),
      ),
    );
  }

  bool _validateBeforeSubmit() {
    final hasName = _nameController.text.trim().length >= 2;
    final email = _emailController.text.trim();
    final hasEmail = email.isNotEmpty && email.contains('@');

    final primaryPhone = _normalizeKenyaPhoneInput(_phoneController.text);
    final hasPhone = _isValidKenyaPhone(primaryPhone);

    final additionalRaw = _additionalPhoneController.text.trim();
    final hasAdditional =
        additionalRaw.isNotEmpty && additionalRaw != _kenyaPrefix;
    final additionalPhone = hasAdditional
        ? _normalizeKenyaPhoneInput(additionalRaw)
        : null;
    final hasValidAdditional =
        additionalPhone == null || _isValidKenyaPhone(additionalPhone);
    final hasDistinctAdditional =
        additionalPhone == null || additionalPhone != primaryPhone;

    final hasPassword = _passwordController.text.length >= 8;
    final hasMatchingPassword =
        _confirmPasswordController.text == _passwordController.text;
    final hasDuplicatePrimary = _phoneDuplicateError != null;
    final hasDuplicateAdditional = _additionalPhoneDuplicateError != null;

    setState(() {
      _nameFieldError = !hasName;
      _emailFieldError = !hasEmail;
      _phoneFieldError = !hasPhone || hasDuplicatePrimary;
      _additionalPhoneFieldError =
          !hasValidAdditional ||
          !hasDistinctAdditional ||
          hasDuplicateAdditional;
      _passwordFieldError = !hasPassword;
      _confirmPasswordFieldError = !hasMatchingPassword;
    });

    if (!hasName ||
        !hasEmail ||
        !hasPhone ||
        !hasValidAdditional ||
        !hasDistinctAdditional ||
        !hasPassword ||
        !hasMatchingPassword) {
      setState(() {
        _formError = 'Please correct the highlighted fields.';
      });
      return false;
    }

    if (hasDuplicatePrimary || hasDuplicateAdditional) {
      setState(() {
        _formError =
            _phoneDuplicateError ??
            _additionalPhoneDuplicateError ??
            'A mobile number is already linked to another account.';
      });
      return false;
    }

    return true;
  }

  Future<void> _submit() async {
    if (!_validateBeforeSubmit()) {
      return;
    }

    setState(() => _isSubmitting = true);

    final hasDuplicatePhone = await _runPhoneDuplicationChecksBeforeSubmit();
    if (!mounted) {
      return;
    }

    if (hasDuplicatePhone || !_validateBeforeSubmit()) {
      setState(() => _isSubmitting = false);
      return;
    }

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
      setState(() {
        _formError = error.message ?? 'Registration failed.';
      });
    } catch (error) {
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
    final canSubmit = _canSubmit;

    return AuthBackgroundScaffold(
      child: Form(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final subtitle = _hasInviteContext
                    ? 'Register with the invited email, then accept your invite instantly.'
                    : _isCounselorIntent
                    ? 'After verification, you will wait for an institution admin invite and skip basic onboarding questions.'
                    : '';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isCounselorIntent
                          ? 'Create your counselor account'
                          : 'Create your account',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF071937),
                        letterSpacing: -0.5,
                        fontSize: 24,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF516784),
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ],
                );
              },
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: (_formError == null || _formError!.trim().isEmpty)
                  ? const SizedBox(height: 12)
                  : Container(
                      key: ValueKey(_formError),
                      margin: const EdgeInsets.only(top: 14, bottom: 8),
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
            if (_hasInviteContext) ...[
              const SizedBox(height: 4),
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
              hasError: _nameFieldError,
              child: TextFormField(
                controller: _nameController,
                onChanged: (_) => setState(() {
                  _nameFieldError = false;
                  _formError = null;
                }),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Alex Rivera',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _FieldLabel(text: 'EMAIL ADDRESS'),
            const SizedBox(height: 8),
            _RoundedInput(
              hasError: _emailFieldError,
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {
                  _emailFieldError = false;
                  _formError = null;
                }),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'alex@example.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final primaryPhoneField = _LabeledFieldBlock(
                  label: 'MOBILE NUMBER',
                  child: _RoundedInput(
                    hasError: _phoneFieldError || _phoneDuplicateError != null,
                    child: TextFormField(
                      controller: _phoneController,
                      focusNode: _phoneFocusNode,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {
                        _phoneFieldError = false;
                        _phoneDuplicateError = null;
                        _formError = null;
                      }),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '+2547..',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                    ),
                  ),
                );

                final additionalPhoneField = _LabeledFieldBlock(
                  label: 'OTHER MOBILE',
                  child: _RoundedInput(
                    hasError:
                        _additionalPhoneFieldError ||
                        _additionalPhoneDuplicateError != null,
                    child: TextFormField(
                      controller: _additionalPhoneController,
                      focusNode: _additionalPhoneFocusNode,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {
                        _additionalPhoneFieldError = false;
                        _additionalPhoneDuplicateError = null;
                        _formError = null;
                      }),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '+2547..',
                        prefixIcon: Icon(Icons.phone_android_rounded),
                      ),
                    ),
                  ),
                );

                final passwordField = _LabeledFieldBlock(
                  label: 'PASSWORD',
                  child: _RoundedInput(
                    hasError: _passwordFieldError,
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      onChanged: (_) => setState(() {
                        _passwordFieldError = false;
                        _confirmPasswordFieldError =
                            _confirmPasswordController.text.isNotEmpty &&
                            _confirmPasswordController.text !=
                                _passwordController.text;
                        _formError = null;
                      }),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '***',
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible,
                          ),
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                final confirmPasswordField = _LabeledFieldBlock(
                  label: 'CONFIRM',
                  child: _RoundedInput(
                    hasError: _confirmPasswordFieldError,
                    child: TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      onChanged: (_) => setState(() {
                        _confirmPasswordFieldError =
                            _confirmPasswordController.text.isNotEmpty &&
                            _confirmPasswordController.text !=
                                _passwordController.text;
                        _formError = null;
                      }),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '***',
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible,
                          ),
                          icon: Icon(
                            _isConfirmPasswordVisible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: primaryPhoneField),
                        const SizedBox(width: 12),
                        Expanded(child: additionalPhoneField),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: passwordField),
                        const SizedBox(width: 12),
                        Expanded(child: confirmPasswordField),
                      ],
                    ),
                  ],
                );
              },
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
                gradient: LinearGradient(
                  colors: canSubmit
                      ? const [Color(0xFF0E9B90), Color(0xFF18A89D)]
                      : const [Color(0xFFB8C5D6), Color(0xFFAAB8CB)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: canSubmit
                    ? const [
                        BoxShadow(
                          color: Color(0x4D72ECDC),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ]
                    : const [],
              ),
              child: ElevatedButton(
                onPressed: canSubmit ? _submit : null,
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
                      fontSize: 17.5,
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

class _LabeledFieldBlock extends StatelessWidget {
  const _LabeledFieldBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _RoundedInput extends StatelessWidget {
  const _RoundedInput({required this.child, this.hasError = false});

  final Widget child;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasError ? const Color(0xFFFECDD3) : const Color(0xFFD2DCE9),
          width: hasError ? 1.2 : 1.0,
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
