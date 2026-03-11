// features/auth/presentation/login_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/ai/data/assistant_providers.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      await _saveLastEmail(normalizedEmail);
    } on FirebaseAuthException catch (error) {
      setState(() {
        _formError = error.message ?? 'Login failed.';
      });
      await _triggerShake();
    } catch (error) {
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
      final email = credential.user?.email?.trim().toLowerCase() ?? '';
      if (email.isNotEmpty) {
        await _saveLastEmail(email);
      }
    } on FirebaseAuthException catch (error) {
      setState(() {
        _formError = error.message ?? 'Google sign-in failed.';
      });
      await _triggerShake();
    } catch (error) {
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          flex: 6,
                          child: _DesktopMarketingPanel(),
                        ),
                        const SizedBox(width: 54),
                        Expanded(
                          flex: 5,
                          child: Align(
                            alignment: Alignment.centerRight,
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
                                  padding: const EdgeInsets.fromLTRB(
                                    34,
                                    28,
                                    34,
                                    26,
                                  ),
                                  child: _buildFormContent(
                                    context,
                                    showBrand: false,
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
              const SizedBox(height: 8),
              BrandMark(
                showText:
                    MediaQuery.sizeOf(context).width >= _desktopBreakpoint,
                compact: false,
                withBlob: MediaQuery.sizeOf(context).width < _desktopBreakpoint,
              ),
              SizedBox(
                height: MediaQuery.sizeOf(context).width >= _desktopBreakpoint
                    ? 14
                    : 2,
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
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'alex@example.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
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
                  : Image.network(
                      'https://developers.google.com/identity/images/g-logo.png',
                      height: 20,
                      width: 20,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.g_mobiledata_rounded,
                        size: 24,
                        color: Color(0xFFEA4335),
                      ),
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
                  child: Text(
                    _isSubmitting
                        ? 'Signing in...'
                        : (_isGoogleSubmitting
                              ? 'Please wait...'
                              : 'Log In  ->'),
                    key: ValueKey(_isBusy),
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'New to MindNest? ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF4A607C),
                  ),
                ),
                GestureDetector(
                  onTap: _isBusy
                      ? null
                      : () => context.go(
                          _hasInviteContext
                              ? AppRoute.withInviteQuery(
                                  AppRoute.registerDetails,
                                  _inviteQuery,
                                )
                              : AppRoute.register,
                        ),
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      color: Color(0xFF0E9B90),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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

class _DesktopMarketingPanel extends ConsumerStatefulWidget {
  const _DesktopMarketingPanel();

  @override
  ConsumerState<_DesktopMarketingPanel> createState() =>
      _DesktopMarketingPanelState();
}

class _DesktopMarketingPanelState
    extends ConsumerState<_DesktopMarketingPanel> {
  // Temporary quota guard. Set to false to resume AI fact generation.
  static const _pauseAiFactGeneration = true;
  static const _seenFactIdsKey = 'login.did_you_know.seen_ids';
  static const _recentFactsKey = 'login.did_you_know.recent_facts';
  static const _reactionCountKey = 'login.did_you_know.reaction_count';

  static const List<String> _topics = <String>[
    'Sleep',
    'Stress',
    'Focus',
    'Mood',
    'Energy',
    'Connection',
  ];

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

  final math.Random _random = math.Random();
  Timer? _autoFactTimer;

  Set<String> _seenFactIds = <String>{};
  List<String> _recentFactTexts = <String>[];
  String _selectedTopic = _topics.first;
  _DidYouKnowFact? _currentFact;

  bool _isFactLoading = true;
  bool _showMindBlownState = false;
  int _reactionCount = 0;

  @override
  void initState() {
    super.initState();
    _restoreFactState();
  }

  @override
  void dispose() {
    _autoFactTimer?.cancel();
    super.dispose();
  }

  Future<void> _restoreFactState() async {
    final preferences = await SharedPreferences.getInstance();
    final seenIds = preferences.getStringList(_seenFactIdsKey) ?? const [];
    final recentFacts = preferences.getStringList(_recentFactsKey) ?? const [];
    final reactionCount = preferences.getInt(_reactionCountKey) ?? 0;

    if (!mounted) {
      return;
    }

    setState(() {
      _seenFactIds = seenIds.toSet();
      _recentFactTexts = recentFacts;
      _reactionCount = reactionCount;
      _isFactLoading = false;
    });
    _startAutoRotation();
    await _loadNextFact();
  }

  void _startAutoRotation() {
    _autoFactTimer?.cancel();
    _autoFactTimer = Timer.periodic(const Duration(seconds: 22), (_) {
      if (!mounted || _isFactLoading || _showMindBlownState) {
        return;
      }
      _loadNextFact();
    });
  }

  Future<void> _loadNextFact() async {
    if (_isFactLoading) {
      return;
    }

    setState(() => _isFactLoading = true);
    final generated = await _generateUniqueFact();

    if (!mounted) {
      return;
    }

    if (generated != null) {
      await _persistFactMemory(generated);
    }

    setState(() {
      _currentFact = generated ?? _buildFallbackFact();
      _isFactLoading = false;
    });
  }

  Future<_DidYouKnowFact?> _generateUniqueFact() async {
    if (_pauseAiFactGeneration) {
      return _buildFallbackFact();
    }

    final avoidFacts = <String>[
      ..._recentFactTexts.take(18),
      if (_currentFact != null) _currentFact!.text,
    ];

    for (var attempt = 0; attempt < 3; attempt++) {
      final aiText = await ref
          .read(assistantRepositoryProvider)
          .generateWellnessDidYouKnowFact(
            topic: _selectedTopic,
            avoidFacts: avoidFacts,
          );
      if (aiText == null || aiText.trim().isEmpty) {
        continue;
      }

      final candidate = _DidYouKnowFact(
        id: _stableFactId(aiText),
        text: aiText.trim(),
        topic: _selectedTopic,
        source: 'AI',
      );
      if (_seenFactIds.contains(candidate.id)) {
        avoidFacts.add(candidate.text);
        continue;
      }
      return candidate;
    }

    final fallback = _buildFallbackFact();
    if (_seenFactIds.contains(fallback.id)) {
      return fallback;
    }
    return fallback;
  }

  _DidYouKnowFact _buildFallbackFact() {
    final selectedTopicFacts = _fallbackFacts[_selectedTopic] ?? const [];
    final pool = <String>[
      ...selectedTopicFacts,
      for (final entry in _fallbackFacts.entries)
        if (entry.key != _selectedTopic) ...entry.value,
    ];
    if (pool.isEmpty) {
      const text =
          'Did you know? Tiny daily habits, repeated consistently, often create the biggest wellness gains over time.';
      return _DidYouKnowFact(
        id: _stableFactId(text),
        text: text,
        topic: _selectedTopic,
        source: 'Fallback',
      );
    }

    final unseen = pool
        .where((fact) => !_seenFactIds.contains(_stableFactId(fact)))
        .toList(growable: false);
    final candidatePool = unseen.isNotEmpty ? unseen : pool;

    String picked = candidatePool[_random.nextInt(candidatePool.length)];
    if (_currentFact != null && candidatePool.length > 1) {
      var guard = 0;
      while (picked == _currentFact!.text && guard < 8) {
        picked = candidatePool[_random.nextInt(candidatePool.length)];
        guard++;
      }
    }

    return _DidYouKnowFact(
      id: _stableFactId(picked),
      text: picked,
      topic: _selectedTopic,
      source: 'Fallback',
    );
  }

  String _stableFactId(String text) {
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

  Future<void> _persistFactMemory(_DidYouKnowFact fact) async {
    _seenFactIds.add(fact.id);
    _recentFactTexts = <String>[
      fact.text,
      ..._recentFactTexts.where((entry) => entry != fact.text),
    ].take(32).toList(growable: false);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _seenFactIdsKey,
      _seenFactIds.toList(growable: false),
    );
    await preferences.setStringList(_recentFactsKey, _recentFactTexts);
  }

  Future<void> _onMindBlownPressed() async {
    if (_isFactLoading || _currentFact == null) {
      return;
    }

    final nextCount = _reactionCount + 1;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_reactionCountKey, nextCount);

    if (!mounted) {
      return;
    }
    setState(() {
      _reactionCount = nextCount;
      _showMindBlownState = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }

    setState(() => _showMindBlownState = false);
    await _loadNextFact();
  }

  Future<void> _onTopicTap(String topic) async {
    if (topic == _selectedTopic) {
      return;
    }
    setState(() => _selectedTopic = topic);
    await _loadNextFact();
  }

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Your safe space',
                  style: TextStyle(
                    color: Color(0xFF0E9B90),
                    fontSize: 62,
                    fontWeight: FontWeight.w800,
                    height: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
                'MindNest AI feed',
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
                fact?.text ?? 'Curating a fresh fact for you...',
                style: const TextStyle(
                  color: Color(0xFF14324D),
                  fontSize: 27,
                  height: 1.28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
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
                  fact == null ? _selectedTopic : fact.topic,
                  style: const TextStyle(
                    color: Color(0xFF0F6C68),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                  fact?.source == 'AI' ? 'AI generated' : 'MindNest picks',
                  style: const TextStyle(
                    color: Color(0xFF315A74),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _topics
                .map((topic) {
                  final selected = topic == _selectedTopic;
                  return ChoiceChip(
                    label: Text(topic),
                    selected: selected,
                    onSelected: (_) => _onTopicTap(topic),
                    labelStyle: TextStyle(
                      color: selected
                          ? const Color(0xFF063B52)
                          : const Color(0xFF48637B),
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF6DE4D9)
                            : const Color(0xFFD3E5E8),
                      ),
                    ),
                    backgroundColor: Colors.white,
                    selectedColor: const Color(0xFFBDF5EE),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: _isFactLoading ? null : _onMindBlownPressed,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFF073B4C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.emoji_objects_rounded, size: 18),
                label: Text(
                  _showMindBlownState
                      ? 'Mind blown unlocked'
                      : 'That was mind-blowing 🤯',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isFactLoading ? null : _loadNextFact,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0E9B90),
                  side: const BorderSide(color: Color(0xFF8ADFD7)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Give me another',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedOpacity(
            opacity: _showMindBlownState ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Text(
              'MindNest AI is finding your next one...',
              style: TextStyle(
                color: Color(0xFF0E9B90),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
      child: Image.asset('assets/logo.png', fit: BoxFit.contain),
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
