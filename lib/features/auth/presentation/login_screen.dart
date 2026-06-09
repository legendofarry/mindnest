// features/auth/presentation/login_screen.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/mindnest_logo.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/presentation/login_did_you_know_session.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:passkeys/exceptions.dart' as passkey_exceptions;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
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
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const _lastEmailKey = 'auth.last_email';
  static const _desktopBreakpoint = 1100.0;
  static final Uri _webAppBaseUri = Uri.parse('https://mindnestke.netlify.app');

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _rememberMe = true;
  bool _isSubmitting = false;
  bool _isGoogleSubmitting = false;
  bool _isBiometricScanning = false;
  bool _isPasswordVisible = false;
  bool _showEmailForm = false;
  bool _emailFieldError = false;
  bool _passwordFieldError = false;
  String? _lastEmail;
  String? _formError;
  String? _biometricNotice;

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final Animation<double> _shakeOffset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -14), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -14, end: 14), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 14, end: -10), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 2),
  ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    final invitedEmail = (widget.invitedEmail ?? '').trim().toLowerCase();
    if (invitedEmail.isNotEmpty) {
      _emailController.text = invitedEmail;
    }
    _restoreLastEmail();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _triggerShake() async {
    if (!mounted) {
      return;
    }
    await _shakeController.forward(from: 0);
  }

  void _showStageBanner(
    String message, {
    bool isError = false,
    Duration? autoDismissAfter,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;

    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.fingerprint_rounded;
    final color = isError ? const Color(0xFFBE123C) : const Color(0xFF0E9B90);

    try {
      showModernBanner(
        context,
        message: text,
        icon: icon,
        color: color,
        autoDismissAfter: autoDismissAfter ?? const Duration(seconds: 6),
      );
    } catch (_) {}
  }

  bool get _isBusy => _isSubmitting || _isGoogleSubmitting;
  bool get _isEntryLocked => _isBusy || _isBiometricScanning;
  bool get _isWindowsLoginOnlyMode =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  void _showEmailLogin() {
    if (_isEntryLocked) {
      return;
    }
    setState(() {
      _showEmailForm = true;
      _biometricNotice = null;
    });
  }

  void _showBiometricLogin() {
    if (_isEntryLocked) {
      return;
    }
    setState(() {
      _showEmailForm = false;
      _formError = null;
      _biometricNotice = null;
    });
  }

  String? _passkeyFailureMessage(Object error) {
    if (error is passkey_exceptions.PasskeyAuthCancelledException) {
      return null;
    }
    if (error is passkey_exceptions.NoCredentialsAvailableException) {
      return 'No passkey was found for this browser or device. Use Google or email, or add one in Privacy & Data Controls.';
    }
    if (error is passkey_exceptions.DeviceNotSupportedException ||
        error is passkey_exceptions.PasskeyUnsupportedException) {
      return 'This device does not support passkeys yet. Use Google or email instead.';
    }
    if (error is passkey_exceptions.TimeoutException) {
      return 'The passkey prompt timed out. Please try again.';
    }
    if (error is FirebaseAuthException) {
      return _friendlyLoginErrorMessage(
        error,
        fallback: 'Passkey sign-in failed. Please try again.',
      );
    }

    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return message.isEmpty
        ? 'Passkey sign-in failed. Please try again.'
        : message;
  }

  Future<void> _startPasskeySignIn() async {
    if (_isEntryLocked) {
      return;
    }

    setState(() {
      _formError = null;
      _biometricNotice = 'Checking your passkey...';
      _isBiometricScanning = true;
    });

    try {
      final passkeys = ref.read(passkeyRepositoryProvider);
      final passkeyResult = await passkeys.signIn();
      await ref
          .read(authRepositoryProvider)
          .signInWithCustomToken(
            passkeyResult.customToken,
            rememberMe: _rememberMe,
          );
      await syncAuthSessionState(ref);
      if (!mounted) {
        return;
      }
      final currentEmail =
          ref
              .read(authRepositoryProvider)
              .currentAuthUser
              ?.email
              .trim()
              .toLowerCase() ??
          '';
      if (currentEmail.isNotEmpty) {
        await _saveLastEmail(currentEmail);
      }
      _showStageBanner(
        'Passkey verified. Welcome back.',
        isError: false,
        autoDismissAfter: const Duration(seconds: 4),
      );
    } on passkey_exceptions.PasskeyAuthCancelledException {
      if (mounted) {
        setState(() {
          _isBiometricScanning = false;
          _biometricNotice = null;
        });
      }
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _passkeyFailureMessage(error);
      if (message != null && message.trim().isNotEmpty) {
        setState(() {
          _formError = message;
          _biometricNotice = null;
        });
        _showStageBanner(message, isError: true);
        await _triggerShake();
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _isBiometricScanning = false);
      }
    }
  }

  void _goToSignup() {
    if (_isEntryLocked) {
      return;
    }

    if (_isWindowsLoginOnlyMode) {
      _openSignupOnWeb();
      return;
    }

    context.go(
      _hasInviteContext
          ? AppRoute.withInviteQuery(AppRoute.registerDetails, _inviteQuery)
          : AppRoute.register,
    );
  }

  Future<void> _submit() async {
    if (_isBusy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final emailInvalid = email.isEmpty || !email.contains('@');
    final passwordInvalid = password.isEmpty;

    if (emailInvalid || passwordInvalid) {
      setState(() {
        _emailFieldError = emailInvalid;
        _passwordFieldError = passwordInvalid;
        _formError = 'Please correct the highlighted fields.';
      });
      _showStageBanner(_formError!, isError: true);
      await _triggerShake();
      return;
    }

    final normalizedEmail = email.toLowerCase();
    setState(() {
      _emailFieldError = false;
      _passwordFieldError = false;
      _formError = null;
      _biometricNotice = null;
      _isSubmitting = true;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(
            email: normalizedEmail,
            password: _passwordController.text,
            rememberMe: _rememberMe,
          );
      await syncAuthSessionState(ref);
      if (!mounted) {
        return;
      }
      await _saveLastEmail(normalizedEmail);
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = _friendlyLoginErrorMessage(error);
      });
      _showStageBanner(_formError!, isError: true);
      await _triggerShake();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = error.toString().replaceFirst('Exception: ', '');
      });
      _showStageBanner(_formError!, isError: true);
      await _triggerShake();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isBusy) return;
    setState(() {
      _formError = null;
      _biometricNotice = null;
      _isGoogleSubmitting = true;
    });
    try {
      final credential = await ref
          .read(authRepositoryProvider)
          .signInWithGoogle(rememberMe: _rememberMe);
      await syncAuthSessionState(ref);
      if (!mounted) {
        return;
      }
      final email = credential.user.email.trim().toLowerCase();
      if (email.isNotEmpty) {
        await _saveLastEmail(email);
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = _friendlyLoginErrorMessage(
          error,
          fallback: 'Google sign-in failed. Please try again.',
        );
      });
      _showStageBanner(_formError!, isError: true);
      await _triggerShake();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = error.toString().replaceFirst('Exception: ', '');
      });
      _showStageBanner(_formError!, isError: true);
      await _triggerShake();
    } finally {
      if (mounted) {
        setState(() => _isGoogleSubmitting = false);
      }
    }
  }

  String _friendlyLoginErrorMessage(
    FirebaseAuthException error, {
    String fallback = 'Login failed. Please try again.',
  }) {
    final code = error.code.trim().toLowerCase();
    final rawMessage = (error.message ?? '').trim().toLowerCase();

    if (code == 'invalid-credential' ||
        code == 'wrong-password' ||
        code == 'user-not-found' ||
        rawMessage.contains('supplied auth credential is incorrect') ||
        rawMessage.contains('malformed or has expired')) {
      return 'The email or password is incorrect. Please try again.';
    }

    if (code == 'invalid-email') {
      return 'Please enter a valid email address.';
    }

    if (code == 'user-disabled') {
      return 'This account has been disabled. Please contact support.';
    }

    if (code == 'too-many-requests') {
      return 'Too many attempts were made. Please wait a moment and try again.';
    }

    if (code == 'network-request-failed') {
      return 'We could not reach the server. Check your internet connection and try again.';
    }

    if (code == 'popup-closed-by-user') {
      return 'Sign-in was cancelled before it could finish.';
    }

    if (code == 'popup-blocked') {
      return 'Your browser blocked the sign-in window. Allow pop-ups and try again.';
    }

    if (rawMessage.isNotEmpty) {
      return error.message!;
    }

    return fallback;
  }

  Uri _buildWindowsSignupUri() {
    final route = _hasInviteContext
        ? AppRoute.withInviteQuery(AppRoute.registerDetails, _inviteQuery)
        : AppRoute.register;
    final routeUri = Uri.parse(route);
    return _webAppBaseUri.replace(
      path: routeUri.path,
      queryParameters: routeUri.queryParameters.isEmpty
          ? null
          : routeUri.queryParameters,
    );
  }

  Future<void> _openSignupOnWeb() async {
    final launched = await launchUrl(
      _buildWindowsSignupUri(),
      mode: LaunchMode.externalApplication,
    );
    if (launched || !mounted) {
      return;
    }
    setState(() {
      _formError =
          'We could not open the web sign-up page. Visit mindnestke.netlify.app in your browser.';
    });
    _showStageBanner(_formError!, isError: true);
    await _triggerShake();
  }

  Future<void> _restoreLastEmail() async {
    final preferences = await SharedPreferences.getInstance();
    final storedEmail = preferences.getString(_lastEmailKey)?.trim();

    if (!mounted || storedEmail == null || storedEmail.isEmpty) {
      return;
    }

    setState(() => _lastEmail = storedEmail);
    if (_emailController.text.trim().isEmpty) {
      _emailController.text = storedEmail;
    }
  }

  Future<void> _saveLastEmail(String email) async {
    if (email.isEmpty) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastEmailKey, email);

    if (!mounted) {
      return;
    }

    setState(() => _lastEmail = email);
  }

  Map<String, String> get _inviteQuery => AppRoute.inviteQuery(
    inviteId: widget.inviteId ?? '',
    invitedEmail: widget.invitedEmail,
    invitedName: widget.invitedName,
    institutionName: widget.institutionName,
    intendedRole: widget.intendedRole,
  );

  bool get _hasInviteContext => _inviteQuery.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFF03110F),
        body: Stack(
          children: [
            const Positioned.fill(child: _DarkDesktopBackground()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(34, 24, 34, 26),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const _DesktopLoginBrand(),
                        const Spacer(),
                        _DesktopCreateAccountLink(
                          onPressed: _goToSignup,
                          disabled: _isEntryLocked,
                        ),
                        const SizedBox(width: 12),
                        const WindowsDesktopWindowControls(),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1440),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedAlign(
                                duration: const Duration(milliseconds: 520),
                                curve: Curves.easeOutCubic,
                                alignment: _showEmailForm
                                    ? const Alignment(-0.86, 0.02)
                                    : Alignment.center,
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 520),
                                  curve: Curves.easeOutCubic,
                                  scale: _showEmailForm ? 0.78 : 1,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: _BiometricHero(
                                      isBiometricScanning: _isBiometricScanning,
                                      isGoogleSubmitting: _isGoogleSubmitting,
                                      isBusy: _isEntryLocked,
                                      isEmailOpen: _showEmailForm,
                                      noticeText: _biometricNotice,
                                      errorText: _showEmailForm
                                          ? null
                                          : _formError,
                                      onBiometricTap: _startPasskeySignIn,
                                      onGooglePressed: _signInWithGoogle,
                                      onUseEmailPressed: _showEmailLogin,
                                    ),
                                  ),
                                ),
                              ),
                              // When the email form is open, allow clicks anywhere
                              // outside the form to close it by tapping this overlay.
                              if (_showEmailForm)
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _showBiometricLogin,
                                    child: Container(color: Colors.transparent),
                                  ),
                                ),
                              AnimatedAlign(
                                duration: const Duration(milliseconds: 520),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.centerRight,
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 520),
                                  curve: Curves.easeOutCubic,
                                  offset: _showEmailForm
                                      ? Offset.zero
                                      : const Offset(0.22, 0),
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 320),
                                    curve: Curves.easeOut,
                                    opacity: _showEmailForm ? 1 : 0,
                                    child: IgnorePointer(
                                      ignoring: !_showEmailForm,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 520,
                                        ),
                                        child: _DesktopEmailLoginCard(
                                          child: _buildFormContent(
                                            context,
                                            showBrand: false,
                                          ),
                                        ),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      child: _buildFormContent(context, showBrand: true),
    );
  }

  Widget _buildFormContent(BuildContext context, {required bool showBrand}) {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeOffset.value, 0),
          child: child,
        );
      },
      child: Form(
        key: const ValueKey('login-form'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!showBrand) const SizedBox(height: 4),
            if (showBrand) ...[
              const SizedBox(),
              BrandMark(
                showText:
                    MediaQuery.sizeOf(context).width >= _desktopBreakpoint,
                compact: false,
                withBlob: MediaQuery.sizeOf(context).width < _desktopBreakpoint,
              ),
              SizedBox(
                height: MediaQuery.sizeOf(context).width >= _desktopBreakpoint
                    ? 14
                    : 0,
              ),
            ] else ...[
              const SizedBox(height: 4),
            ],
            Text(
              'Welcome Back',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF071937),
                letterSpacing: -0.7,
              ),
              textAlign: TextAlign.center,
            ),
            if (_hasInviteContext) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFFFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFB3ECDD)),
                ),
                child: Text(
                  'Invite detected${(widget.institutionName ?? '').trim().isNotEmpty ? ' for ${widget.institutionName!.trim()}' : ''}. Log in with the invited email to continue.',
                  style: const TextStyle(
                    color: Color(0xFF0D6F69),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (showBrand) ...[
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E9B90),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2218A89D),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: _isEntryLocked ? null : _signInWithGoogle,
                        icon: _isGoogleSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : SvgPicture.asset(
                                'assets/google.svg',
                                width: 20,
                                height: 20,
                              ),
                        label: Text(
                          _isGoogleSubmitting ? 'Connecting' : 'Google',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF071937),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22071937),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: _isEntryLocked ? null : _startPasskeySignIn,
                        icon: _isBiometricScanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.fingerprint_rounded, size: 22),
                        label: Text(
                          _isBiometricScanning ? 'Verifying' : 'Biometric',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: Divider(color: Colors.grey.shade300, thickness: 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(color: Colors.grey.shade300, thickness: 1),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: (_formError == null || _formError!.trim().isEmpty)
                  ? const SizedBox(height: 24)
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
            const _FieldLabel(text: 'EMAIL ADDRESS'),
            const SizedBox(height: 8),
            _RoundedInput(
              hasError: _emailFieldError,
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) {
                  if (_emailFieldError || _formError != null) {
                    setState(() {
                      _emailFieldError = false;
                      _formError = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'alex@example.com',
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                ),
              ),
            ),
            if ((_lastEmail ?? '').isNotEmpty &&
                _emailController.text.trim().toLowerCase() != _lastEmail)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () {
                      final lastEmail = _lastEmail;
                      if (lastEmail == null || lastEmail.isEmpty) {
                        return;
                      }
                      setState(() {
                        _emailController.text = lastEmail;
                        _emailController.selection = TextSelection.collapsed(
                          offset: lastEmail.length,
                        );
                        _emailFieldError = false;
                        _formError = null;
                      });
                    },
                    child: Text(
                      'Use saved email: $_lastEmail',
                      style: const TextStyle(
                        color: Color(0xFF0E9B90),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                const _FieldLabel(text: 'PASSWORD'),
                const Spacer(),
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => context.go(
                          AppRoute.withInviteQuery(
                            AppRoute.forgotPassword,
                            _inviteQuery,
                          ),
                        ),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: Color(0xFF0E9B90),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _RoundedInput(
              hasError: _passwordFieldError,
              child: TextFormField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                onChanged: (_) {
                  if (_passwordFieldError || _formError != null) {
                    setState(() {
                      _passwordFieldError = false;
                      _formError = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: '********',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: _isBusy
                          ? null
                          : (value) {
                              setState(() => _rememberMe = value ?? false);
                            },
                    ),
                    const Text(
                      'Remember Me',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    'Keep me signed in for 14 days on this device.',
                    style: TextStyle(
                      color: Color(0xFF0E9B90),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 16),
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
                onPressed: _isBusy ? null : _submit,
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
                  child: _isSubmitting
                      ? const Text(
                          'Signing in...',
                          key: ValueKey('login-busy'),
                          style: TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        )
                      : _isGoogleSubmitting
                      ? const Text(
                          'Please wait...',
                          key: ValueKey('login-google'),
                          style: TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          key: const ValueKey('login-ready'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Log In',
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
            ),
            if (showBrand) ...[
              const SizedBox(height: 18),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const Text(
                      'New here?',
                      style: TextStyle(
                        color: Color(0xFF4A607C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton(
                      onPressed: _isEntryLocked ? null : _goToSignup,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0E9B90),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                      child: const Text(
                        'Create account',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    TextButton(
                      onPressed: _isEntryLocked
                          ? null
                          : () => context.go(AppRoute.registerInstitution),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0E9B90),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                      child: const Text(
                        'Register institution',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DesktopMarketingPanel extends StatefulWidget {
  const _DesktopMarketingPanel({
    // ignore: unused_element_parameter
    this.onCreateAccount,
    // ignore: unused_element_parameter
    this.onRegisterInstitution,
    // ignore: unused_element_parameter
    this.hasInviteContext = false,
    // ignore: unused_element_parameter
    this.institutionName,
  });

  final VoidCallback? onCreateAccount;
  final VoidCallback? onRegisterInstitution;
  final bool hasInviteContext;
  final String? institutionName;

  @override
  State<_DesktopMarketingPanel> createState() => _DesktopMarketingPanelState();
}

class _DesktopMarketingPanelState extends State<_DesktopMarketingPanel> {
  static const Map<String, List<String>>
  _fallbackFacts = <String, List<String>>{
    'Sleep': <String>[
      'Did you know? Getting morning sunlight can help your brain set a stronger sleep rhythm at night.',
      'Did you know? Deep sleep helps lock in emotional memories so stressful days feel less heavy later.',
      'Did you know? A consistent sleep window often improves mood more than sleeping very long on weekends.',
      'Did you know? A cooler bedroom can help your body start melatonin release sooner.',
    ],
    'Stress': <String>[
      'Did you know? Slow exhaling for longer than inhaling can signal your nervous system to downshift.',
      'Did you know? Naming your feeling out loud can reduce emotional intensity in the moment.',
      'Did you know? Brief movement breaks can lower stress hormones faster than passive scrolling.',
      'Did you know? Social laughter can reduce stress tension even before a problem is solved.',
    ],
    'Focus': <String>[
      'Did you know? Your focus often improves when you single-task in short blocks with clear stop points.',
      'Did you know? Decision fatigue can start early, so doing hardest tasks first protects mental energy.',
      'Did you know? Hydration affects attention; even mild dehydration can reduce concentration.',
      'Did you know? Writing one next action can reduce mental overload better than replaying the whole task.',
    ],
    'Mood': <String>[
      'Did you know? A 10-minute walk can lift mood by increasing blood flow and neurotransmitter activity.',
      'Did you know? Gratitude journaling can train attention toward positive cues over time.',
      'Did you know? Music you enjoy can reduce perceived effort and improve emotional resilience.',
      'Did you know? Helping someone else can activate reward circuits that improve mood.',
    ],
    'Energy': <String>[
      'Did you know? Large blood sugar spikes can be followed by energy crashes that feel like low motivation.',
      'Did you know? Light stretching can improve alertness during afternoon slumps.',
      'Did you know? Short outdoor breaks can raise perceived energy more than staying under indoor lighting.',
      'Did you know? Protein and fiber at breakfast can support steadier energy through the morning.',
    ],
    'Connection': <String>[
      'Did you know? Meaningful social contact can buffer stress responses in the brain.',
      'Did you know? Eye contact and warm tone can increase feelings of safety in conversations.',
      'Did you know? Feeling listened to reduces cognitive load and can improve emotional regulation.',
      'Did you know? Small daily check-ins often strengthen relationships more than occasional long talks.',
    ],
  };

  static final List<_DidYouKnowFact> _factCatalog = _buildFactCatalog();
  static final _DidYouKnowFact _defaultFact = _DidYouKnowFact(
    id: _stableFactId(
      'Did you know? Tiny daily habits, repeated consistently, often create the biggest wellness gains over time.',
    ),
    text:
        'Did you know? Tiny daily habits, repeated consistently, often create the biggest wellness gains over time.',
    topic: 'Wellness',
    source: 'MindNest pick',
  );

  final math.Random _random = math.Random();

  _DidYouKnowFact? _currentFact;
  bool _isFactLoading = true;

  @override
  void initState() {
    super.initState();
    _restoreSessionFact();
  }

  Future<void> _restoreSessionFact() async {
    final activeFactId = LoginDidYouKnowSession.activeFactId;
    if (activeFactId != null) {
      final activeFact = _factForId(activeFactId);
      if (activeFact != null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentFact = activeFact;
          _isFactLoading = false;
        });
        return;
      }
    }

    final lastFactId = kIsWeb
        ? await LoginDidYouKnowSession.readLastFactId()
        : null;
    final nextFact = _pickNextFact(lastFactId: lastFactId);
    LoginDidYouKnowSession.setActiveFact(nextFact.id);
    if (kIsWeb) {
      await LoginDidYouKnowSession.persistLastFactId(nextFact.id);
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _currentFact = nextFact;
      _isFactLoading = false;
    });
  }

  _DidYouKnowFact _pickNextFact({String? lastFactId}) {
    final candidates = _factCatalog
        .where((fact) => fact.id != (lastFactId ?? '').trim())
        .toList(growable: false);
    final pool = candidates.isEmpty ? _factCatalog : candidates;
    if (pool.isEmpty) {
      return _defaultFact;
    }
    return pool[_random.nextInt(pool.length)];
  }

  static List<_DidYouKnowFact> _buildFactCatalog() {
    final facts = <_DidYouKnowFact>[];
    for (final entry in _fallbackFacts.entries) {
      for (final text in entry.value) {
        facts.add(
          _DidYouKnowFact(
            id: _stableFactId(text),
            text: text,
            topic: entry.key,
            source: 'MindNest pick',
          ),
        );
      }
    }
    return facts;
  }

  static _DidYouKnowFact? _factForId(String factId) {
    final normalized = factId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final fact in _factCatalog) {
      if (fact.id == normalized) {
        return fact;
      }
    }
    if (_defaultFact.id == normalized) {
      return _defaultFact;
    }
    return null;
  }

  static String _stableFactId(String text) {
    final normalized = text.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    var hash = 0x811C9DC5;
    for (final codeUnit in normalized.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  Widget build(BuildContext context) {
    final inviteInstitutionName = (widget.institutionName ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _DesktopBrandIcon(),
              SizedBox(width: 6),
              Text(
                'MindNest',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 41,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF062E43),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14062E43),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.language_rounded,
                  size: 16,
                  color: Color(0xFF7CF4E8),
                ),
                SizedBox(width: 8),
                Text(
                  'Web-first workspace for institutions and care teams',
                  style: TextStyle(
                    color: Color(0xFFF4FFFE),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 58,
                fontWeight: FontWeight.w800,
                height: 0.95,
                letterSpacing: -1.7,
              ),
              children: [
                TextSpan(
                  text: 'A calmer browser workspace ',
                  style: TextStyle(color: Color(0xFF0F172A)),
                ),
                TextSpan(
                  text: 'for mental wellness teams.',
                  style: TextStyle(color: Color(0xFF0E9B90)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              'MindNest brings invites, onboarding, booking workflows, notifications, live support rooms, and privacy-aware role journeys into one polished web experience for students, staff, counselors, admins, owners, and individual members.',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF4B617B),
                height: 1.42,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _RoleBadge(label: 'Students'),
              _RoleBadge(label: 'Staff'),
              _RoleBadge(label: 'Counselors'),
              _RoleBadge(label: 'Admins'),
              _RoleBadge(label: 'Owners'),
              _RoleBadge(label: 'Individuals'),
            ],
          ),
          if (widget.hasInviteContext) ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFFFFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFB6ECDD)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E9B90).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mark_email_read_rounded,
                      color: Color(0xFF0E9B90),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      inviteInstitutionName.isEmpty
                          ? 'Invite ready. Sign in or create your account with the invited email to enter your workspace without extra setup.'
                          : 'Invite ready for $inviteInstitutionName. Sign in or create your account with the invited email to land in the right workspace without extra setup.',
                      style: const TextStyle(
                        color: Color(0xFF0D6F69),
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: const [
              _MarketingMetricCard(
                title: '6 tailored roles',
                description:
                    'Owner, admin, counselor, student, staff, and individual journeys stay role-aware from login onward.',
              ),
              _MarketingMetricCard(
                title: 'Realtime operations',
                description:
                    'Invites, schedules, and notification state stay live in the browser instead of feeling static.',
              ),
              _MarketingMetricCard(
                title: 'Pitch-ready flow',
                description:
                    'A branded entry, cleaner onboarding, and persistent workspace navigation make the product easier to sell.',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: widget.onCreateAccount,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Create account'),
              ),
              OutlinedButton.icon(
                onPressed: widget.onRegisterInstitution,
                icon: const Icon(Icons.apartment_rounded),
                label: const Text('Register institution'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: const [
              _MarketingFeatureCard(
                icon: Icons.mark_email_unread_rounded,
                title: 'Invite-led onboarding',
                description:
                    'Institution members can join through guided invites and land in the right role with less back-and-forth.',
              ),
              _MarketingFeatureCard(
                icon: Icons.event_available_rounded,
                title: 'Care operations in one place',
                description:
                    'Scheduling, counselor discovery, session queues, and notifications stay inside one connected web workspace.',
              ),
              _MarketingFeatureCard(
                icon: Icons.graphic_eq_rounded,
                title: 'Live support moments',
                description:
                    'MindNest already supports live audio rooms and follow-up flows, which makes demos feel like a product, not a mockup.',
              ),
            ],
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _buildDidYouKnowCard(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDidYouKnowCard(BuildContext context) {
    final fact = _currentFact;
    final topicLabel = fact?.topic ?? 'Wellness';
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFF7FFFE), Color(0xFFF3FCFA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFD0F0EB), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x190F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF062E43),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 15,
                      color: Color(0xFF7CF4E8),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Did You Know',
                      style: TextStyle(
                        color: Color(0xFFF4FFFE),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'MindNest welcome note',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF315A74),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_isFactLoading) const _TypingDots(),
            ],
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 340),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offsetAnimation = Tween<Offset>(
                begin: const Offset(0.0, 0.1),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offsetAnimation, child: child),
              );
            },
            child: Container(
              key: ValueKey(fact?.id ?? 'loading'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white.withValues(alpha: 0.88),
                border: Border.all(color: const Color(0xFFDBEEE9)),
              ),
              child: Text(
                fact?.text ?? 'Loading a welcome fact for this visit...',
                style: const TextStyle(
                  color: Color(0xFF14324D),
                  fontSize: 23,
                  height: 1.28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F7F4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  topicLabel,
                  style: const TextStyle(
                    color: Color(0xFF0F6C68),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  fact?.source ?? 'MindNest pick',
                  style: const TextStyle(
                    color: Color(0xFF315A74),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (kIsWeb)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F7FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'New one after logout',
                    style: TextStyle(
                      color: Color(0xFF48637B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD7E6EE)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF315A74),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MarketingMetricCard extends StatelessWidget {
  const _MarketingMetricCard({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 222,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFDCECF1)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x110F172A),
              blurRadius: 18,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFF4B617B),
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketingFeatureCard extends StatelessWidget {
  const _MarketingFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 242,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF9FFFE), Color(0xFFF5FBFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD6EBE8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0E9B90).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF0E9B90)),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFF4B617B),
                height: 1.42,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DidYouKnowFact {
  const _DidYouKnowFact({
    required this.id,
    required this.text,
    required this.topic,
    required this.source,
  });

  final String id;
  final String text;
  final String topic;
  final String source;
}

class _DesktopBrandIcon extends StatelessWidget {
  const _DesktopBrandIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: MindNestLogo(width: 150, height: 150, fit: BoxFit.contain),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final wave = (progress - index * 0.18) * math.pi * 2;
            final opacity = (0.4 + (math.sin(wave) + 1) * 0.3)
                .clamp(0.2, 1.0)
                .toDouble();
            return Container(
              width: 7,
              height: 7,
              margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0E9B90).withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ignore: unused_element
class _DesktopAmbientBackground extends StatelessWidget {
  const _DesktopAmbientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF8FCFD),
                  const Color(0xFFF6FAFC),
                  const Color(0xFFF4F9FB),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Positioned(
          left: -150,
          top: -210,
          child: _GlowBlob(
            size: 680,
            color: const Color(0xFF82E9E0).withValues(alpha: 0.35),
          ),
        ),
        Positioned(
          right: -160,
          top: 130,
          child: _GlowBlob(
            size: 560,
            color: const Color(0xFFB8F4EF).withValues(alpha: 0.34),
          ),
        ),
        Positioned(
          right: 150,
          bottom: -220,
          child: _GlowBlob(
            size: 640,
            color: const Color(0xFF8DE8DF).withValues(alpha: 0.26),
          ),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.44),
              blurRadius: size * 0.28,
              spreadRadius: size * 0.02,
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkDesktopBackground extends StatelessWidget {
  const _DarkDesktopBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF063D36),
                  const Color(0xFF031916),
                  const Color(0xFF030A09),
                ],
                center: const Alignment(-0.92, -0.72),
                radius: 1.4,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFF020807).withValues(alpha: 0.62),
                  const Color(0xFF05211D).withValues(alpha: 0.9),
                ],
                stops: const [0.0, 0.52, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Positioned(
          left: -210,
          top: -230,
          child: _GlowBlob(
            size: 760,
            color: const Color(0xFF0E9B90).withValues(alpha: 0.22),
          ),
        ),
        Positioned(
          right: -180,
          top: 70,
          child: _GlowBlob(
            size: 620,
            color: const Color(0xFF6DE3D9).withValues(alpha: 0.14),
          ),
        ),
        Positioned(
          right: 115,
          bottom: -260,
          child: _GlowBlob(
            size: 720,
            color: const Color(0xFF0E9B90).withValues(alpha: 0.13),
          ),
        ),
      ],
    );
  }
}

class _DesktopLoginBrand extends StatelessWidget {
  const _DesktopLoginBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const MindNestLogo(width: 32, height: 32),
        ),
        const SizedBox(width: 10),
        const Text(
          'mindnest',
          style: TextStyle(
            color: Color(0xFFE6FFFB),
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.35,
          ),
        ),
      ],
    );
  }
}

class _DesktopCreateAccountLink extends StatefulWidget {
  const _DesktopCreateAccountLink({
    required this.onPressed,
    required this.disabled,
  });

  final VoidCallback onPressed;
  final bool disabled;

  @override
  State<_DesktopCreateAccountLink> createState() =>
      _DesktopCreateAccountLinkState();
}

class _DesktopCreateAccountLinkState extends State<_DesktopCreateAccountLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabled;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered && !disabled
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _isHovered && !disabled
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New here? ',
                    style: TextStyle(
                      color: disabled
                          ? Colors.white.withValues(alpha: 0.34)
                          : Colors.white.withValues(alpha: 0.72),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Create account',
                    style: TextStyle(
                      color: disabled
                          ? Colors.white.withValues(alpha: 0.34)
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.north_east_rounded,
                size: 15,
                color: disabled
                    ? Colors.white.withValues(alpha: 0.34)
                    : Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopEmailLoginCard extends StatelessWidget {
  const _DesktopEmailLoginCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxHeight = math.max(520.0, MediaQuery.sizeOf(context).height - 150);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF5FAFA).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: const Color(0xFFBEE9E4).withValues(alpha: 0.9),
                width: 1.1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4510B8A6),
                  blurRadius: 46,
                  offset: Offset(0, 22),
                ),
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 60,
                  offset: Offset(0, 30),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(34, 24, 34, 30),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _BiometricHero extends StatefulWidget {
  const _BiometricHero({
    required this.isBiometricScanning,
    required this.isGoogleSubmitting,
    required this.isBusy,
    required this.isEmailOpen,
    required this.noticeText,
    required this.errorText,
    required this.onBiometricTap,
    required this.onGooglePressed,
    required this.onUseEmailPressed,
  });

  final bool isBiometricScanning;
  final bool isGoogleSubmitting;
  final bool isBusy;
  final bool isEmailOpen;
  final String? noticeText;
  final String? errorText;
  final VoidCallback onBiometricTap;
  final VoidCallback onGooglePressed;
  final VoidCallback onUseEmailPressed;

  @override
  State<_BiometricHero> createState() => _BiometricHeroState();
}

class _BiometricHeroState extends State<_BiometricHero>
    with TickerProviderStateMixin {
  late final AnimationController _orbitController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _orbitController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.isEmailOpen ? 690.0 : 760.0;
    return SizedBox(
      width: width,
      height: 650,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _BiometricOrbitPainter(
                showEmailPill: !widget.isEmailOpen,
              ),
            ),
          ),
          Positioned(
            top: 55,
            left: 0,
            right: 0,
            child: Center(
              child: _WelcomePill(isScanning: widget.isBiometricScanning),
            ),
          ),
          Positioned(
            left: widget.isEmailOpen ? 82 : 116,
            top: 210,
            child: _StagePillButton(
              label: widget.isGoogleSubmitting ? 'Connecting...' : 'Google',
              isLight: true,
              disabled: widget.isBusy,
              onPressed: widget.onGooglePressed,
              leading: widget.isGoogleSubmitting
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : SvgPicture.asset(
                      'assets/google.svg',
                      width: 18,
                      height: 18,
                    ),
            ),
          ),
          Positioned(
            left: widget.isEmailOpen ? 152 : 186,
            top: 271,
            child: Container(
              width: 1,
              height: 58,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          if (!widget.isEmailOpen) ...[
            Positioned(
              right: 156,
              top: 327,
              child: Container(
                width: 1,
                height: 86,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              right: 156,
              top: 412,
              child: Container(
                width: 70,
                height: 1,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              right: 40,
              top: 384,
              child: _StagePillButton(
                label: 'Use email instead',
                disabled: widget.isBusy,
                onPressed: widget.onUseEmailPressed,
                trailing: const Icon(
                  Icons.north_east_rounded,
                  size: 18,
                  color: Color(0xFFE6FFFB),
                ),
              ),
            ),
          ],
          Positioned(
            top: 242,
            left: 0,
            right: 0,
            child: Center(
              child: _BiometricOrb(
                orbitController: _orbitController,
                pulseController: _pulseController,
                isScanning: widget.isBiometricScanning,
                disabled: widget.isBusy,
                onTap: widget.onBiometricTap,
              ),
            ),
          ),
          Positioned(
            top: widget.isBiometricScanning ? 480 : 493,
            left: 0,
            right: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Column(
                key: ValueKey(widget.isBiometricScanning),
                children: [
                  Text(
                    widget.isBiometricScanning ? 'Scanning...' : 'Tap to enter',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Passkey sign-in',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.56),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Stage message now shown via overlay banners (modern_banner.dart).
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'END-TO-END ENCRYPTED - PRIVATE BY DESIGN',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.23),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BiometricOrbitPainter extends CustomPainter {
  const _BiometricOrbitPainter({required this.showEmailPill});

  final bool showEmailPill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 360);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.055);

    for (final radius in <double>[132, 198, 258, 318]) {
      canvas.drawCircle(center, radius, ringPaint);
    }

    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF0E9B90).withValues(alpha: 0.22),
          const Color(0xFF0E9B90).withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 290));
    canvas.drawCircle(center, 290, auraPaint);
  }

  @override
  bool shouldRepaint(covariant _BiometricOrbitPainter oldDelegate) {
    return oldDelegate.showEmailPill != showEmailPill;
  }
}

class _WelcomePill extends StatelessWidget {
  const _WelcomePill({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isScanning ? 0.11 : 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF72ECDC),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isScanning ? 'VERIFYING ACCESS' : 'WELCOME BACK',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _BiometricOrb extends StatelessWidget {
  const _BiometricOrb({
    required this.orbitController,
    required this.pulseController,
    required this.isScanning,
    required this.disabled,
    required this.onTap,
  });

  final AnimationController orbitController;
  final AnimationController pulseController;
  final bool isScanning;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([orbitController, pulseController]),
      builder: (context, _) {
        final pulse = isScanning
            ? (math.sin(pulseController.value * math.pi * 2) + 1) / 2
            : 0.0;
        return MouseRegion(
          cursor: disabled
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: disabled ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              width: isScanning ? 255 : 244,
              height: isScanning ? 326 : 244,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(180),
                color: const Color(
                  0xFF0E9B90,
                ).withValues(alpha: isScanning ? 0.20 + (pulse * 0.06) : 0.02),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF35D7C7,
                    ).withValues(alpha: isScanning ? 0.36 : 0.24),
                    blurRadius: isScanning ? 74 : 42,
                    spreadRadius: isScanning ? 8 : 1,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: isScanning ? 1 : 0,
                    child: Container(
                      width: 186,
                      height: 300,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(130),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.03),
                            Colors.white.withValues(alpha: 0.13),
                            Colors.white.withValues(alpha: 0.03),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 222,
                    height: 222,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF287F69).withValues(alpha: 0.88),
                      border: Border.all(
                        color: const Color(0xFF45DDB9),
                        width: 9,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3314B8A6),
                          blurRadius: 38,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                  ),
                  Transform.rotate(
                    angle: orbitController.value * math.pi * 2,
                    child: SizedBox(
                      width: 228,
                      height: 228,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFBFFFF7,
                                ).withValues(alpha: 0.9),
                                blurRadius: 18,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.fingerprint_rounded,
                    color: Colors.white,
                    size: 92,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StagePillButton extends StatefulWidget {
  const _StagePillButton({
    required this.label,
    required this.onPressed,
    this.leading,
    this.trailing,
    this.disabled = false,
    this.isLight = false,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget? leading;
  final Widget? trailing;
  final bool disabled;
  final bool isLight;

  @override
  State<_StagePillButton> createState() => _StagePillButtonState();
}

class _StagePillButtonState extends State<_StagePillButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabled;
    final isLight = widget.isLight;
    final foreground = isLight
        ? const Color(0xFF071937)
        : const Color(0xFFF5FFFD);
    final baseColor = isLight
        ? Colors.white.withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.12);
    final hoverColor = isLight
        ? const Color(0xFFE9FFFB)
        : Colors.white.withValues(alpha: 0.20);

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: _isHovered && !disabled ? hoverColor : baseColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isLight
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: _isHovered ? 0.22 : 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: isLight
                    ? Colors.black.withValues(alpha: _isHovered ? 0.16 : 0.10)
                    : const Color(
                        0xFF0E9B90,
                      ).withValues(alpha: _isHovered ? 0.30 : 0.12),
                blurRadius: _isHovered ? 30 : 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 12),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: disabled
                      ? foreground.withValues(alpha: 0.45)
                      : foreground,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 12),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LegacyBiometricHero extends StatelessWidget {
  const _LegacyBiometricHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Floating Google pill (visual only)
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 12,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset('assets/google.svg', height: 16, width: 16),
                const SizedBox(width: 8),
                const Text(
                  'Google',
                  style: TextStyle(
                    color: Color(0xFF071937),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        GestureDetector(
          onTap: () {
            // biometric flow will be implemented later; skeleton only
          },
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF0E9B90), Color(0xFF065D55)],
                center: Alignment(-0.2, -0.2),
                radius: 0.9,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3318A89D),
                  blurRadius: 40,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.fingerprint_rounded,
                    size: 88,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Tap to enter',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Passkey sign-in',
          style: TextStyle(
            color: Color(0xFFBFECE6),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
