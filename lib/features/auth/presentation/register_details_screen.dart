import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';
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
  static const _desktopBreakpoint = 1100.0;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _nameFieldError = false;
  bool _emailFieldError = false;
  bool _passwordFieldError = false;
  bool _confirmPasswordFieldError = false;
  String? _formError;

  bool _isValidEmail(String raw) {
    final email = raw.trim();
    if (email.isEmpty) {
      return false;
    }
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  String? get _firstBlockingIssue {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (name.isEmpty) {
      return 'Enter your full name.';
    }
    if (name.length < 2) {
      return 'Full name must be at least 2 characters.';
    }
    if (email.isEmpty) {
      return 'Enter your email address.';
    }
    if (!_isValidEmail(email)) {
      return 'Enter a valid email address (example: name@example.com).';
    }
    if (password.isEmpty) {
      return 'Enter a password.';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (confirm.isEmpty) {
      return 'Confirm your password.';
    }
    if (confirm != password) {
      return 'Password confirmation does not match.';
    }
    return null;
  }

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
    final hasEmail = _isValidEmail(_emailController.text);

    final hasPassword = _passwordController.text.length >= 8;
    final hasMatchingPassword =
        _confirmPasswordController.text == _passwordController.text;

    return hasName && hasEmail && hasPassword && hasMatchingPassword;
  }

  bool get _canSubmit => !_isSubmitting && _isFormStructurallyValid;

  @override
  void initState() {
    super.initState();
    _isPasswordVisible = false;
    _isConfirmPasswordVisible = false;

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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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
    final hasEmail = _isValidEmail(_emailController.text);

    final hasPassword = _passwordController.text.length >= 8;
    final hasMatchingPassword =
        _confirmPasswordController.text == _passwordController.text;

    setState(() {
      _nameFieldError = !hasName;
      _emailFieldError = !hasEmail;
      _passwordFieldError = !hasPassword;
      _confirmPasswordFieldError = !hasMatchingPassword;
    });

    if (!hasName || !hasEmail || !hasPassword || !hasMatchingPassword) {
      setState(() {
        _formError = 'Please correct the highlighted fields.';
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

    try {
      await ref
          .read(authRepositoryProvider)
          .registerIndividual(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
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
    final isDesktop = screenSize.width >= _desktopBreakpoint;
    final isCompactDesktopHeight = screenSize.height < 950;
    final formContent = _buildRegisterDetailsForm(
      context: context,
      isDesktop: isDesktop,
      isCompactDesktopHeight: isCompactDesktopHeight,
    );

    if (isDesktop) {
      return AuthDesktopShell(
        heroHighlightText: '',
        heroBaseText: '',
        heroHighlightAfterBase: true,
        heroDescription:
            'Empower your mental well-being with personalized tools, guidance, and community support.',
        heroSupplement: _DesktopRegisterDetailsSupportPanel(
          hasInviteContext: _hasInviteContext,
          isCounselorIntent: _isCounselorIntent,
          institutionName: widget.institutionName,
          compact: isCompactDesktopHeight,
        ),
        formMaxWidth: 600,
        formChild: formContent,
      );
    }

    return AuthBackgroundScaffold(
      maxWidth: double.infinity,
      child: formContent,
    );
  }

  Widget _buildRegisterDetailsForm({
    required BuildContext context,
    required bool isDesktop,
    required bool isCompactDesktopHeight,
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
          _RegisterDetailsBackLink(
            label: _hasInviteContext ? 'Back to invite' : 'Back',
            onTap: () =>
                context.go(_routeWithCurrentContext(AppRoute.register)),
          ),
          SizedBox(height: isDesktop ? (isCompactDesktopHeight ? 14 : 18) : 12),
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
          _buildPasswordRows(pairGap: pairGap),
          SizedBox(height: fieldGap),
          _buildTermsCard(),
          SizedBox(height: submitGap),
          _buildSubmitButton(canSubmit: canSubmit, isDesktop: isDesktop),
          _buildBlockingHint(canSubmit: canSubmit),
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
            fontSize: isDesktop ? 30 : 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF516784),
            fontWeight: FontWeight.w500,
            fontSize: isDesktop ? 16 : null,
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
            onChanged: (value) => setState(() {
              final trimmed = value.trim();
              _nameFieldError = trimmed.isNotEmpty && trimmed.length < 2;
              _formError = null;
            }),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
        ),
        if (_nameFieldError)
          const _FieldErrorText('Full name must be at least 2 characters.'),
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
            onChanged: (value) => setState(() {
              final email = value.trim();
              _emailFieldError = email.isNotEmpty && !_isValidEmail(email);
              _formError = null;
            }),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '...',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
        ),
        if (_emailFieldError)
          const _FieldErrorText(
            'Enter a valid email address (example: name@example.com).',
          ),
      ],
    );
  }

  Widget _buildPasswordRows({required double pairGap}) {
    final passwordField = _LabeledFieldBlock(
      label: 'PASSWORD',
      errorText: _passwordFieldError
          ? 'Password must be at least 8 characters.'
          : null,
      child: _RoundedInput(
        hasError: _passwordFieldError,
        child: TextFormField(
          controller: _passwordController,
          obscureText: !_isPasswordVisible,
          onChanged: (value) => setState(() {
            _passwordFieldError = value.isNotEmpty && value.length < 8;
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
      errorText: _confirmPasswordFieldError
          ? 'Password confirmation does not match.'
          : null,
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
                  '. Teraji is not a substitute for professional medical advice.',
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

  Widget _buildBlockingHint({required bool canSubmit}) {
    if (_isSubmitting || canSubmit) {
      return const SizedBox(height: 0);
    }
    final issue = _firstBlockingIssue;
    if (issue == null) {
      return const SizedBox(height: 0);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Color(0xFF6A7F9B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              issue,
              style: const TextStyle(
                color: Color(0xFF607792),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

class _RegisterDetailsBackLink extends StatefulWidget {
  const _RegisterDetailsBackLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_RegisterDetailsBackLink> createState() =>
      _RegisterDetailsBackLinkState();
}

class _RegisterDetailsBackLinkState extends State<_RegisterDetailsBackLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_hovered ? -2 : 0, 0, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_left_rounded,
                  size: 22,
                  color: _hovered
                      ? const Color(0xFF0E9B90)
                      : const Color(0xFF9AAAC0),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _hovered
                        ? const Color(0xFF0D6F69)
                        : const Color(0xFF9AAAC0),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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
    final title = hasInviteContext
        ? 'Finish sign up in simple steps.'
        : 'Get started in simple steps.';
    final steps = hasInviteContext
        ? [
            _DesktopSupportStepData(
              title: 'Use the invited email',
              description:
                  'Create your account with the same email that received the invitation.',
            ),
            _DesktopSupportStepData(
              title: 'Verify your email',
              description: 'We send a verification email before you continue.',
            ),
            _DesktopSupportStepData(
              title: 'Join the workspace',
              description: (institutionName ?? '').trim().isEmpty
                  ? 'After you sign in, you can accept the invitation and enter your workspace.'
                  : 'After you sign in, you can join ${(institutionName ?? '').trim()}.',
            ),
          ]
        : [
            _DesktopSupportStepData(
              title: 'Choose account type',
              description: isCounselorIntent
                  ? 'You selected counselor, so this form prepares your approval-ready account.'
                  : 'Student and staff accounts use this form to join an institution.',
            ),
            const _DesktopSupportStepData(
              title: 'Enter details',
              description: 'Securely add your name, email, and password.',
            ),
            _DesktopSupportStepData(
              title: isCounselorIntent
                  ? 'Verify and await approval'
                  : 'Verify email',
              description: isCounselorIntent
                  ? 'Confirm via email, then an institution can invite you into the counselor workspace.'
                  : 'Confirm via the link we send to your inbox.',
            ),
          ];

    return Container(
      padding: EdgeInsets.fromLTRB(28, compact ? 24 : 28, 28, 28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD5E8EC)),
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
            hasInviteContext ? 'WHAT HAPPENS NEXT' : 'HOW SIGN UP WORKS',
            style: const TextStyle(
              color: Color(0xFF0E9B90),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontSize: compact ? 23 : 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          SizedBox(height: compact ? 20 : 24),
          for (var index = 0; index < steps.length; index++) ...[
            _DesktopSupportStepRow(
              number: '${index + 1}',
              title: steps[index].title,
              description: steps[index].description,
              compact: compact,
            ),
            if (index < steps.length - 1) SizedBox(height: compact ? 16 : 18),
          ],
        ],
      ),
    );
  }
}

class _DesktopSupportStepData {
  const _DesktopSupportStepData({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
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
            color: const Color(0xFFC6F7EE),
            borderRadius: BorderRadius.circular(999),
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
        const SizedBox(width: 14),
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

/*
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

*/
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
  const _LabeledFieldBlock({
    required this.label,
    required this.child,
    this.errorText,
  });

  final String label;
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 8),
        child,
        if (errorText != null) _FieldErrorText(errorText!),
      ],
    );
  }
}

class _FieldErrorText extends StatelessWidget {
  const _FieldErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7, left: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFC1272D),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
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
