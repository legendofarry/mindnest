// features/auth/presentation/forgot_password_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';
import 'package:mindnest/core/ui/modern_banner.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    this.inviteId,
    this.invitedEmail,
    this.invitedName,
    this.institutionName,
    this.intendedRole,
  });

  final String? inviteId;
  final String? invitedEmail;
  final String? invitedName;
  final String? institutionName;
  final String? intendedRole;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _desktopBreakpoint = 1100.0;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;

  Map<String, String> get _inviteQuery => AppRoute.inviteQuery(
    inviteId: widget.inviteId ?? '',
    invitedEmail: widget.invitedEmail,
    invitedName: widget.invitedName,
    institutionName: widget.institutionName,
    intendedRole: widget.intendedRole,
  );

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordReset(_emailController.text);
      if (mounted) {
        showModernBanner(
          context,
          message: 'Password reset email sent. Check your inbox.',
          icon: Icons.mark_email_read_rounded,
          color: const Color(0xFF0E9B90),
        );
        context.go(AppRoute.withInviteQuery(AppRoute.login, _inviteQuery));
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(error.message ?? 'Unable to send reset email.');
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showModernBanner(
      context,
      message: message,
      icon: Icons.error_outline_rounded,
      color: const Color(0xFFBE123C),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    if (isDesktop) {
      return AuthDesktopShell(
        heroHighlightText: 'Reset your access',
        heroBaseText: 'securely and quickly.',
        heroDescription:
            'Enter your account email and we will send a secure reset link so '
            'you can get back to your wellness workspace.',
        metrics: const [
          AuthDesktopMetric(value: '187+', label: 'USERS HELPED'),
          AuthDesktopMetric(value: '24/7', label: 'SUPPORT READY'),
        ],
        formChild: _buildFormContent(context),
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      child: _buildFormCard(context),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    return Container(
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
      child: _buildFormContent(context),
    );
  }

  Widget _buildFormContent(BuildContext context) {
    return Form(
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
                  : () => context.go(
                      AppRoute.withInviteQuery(AppRoute.login, _inviteQuery),
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
          const SizedBox(height: 24),
          Container(
            width: 10,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F3F1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              color: Color(0xFF0E9B90),
              size: 33,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Forgot Password?',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF071937),
              fontSize: 50 / 2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Enter your email and we\'ll send you a\nlink to reset your password.',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF516784),
              height: 1.4,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFFFFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB3ECDD)),
            ),
            child: const Text(
              "Didn't receive the email? Please check your Spam or Junk folder. "
              "If you find it there, mark it as \"Not Spam\" so future emails arrive in your inbox.",
              style: TextStyle(
                color: Color(0xFF0D6F69),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 20),
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
                  return 'Enter a valid email.';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 28),
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
                duration: const Duration(milliseconds: 200),
                child: Row(
                  key: ValueKey(_isSubmitting),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isSubmitting ? 'Sending...' : 'Send Reset Link',
                      style: const TextStyle(
                        fontSize: 35 / 2,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (!_isSubmitting) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
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
