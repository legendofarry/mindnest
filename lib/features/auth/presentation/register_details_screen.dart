import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
      await syncAuthSessionState(ref);
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
    final screenSize = MediaQuery.sizeOf(context);
    final isWindowsDesktop =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        screenSize.width >= 1180;
    final isCompactDesktopHeight = screenSize.height < 950;
    final breadcrumbItems = <_BreadcrumbItem>[
      _BreadcrumbItem(
        label: _hasInviteContext ? 'Invitation' : 'Account type',
        route: AppRoute.register,
        icon: _hasInviteContext
            ? Icons.mark_email_unread_outlined
            : Icons.account_tree_outlined,
      ),
      _BreadcrumbItem(
        label: 'Your details',
        icon: _hasInviteContext
            ? Icons.person_add_alt_1_rounded
            : _isCounselorIntent
            ? Icons.psychology_alt_outlined
            : Icons.badge_outlined,
      ),
    ];
    final trailingLabel = _hasInviteContext
        ? 'Step 2 of 2'
        : _isCounselorIntent
        ? 'Counselor sign up'
        : 'Step 2 of 2';
    final formContent = _buildRegisterDetailsForm(
      context: context,
      isDesktop: isWindowsDesktop,
      isCompactDesktopHeight: isCompactDesktopHeight,
      breadcrumbItems: breadcrumbItems,
      trailingLabel: trailingLabel,
    );

    if (isWindowsDesktop) {
      return AuthBackgroundScaffold(
        maxWidth: 1360,
        scrollable: false,
        child: _DesktopRegisterDetailsLayout(
          supportPanel: _DesktopRegisterDetailsSupportPanel(
            hasInviteContext: _hasInviteContext,
            isCounselorIntent: _isCounselorIntent,
            institutionName: widget.institutionName,
            compact: isCompactDesktopHeight,
          ),
          formPanel: _DesktopRegisterDetailsFormCard(
            compact: isCompactDesktopHeight,
            child: formContent,
          ),
        ),
      );
    }

    return AuthBackgroundScaffold(maxWidth: 430, child: formContent);
  }

  Widget _buildRegisterDetailsForm({
    required BuildContext context,
    required bool isDesktop,
    required bool isCompactDesktopHeight,
    required List<_BreadcrumbItem> breadcrumbItems,
    required String trailingLabel,
  }) {
    final canSubmit = _canSubmit;
    final fieldGap = isDesktop ? 14.0 : 18.0;
    final pairGap = isDesktop ? 10.0 : 12.0;
    final submitGap = isDesktop ? 18.0 : 22.0;

    return Form(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop) ...[
            _AuthBreadcrumb(
              items: breadcrumbItems,
              onTapRoute: (route) => context.go(route),
              trailingLabel: trailingLabel,
            ),
            SizedBox(height: isCompactDesktopHeight ? 14 : 18),
          ],
          _buildFormHeader(context: context, isDesktop: isDesktop),
          _buildFormErrorBanner(isDesktop: isDesktop),
          if (_hasInviteContext) ...[
            const SizedBox(height: 8),
            _buildInviteSummaryBanner(),
          ],
          SizedBox(height: isDesktop ? 18 : 28),
          _buildNameField(),
          SizedBox(height: fieldGap),
          _buildEmailField(),
          SizedBox(height: fieldGap),
          _buildPhoneAndPasswordRows(fieldGap: fieldGap, pairGap: pairGap),
          SizedBox(height: fieldGap),
          _buildTermsCard(),
          SizedBox(height: submitGap),
          _buildSubmitButton(canSubmit: canSubmit, isDesktop: isDesktop),
          if (_hasInviteContext) ...[
            const SizedBox(height: 6),
            _buildExistingAccountLink(context),
          ],
        ],
      ),
    );
  }

  Widget _buildFormHeader({
    required BuildContext context,
    required bool isDesktop,
  }) {
    final subtitle = _hasInviteContext
        ? 'Use the invited email to finish setup.'
        : _isCounselorIntent
        ? 'Use the details you will sign in with after approval.'
        : 'Use the details you will sign in with.';

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
            fontSize: isDesktop ? 22 : 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF516784),
            fontWeight: FontWeight.w500,
            fontSize: isDesktop ? 15 : null,
          ),
        ),
      ],
    );
  }

  Widget _buildFormErrorBanner({required bool isDesktop}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: (_formError == null || _formError!.trim().isEmpty)
          ? SizedBox(height: isDesktop ? 6 : 12)
          : Container(
              key: ValueKey(_formError),
              margin: EdgeInsets.only(top: isDesktop ? 12 : 14, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    );
  }

  Widget _buildInviteSummaryBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              hintText: '',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    );
  }

  Widget _buildPhoneAndPasswordRows({
    required double fieldGap,
    required double pairGap,
  }) {
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
                _confirmPasswordController.text != _passwordController.text;
            _formError = null;
          }),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: '***',
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _isPasswordVisible = !_isPasswordVisible),
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
                _confirmPasswordController.text != _passwordController.text;
            _formError = null;
          }),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: '***',
            suffixIcon: IconButton(
              onPressed: () => setState(
                () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
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
            SizedBox(width: pairGap),
            Expanded(child: additionalPhoneField),
          ],
        ),
        SizedBox(height: fieldGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: passwordField),
            SizedBox(width: pairGap),
            Expanded(child: confirmPasswordField),
          ],
        ),
      ],
    );
  }

  Widget _buildTermsCard() {
    return Container(
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
            child: Icon(Icons.info_outline_rounded, color: Color(0xFF0E9B90)),
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
                  onTap: () => _openLegalDoc(LegalDocumentType.termsOfService),
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
                  onTap: () => _openLegalDoc(LegalDocumentType.privacyPolicy),
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
    );
  }

  Widget _buildSubmitButton({
    required bool canSubmit,
    required bool isDesktop,
  }) {
    return Container(
      height: isDesktop ? 58 : 62,
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
          child: _isSubmitting
              ? const Text(
                  'Creating...',
                  key: ValueKey('register-details-busy'),
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                )
              : Row(
                  key: const ValueKey('register-details-ready'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildExistingAccountLink(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: TextButton(
        onPressed: _isSubmitting
            ? null
            : () => context.go(
                AppRoute.withInviteQuery(AppRoute.login, _inviteQuery),
              ),
        child: const Text('Already have an account? Log in instead'),
      ),
    );
  }
}

class _DesktopRegisterDetailsLayout extends StatelessWidget {
  const _DesktopRegisterDetailsLayout({
    required this.supportPanel,
    required this.formPanel,
  });

  final Widget supportPanel;
  final Widget formPanel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 5, child: supportPanel),
        const SizedBox(width: 34),
        Expanded(
          flex: 4,
          child: Align(alignment: Alignment.centerRight, child: formPanel),
        ),
      ],
    );
  }
}

class _DesktopRegisterDetailsFormCard extends StatelessWidget {
  const _DesktopRegisterDetailsFormCard({
    required this.child,
    required this.compact,
  });

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 600 : 620),
      child: Container(
        padding: EdgeInsets.fromLTRB(28, compact ? 24 : 28, 28, 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFD6E7EE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 32,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DesktopRegisterDetailsSupportPanel extends StatelessWidget {
  const _DesktopRegisterDetailsSupportPanel({
    required this.hasInviteContext,
    required this.isCounselorIntent,
    required this.institutionName,
    required this.compact,
  });

  final bool hasInviteContext;
  final bool isCounselorIntent;
  final String? institutionName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final headline = hasInviteContext
        ? 'Finish your invited sign up in one safe step.'
        : isCounselorIntent
        ? 'Set up your counselor account, then wait for approval.'
        : 'Finish your details and join your institution faster.';
    final description = hasInviteContext
        ? 'Use the invited email, verify it, and return to MindNest to enter your workspace.'
        : isCounselorIntent
        ? 'After email verification, an institution admin can invite you into the counselor workspace.'
        : 'You are on the last account step. After email verification, you can continue into onboarding and your institution workspace.';
    final accentIcon = hasInviteContext
        ? Icons.mark_email_unread_outlined
        : isCounselorIntent
        ? Icons.psychology_alt_outlined
        : Icons.badge_outlined;
    final chips = hasInviteContext
        ? const [
            _DesktopSupportChipData(
              label: 'Invited email',
              icon: Icons.mail_outline_rounded,
            ),
            _DesktopSupportChipData(
              label: 'New password',
              icon: Icons.password_rounded,
            ),
            _DesktopSupportChipData(
              label: 'Email verification',
              icon: Icons.verified_user_outlined,
            ),
          ]
        : isCounselorIntent
        ? const [
            _DesktopSupportChipData(
              label: 'Full name',
              icon: Icons.person_outline_rounded,
            ),
            _DesktopSupportChipData(
              label: 'Phone number',
              icon: Icons.phone_rounded,
            ),
            _DesktopSupportChipData(
              label: 'Approval invite',
              icon: Icons.mark_email_read_outlined,
            ),
          ]
        : const [
            _DesktopSupportChipData(
              label: 'Full name',
              icon: Icons.person_outline_rounded,
            ),
            _DesktopSupportChipData(
              label: 'Email address',
              icon: Icons.mail_outline_rounded,
            ),
            _DesktopSupportChipData(
              label: 'Mobile number',
              icon: Icons.phone_rounded,
            ),
          ];
    final steps = hasInviteContext
        ? [
            _DesktopSupportStepData(
              title: 'Create the account',
              description:
                  'Use the same invited email so MindNest can match the invitation automatically.',
            ),
            _DesktopSupportStepData(
              title: 'Verify your email',
              description:
                  'Open the verification email we send you, then come back to the app.',
            ),
            _DesktopSupportStepData(
              title: 'Accept the workspace invite',
              description: (institutionName ?? '').trim().isEmpty
                  ? 'Once you sign in, you can accept the invitation and enter the workspace.'
                  : 'Once you sign in, you can join ${(institutionName ?? '').trim()}.',
            ),
          ]
        : isCounselorIntent
        ? const [
            _DesktopSupportStepData(
              title: 'Enter your account details',
              description:
                  'Use the email and phone number you will use for sign-in and follow-up communication.',
            ),
            _DesktopSupportStepData(
              title: 'Verify your email',
              description:
                  'We send a verification email before you continue into the app.',
            ),
            _DesktopSupportStepData(
              title: 'Wait for an institution invite',
              description:
                  'An admin invites you into the counselor workspace after approval.',
            ),
          ]
        : const [
            _DesktopSupportStepData(
              title: 'Create your account',
              description:
                  'Enter the details you want to use when signing in to MindNest.',
            ),
            _DesktopSupportStepData(
              title: 'Verify your email',
              description:
                  'Open the verification email we send you before continuing.',
            ),
            _DesktopSupportStepData(
              title: 'Continue into onboarding',
              description:
                  'After verification, you can finish setup and enter your institution workspace.',
            ),
          ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DesktopSupportOverviewCard(
          eyebrow: hasInviteContext
              ? 'Invitation'
              : isCounselorIntent
              ? 'Counselor sign up'
              : 'Final step',
          title: headline,
          description: description,
          icon: accentIcon,
          compact: compact,
          chips: chips,
        ),
        SizedBox(height: compact ? 16 : 18),
        _DesktopSupportStepsCard(
          title: 'What happens next',
          steps: steps,
          compact: compact,
        ),
      ],
    );
  }
}

class _DesktopSupportOverviewCard extends StatelessWidget {
  const _DesktopSupportOverviewCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.compact,
    required this.chips,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final bool compact;
  final List<_DesktopSupportChipData> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, compact ? 22 : 24, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFD8E7EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        color: Color(0xFF0E9B90),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFF0F172A),
                        fontSize: compact ? 28 : 32,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: TextStyle(
                        color: const Color(0xFF516784),
                        fontSize: compact ? 14 : 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Container(
                width: compact ? 92 : 104,
                height: compact ? 92 : 104,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0E9B90), Color(0xFF6DE3D9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x320E9B90),
                      blurRadius: 26,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: compact ? 40 : 44),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final chip in chips)
                _DesktopSupportChip(label: chip.label, icon: chip.icon),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopSupportStepsCard extends StatelessWidget {
  const _DesktopSupportStepsCard({
    required this.title,
    required this.steps,
    required this.compact,
  });

  final String title;
  final List<_DesktopSupportStepData> steps;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, compact ? 20 : 22, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFD8E7EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: compact ? 14 : 16),
          for (var index = 0; index < steps.length; index++) ...[
            _DesktopSupportStepRow(
              number: '${index + 1}',
              title: steps[index].title,
              description: steps[index].description,
              compact: compact,
            ),
            if (index < steps.length - 1) SizedBox(height: compact ? 12 : 14),
          ],
        ],
      ),
    );
  }
}

class _DesktopSupportStepRow extends StatelessWidget {
  const _DesktopSupportStepRow({
    required this.number,
    required this.title,
    required this.description,
    required this.compact,
  });

  final String number;
  final String title;
  final String description;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 34 : 38,
          height: compact ? 34 : 38,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F7F4),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFF0D6F69),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: const Color(0xFF0F172A),
                  fontSize: compact ? 16 : 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: const Color(0xFF516784),
                  fontSize: compact ? 13 : 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopSupportChip extends StatelessWidget {
  const _DesktopSupportChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FAFD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E7EE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0E9B90)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF16324F),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSupportChipData {
  const _DesktopSupportChipData({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _DesktopSupportStepData {
  const _DesktopSupportStepData({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
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
          color: hasError
              ? const Color.fromARGB(255, 255, 90, 109)
              : const Color(0xFFD2DCE9),
          width: hasError ? 2.2 : 1.0,
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

/*
class _LegacyBreadcrumbItem {
  const _LegacyBreadcrumbItem({required this.label, this.route});

  final String label;
  final String? route;
}

class _LegacyAuthBreadcrumb extends StatelessWidget {
  const _LegacyAuthBreadcrumb({required this.items, this.onTapRoute});

  final List<_LegacyBreadcrumbItem> items;
  final void Function(String route)? onTapRoute;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: const Color(0xFF4A607C),
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (items[i].route != null && onTapRoute != null)
            GestureDetector(
              onTap: () => onTapRoute?.call(items[i].route!),
              child: Text(
                items[i].label,
                style: baseStyle?.copyWith(
                  color: const Color(0xFF0E9B90),
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            Text(
              items[i].label,
              style: baseStyle?.copyWith(fontWeight: FontWeight.w800),
            ),
          if (i < items.length - 1)
            const Text(
              '›',
              style: TextStyle(
                color: Color(0xFF9AAAC0),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
        ],
      ],
    );
  }
}

*/

class _BreadcrumbItem {
  const _BreadcrumbItem({required this.label, this.route, this.icon});

  final String label;
  final String? route;
  final IconData? icon;
}

class _AuthBreadcrumb extends StatelessWidget {
  const _AuthBreadcrumb({
    required this.items,
    this.onTapRoute,
    this.trailingLabel,
  });

  final List<_BreadcrumbItem> items;
  final void Function(String route)? onTapRoute;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD5E6EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _BreadcrumbChip(
                    item: items[i],
                    isActive: i == items.length - 1,
                    onTap: items[i].route != null && onTapRoute != null
                        ? () => onTapRoute?.call(items[i].route!)
                        : null,
                  ),
                  if (i < items.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF9AAAC0),
                        size: 18,
                      ),
                    ),
                ],
              ],
            ),
          ),
          if ((trailingLabel ?? '').trim().isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F7F4),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFC0EBE4)),
              ),
              child: Text(
                trailingLabel!,
                style: const TextStyle(
                  color: Color(0xFF0D6F69),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreadcrumbChip extends StatefulWidget {
  const _BreadcrumbChip({
    required this.item,
    required this.isActive,
    this.onTap,
  });

  final _BreadcrumbItem item;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  State<_BreadcrumbChip> createState() => _BreadcrumbChipState();
}

class _BreadcrumbChipState extends State<_BreadcrumbChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isClickable = widget.onTap != null;
    final showHoverState = isClickable && _isHovered && !widget.isActive;
    final backgroundColor = widget.isActive
        ? const Color(0xFF0F172A)
        : showHoverState
        ? const Color(0xFFEAF8F5)
        : const Color(0xFFF5FAFD);
    final borderColor = widget.isActive
        ? const Color(0xFF16213A)
        : showHoverState
        ? const Color(0xFF8FDED4)
        : const Color(0xFFD6E4EF);
    final foregroundColor = widget.isActive
        ? Colors.white
        : showHoverState
        ? const Color(0xFF0B6E67)
        : const Color(0xFF16324F);
    final iconColor = widget.isActive
        ? const Color(0xFF9EF2E8)
        : showHoverState
        ? const Color(0xFF0A9388)
        : const Color(0xFF0E9B90);

    return Material(
      color: Colors.transparent,
      child: MouseRegion(
        opaque: true,
        cursor: isClickable
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: isClickable ? (_) => setState(() => _isHovered = true) : null,
        onExit: isClickable ? (_) => setState(() => _isHovered = false) : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          scale: showHoverState ? 1.01 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, showHoverState ? -2 : 0, 0),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(18),
              hoverColor: Colors.transparent,
              splashColor: const Color(0x120E9B90),
              highlightColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                  boxShadow: widget.isActive || showHoverState
                      ? [
                          BoxShadow(
                            color: showHoverState
                                ? const Color(0x1F0E9B90)
                                : const Color(0x120F172A),
                            blurRadius: showHoverState ? 18 : 12,
                            offset: Offset(0, showHoverState ? 10 : 6),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.item.icon != null) ...[
                      Icon(widget.item.icon, size: 16, color: iconColor),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.item.label,
                      style: TextStyle(
                        color: foregroundColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
