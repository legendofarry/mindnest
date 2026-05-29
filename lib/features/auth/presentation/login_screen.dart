// features/auth/presentation/login_screen.dart
import 'dart:math' as math;

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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _isPasswordVisible = false;
  bool _emailFieldError = false;
  bool _passwordFieldError = false;
  String? _lastEmail;
  String? _formError;

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

  bool get _isBusy => _isSubmitting || _isGoogleSubmitting;
  bool get _isWindowsLoginOnlyMode =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

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
      await _triggerShake();
      return;
    }

    final normalizedEmail = email.toLowerCase();
    setState(() {
      _emailFieldError = false;
      _passwordFieldError = false;
      _formError = null;
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
      await _triggerShake();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = error.toString().replaceFirst('Exception: ', '');
      });
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
      await _triggerShake();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = error.toString().replaceFirst('Exception: ', '');
      });
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
        backgroundColor: const Color(0xFFF7FBFC),
        body: Stack(
          children: [
            const Positioned.fill(child: _DesktopAmbientBackground()),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 52,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
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
                            padding: const EdgeInsets.fromLTRB(34, 28, 34, 26),
                            child: _buildFormContent(context, showBrand: false),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: WindowsDesktopWindowControls(),
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
              const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            Text(
              'Continue your journey to wellness.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF5E728D),
                fontWeight: FontWeight.w500,
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
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _signInWithGoogle,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                shadowColor: Colors.transparent,
                side: const BorderSide(color: Color(0xFFD0D9E6)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isGoogleSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : SvgPicture.asset(
                      'assets/google.svg',
                      height: 20,
                      width: 20,
                    ),
              label: Text(
                _isGoogleSubmitting
                    ? 'Connecting to Google...'
                    : 'Continue with Google',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ),
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
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isWindowsLoginOnlyMode
                      ? 'Need a MindNest account? '
                      : 'New to MindNest? ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF4A607C),
                  ),
                ),
                MouseRegion(
                  cursor: _isBusy
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _isBusy
                        ? null
                        : _isWindowsLoginOnlyMode
                        ? _openSignupOnWeb
                        : () => context.go(
                            _hasInviteContext
                                ? AppRoute.withInviteQuery(
                                    AppRoute.registerDetails,
                                    _inviteQuery,
                                  )
                                : AppRoute.register,
                          ),
                    child: Text(
                      _isWindowsLoginOnlyMode ? 'Sign Up' : 'Create Account',
                      style: TextStyle(
                        color: Color(0xFF0E9B90),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopMarketingPanel extends StatefulWidget {
  const _DesktopMarketingPanel({
    this.onCreateAccount,
    this.onRegisterInstitution,
    this.hasInviteContext = false,
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
