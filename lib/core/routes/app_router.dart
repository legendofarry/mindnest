// core/routes/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/config/owner_config.dart';
import 'package:mindnest/core/diagnostics/invite_debug.dart';
import 'package:mindnest/core/ui/desktop_primary_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/app_auth_user.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/forgot_password_screen.dart';
import 'package:mindnest/features/auth/presentation/login_screen.dart';
import 'package:mindnest/features/auth/presentation/register_details_screen.dart';
import 'package:mindnest/features/auth/presentation/register_institution_school_request_screen.dart';
import 'package:mindnest/features/auth/presentation/register_screen.dart';
import 'package:mindnest/features/auth/presentation/register_institution_screen.dart';
import 'package:mindnest/features/auth/presentation/register_institution_success_screen.dart';
import 'package:mindnest/features/auth/presentation/verify_email_screen.dart';
import 'package:mindnest/features/care/presentation/counselor_appointments_screen.dart';
import 'package:mindnest/features/care/presentation/counselor_availability_screen.dart';
import 'package:mindnest/features/care/presentation/counselor_directory_screen.dart';
import 'package:mindnest/features/care/presentation/counselor_profile_screen.dart';
import 'package:mindnest/features/care/presentation/crisis_counselor_support_screen.dart';
import 'package:mindnest/features/care/presentation/notification_center_screen.dart';
import 'package:mindnest/features/care/presentation/notification_details_screen.dart';
import 'package:mindnest/features/care/presentation/session_details_screen.dart';
import 'package:mindnest/features/care/presentation/student_care_plan_screen.dart';
import 'package:mindnest/features/care/presentation/student_appointments_screen.dart';
import 'package:mindnest/features/counselor/data/counselor_providers.dart';
import 'package:mindnest/features/counselor/presentation/counselor_dashboard_screen.dart';
import 'package:mindnest/features/counselor/presentation/counselor_invite_waiting_screen.dart';
import 'package:mindnest/features/counselor/presentation/counselor_profile_settings_screen.dart';
import 'package:mindnest/features/counselor/presentation/counselor_setup_screen.dart';
import 'package:mindnest/features/home/presentation/home_screen.dart';
import 'package:mindnest/features/home/presentation/privacy_controls_screen.dart';
import 'package:mindnest/features/institutions/presentation/institution_admin_screen.dart';
import 'package:mindnest/features/institutions/presentation/institution_pending_screen.dart';
import 'package:mindnest/features/institutions/presentation/invite_accept_screen.dart';
import 'package:mindnest/features/institutions/presentation/owner_dashboard_screen.dart';
import 'package:mindnest/features/institutions/presentation/admin_messages_screen.dart';
import 'package:mindnest/features/institutions/presentation/institution_admin_profile_screen.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/live/presentation/live_hub_screen.dart';
import 'package:mindnest/features/live/presentation/live_room_screen.dart';
import 'package:mindnest/features/onboarding/data/onboarding_providers.dart';
import 'package:mindnest/features/onboarding/presentation/onboarding_loading_screen.dart';
import 'package:mindnest/features/onboarding/presentation/onboarding_questionnaire_screen.dart';

class AppRoute {
  static const login = '/login';
  static const register = '/register';
  static const registerDetails = '/register-details';
  static const registerInstitution = '/register-institution';
  static const registerInstitutionSchoolRequest =
      '/register-institution-school-request';
  static const registerInstitutionSuccess = '/register-institution-success';
  static const forgotPassword = '/forgot-password';
  static const verifyEmail = '/verify-email';
  static const counselorInviteWaiting = '/counselor-invite-waiting';
  static const inviteAccept = '/invite-accept';
  static const onboarding = '/onboarding';
  static const onboardingLoading = '/onboarding-loading';
  static const counselorSetup = '/counselor-setup';
  static const counselorDashboard = '/counselor-dashboard';
  static const counselorAvailability = '/counselor-availability';
  static const counselorAppointments = '/counselor-appointments';
  static const counselorSettings = '/counselor-settings';
  static const counselorDirectory = '/counselors';
  static const counselorProfile = '/counselor-profile';
  static const studentAppointments = '/student-appointments';
  static const sessionDetails = '/session-details';
  static const notifications = '/notifications';
  static const notificationDetails = '/notification-details';
  static const carePlan = '/care-plan';
  static const crisisCounselorSupport = '/crisis-counselor-support';
  static const liveHub = '/live-hub';
  static const liveRoom = '/live-room';
  static const privacyControls = '/privacy-controls';
  static const home = '/home';
  static const joinInstitution = '/join-institution';
  static const institutionAdmin = '/institution-admin';
  static const institutionAdminProfile = '/institution-admin/profile';
  static const institutionAdminMessages = '/institution-admin/messages';
  static const institutionPending = '/institution-pending';
  static const ownerDashboard = '/owner-dashboard';

  static const inviteIdQuery = 'inviteId';
  static const invitedEmailQuery = 'invitedEmail';
  static const invitedNameQuery = 'invitedName';
  static const institutionNameQuery = 'institutionName';
  static const intendedRoleQuery = 'intendedRole';
  static const registrationIntentQuery = 'registrationIntent';
  static const openJoinCodeQuery = 'openJoinCode';

  static String homeWithJoinCodeIntent() {
    return Uri(
      path: AppRoute.home,
      queryParameters: const <String, String>{openJoinCodeQuery: '1'},
    ).toString();
  }

  static Map<String, String> inviteQueryFromRaw(Map<String, String> raw) {
    final inviteId = (raw[inviteIdQuery] ?? '').trim();
    if (inviteId.isEmpty) {
      return const <String, String>{};
    }
    final cleaned = <String, String>{inviteIdQuery: inviteId};
    final invitedEmail = (raw[invitedEmailQuery] ?? '').trim().toLowerCase();
    if (invitedEmail.isNotEmpty) {
      cleaned[invitedEmailQuery] = invitedEmail;
    }
    final invitedName = (raw[invitedNameQuery] ?? '').trim();
    if (invitedName.isNotEmpty) {
      cleaned[invitedNameQuery] = invitedName;
    }
    final institutionName = (raw[institutionNameQuery] ?? '').trim();
    if (institutionName.isNotEmpty) {
      cleaned[institutionNameQuery] = institutionName;
    }
    final intendedRole = (raw[intendedRoleQuery] ?? '').trim();
    if (intendedRole.isNotEmpty) {
      cleaned[intendedRoleQuery] = intendedRole;
    }
    return cleaned;
  }

  static Map<String, String> inviteQueryFromUri(Uri uri) {
    final fromQuery = inviteQueryFromRaw(uri.queryParameters);
    if (fromQuery.isNotEmpty) {
      return fromQuery;
    }
    final fragment = uri.fragment;
    if (fragment.isEmpty) {
      return const <String, String>{};
    }
    // Fragment may be either "?a=1&b=2" or "a=1&b=2". Handle both.
    String fragmentQuery;
    final queryIndex = fragment.indexOf('?');
    if (queryIndex >= 0 && queryIndex < fragment.length - 1) {
      fragmentQuery = fragment.substring(queryIndex + 1);
    } else {
      fragmentQuery = fragment;
    }
    if (fragmentQuery.trim().isEmpty) {
      return const <String, String>{};
    }
    final parsed = Uri(query: fragmentQuery).queryParameters;
    return inviteQueryFromRaw(parsed);
  }

  static Map<String, String> inviteQuery({
    required String inviteId,
    String? invitedEmail,
    String? invitedName,
    String? institutionName,
    String? intendedRole,
  }) {
    return inviteQueryFromRaw(<String, String>{
      inviteIdQuery: inviteId,
      invitedEmailQuery: invitedEmail ?? '',
      invitedNameQuery: invitedName ?? '',
      institutionNameQuery: institutionName ?? '',
      intendedRoleQuery: intendedRole ?? '',
    });
  }

  static String? registrationIntentFromUri(Uri uri) {
    final normalized = (uri.queryParameters[registrationIntentQuery] ?? '')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static String withInviteAndRegistrationIntent(
    String path,
    Map<String, String> rawInviteQuery, {
    String? registrationIntent,
  }) {
    final inviteQuery = inviteQueryFromRaw(rawInviteQuery);
    final normalizedIntent = (registrationIntent ?? '').trim();
    if (inviteQuery.isEmpty && normalizedIntent.isEmpty) {
      return path;
    }
    final query = <String, String>{...inviteQuery};
    if (normalizedIntent.isNotEmpty) {
      query[registrationIntentQuery] = normalizedIntent;
    }
    return Uri(path: path, queryParameters: query).toString();
  }

  static String withInviteQuery(String path, Map<String, String> rawQuery) {
    final inviteQuery = inviteQueryFromRaw(rawQuery);
    if (inviteQuery.isEmpty) {
      return path;
    }
    return Uri(path: path, queryParameters: inviteQuery).toString();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStateAsync = ref.watch(authStateChangesProvider);
  final profileAsync = ref.watch(currentUserProfileProvider);
  final pendingInviteAsync = ref.watch(pendingUserInviteProvider);
  final currentAdminInstitutionAsync = ref.watch(
    currentAdminInstitutionRequestProvider,
  );
  final onboardingRepository = ref.watch(onboardingRepositoryProvider);
  final counselorRepository = ref.watch(counselorRepositoryProvider);
  final refreshListenable = ref.watch(_routerRefreshListenableProvider);
  final isWindowsLoginOnlyMode =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  final registrationRoutes = <RouteBase>[
    GoRoute(
      path: AppRoute.register,
      builder: (context, state) {
        final inviteQuery = AppRoute.inviteQueryFromUri(state.uri);
        final registrationIntent = AppRoute.registrationIntentFromUri(
          state.uri,
        );
        return RegisterScreen(
          inviteId: inviteQuery[AppRoute.inviteIdQuery],
          invitedEmail: inviteQuery[AppRoute.invitedEmailQuery],
          invitedName: inviteQuery[AppRoute.invitedNameQuery],
          institutionName: inviteQuery[AppRoute.institutionNameQuery],
          intendedRole: inviteQuery[AppRoute.intendedRoleQuery],
          registrationIntent: registrationIntent,
        );
      },
    ),
    GoRoute(
      path: AppRoute.registerDetails,
      builder: (context, state) {
        final inviteQuery = AppRoute.inviteQueryFromUri(state.uri);
        final registrationIntent = AppRoute.registrationIntentFromUri(
          state.uri,
        );
        return RegisterDetailsScreen(
          inviteId: inviteQuery[AppRoute.inviteIdQuery],
          invitedEmail: inviteQuery[AppRoute.invitedEmailQuery],
          invitedName: inviteQuery[AppRoute.invitedNameQuery],
          institutionName: inviteQuery[AppRoute.institutionNameQuery],
          intendedRole: inviteQuery[AppRoute.intendedRoleQuery],
          registrationIntent: registrationIntent,
        );
      },
    ),
    GoRoute(
      path: AppRoute.registerInstitution,
      builder: (context, state) => const RegisterInstitutionScreen(),
    ),
    GoRoute(
      path: AppRoute.registerInstitutionSchoolRequest,
      builder: (context, state) =>
          const RegisterInstitutionSchoolRequestScreen(),
    ),
    GoRoute(
      path: AppRoute.registerInstitutionSuccess,
      builder: (context, state) => RegisterInstitutionSuccessScreen(
        institutionName:
            state.uri.queryParameters[AppRoute.institutionNameQuery],
      ),
    ),
  ];

  return GoRouter(
    initialLocation: AppRoute.login,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = authStateAsync.valueOrNull;
      final isAuthStatePending = authStateAsync.isLoading && authState == null;
      final isEmailVerified = authState?.emailVerified ?? false;
      final location = state.matchedLocation;
      final inviteQuery = AppRoute.inviteQueryFromUri(state.uri);
      final hasInviteContext = inviteQuery.isNotEmpty;
      final isWindowsBlockedRegistrationRoute =
          isWindowsLoginOnlyMode &&
          (location == AppRoute.register ||
              location == AppRoute.registerDetails ||
              location == AppRoute.registerInstitution ||
              location == AppRoute.registerInstitutionSchoolRequest ||
              location == AppRoute.registerInstitutionSuccess);
      final isAuthRoute =
          location == AppRoute.login ||
          location == AppRoute.register ||
          location == AppRoute.registerDetails ||
          location == AppRoute.forgotPassword ||
          location == AppRoute.registerInstitution ||
          location == AppRoute.registerInstitutionSchoolRequest;
      final isPreVerificationOnboardingRoute =
          location == AppRoute.verifyEmail ||
          location == AppRoute.joinInstitution;
      final isCounselorInviteWaitingRoute =
          location == AppRoute.counselorInviteWaiting;
      final isCounselorOpsRoute =
          location == AppRoute.counselorSetup ||
          location == AppRoute.counselorDashboard ||
          location == AppRoute.counselorAvailability ||
          location == AppRoute.counselorAppointments ||
          location == AppRoute.counselorSettings;
      final isSharedCareRoute =
          location == AppRoute.counselorDirectory ||
          location == AppRoute.counselorProfile ||
          location == AppRoute.sessionDetails;
      final isStudentCareRoute =
          location == AppRoute.studentAppointments ||
          location == AppRoute.carePlan;
      final isLiveRoute =
          location == AppRoute.liveHub || location == AppRoute.liveRoom;
      final isOwnerRoute = location == AppRoute.ownerDashboard;
      final isInstitutionAdminRoute =
          location == AppRoute.institutionAdmin ||
          location == AppRoute.institutionAdminProfile ||
          location == AppRoute.institutionAdminMessages;

      try {
        if (isAuthStatePending) {
          return null;
        }

        if (isWindowsBlockedRegistrationRoute) {
          return authState == null
              ? AppRoute.withInviteQuery(AppRoute.login, inviteQuery)
              : AppRoute.home;
        }

        if (authState == null) {
          if (location == AppRoute.inviteAccept) {
            return null;
          }
          if (hasInviteContext) {
            return AppRoute.withInviteQuery(AppRoute.inviteAccept, inviteQuery);
          }
          if (isAuthRoute) {
            return null;
          }
          // Log routing decision when unauthenticated user sent to login.
          trackInviteRouting({
            'event': 'redirect_to_login',
            'location': location,
            'uri': state.uri.toString(),
            'inviteQuery': inviteQuery,
            'timestamp': DateTime.now().toIso8601String(),
          });
          return AppRoute.login;
        }

        if (!isEmailVerified && !isPreVerificationOnboardingRoute) {
          return AppRoute.withInviteQuery(AppRoute.verifyEmail, inviteQuery);
        }

        if (!isEmailVerified) {
          return null;
        }

        if (isOwnerEmail(authState.email)) {
          return isOwnerRoute ? null : AppRoute.ownerDashboard;
        }

        if (profileAsync.isLoading ||
            pendingInviteAsync.isLoading ||
            currentAdminInstitutionAsync.isLoading) {
          return null;
        }

        if (hasInviteContext && location != AppRoute.inviteAccept) {
          // Log when we redirect a logged-in user to invite accept.
          trackInviteRouting({
            'event': 'redirect_to_inviteAccept',
            'location': location,
            'uri': state.uri.toString(),
            'inviteQuery': inviteQuery,
            'timestamp': DateTime.now().toIso8601String(),
          });
          return AppRoute.withInviteQuery(AppRoute.inviteAccept, inviteQuery);
        }

        final profile = profileAsync.valueOrNull;
        final pendingInvite = pendingInviteAsync.valueOrNull;
        final pendingInviteRole = pendingInvite?.intendedRole ?? UserRole.other;
        final role = profile?.role ?? UserRole.other;
        final roleResolved = role != UserRole.other;
        final hasCounselorRegistrationIntent =
            profile?.isCounselorRegistrationIntentPending ?? false;
        final needsCounselorSetup = counselorRepository.requiresSetup(profile);
        final institutionRequest = currentAdminInstitutionAsync.valueOrNull;
        final alreadyInInstitution = (profile?.institutionId ?? '')
            .trim()
            .isNotEmpty;
        // 3. Verified but counselor-registration users stay on the waiting
        // screen even after an invite arrives so they can respond there or
        // from Notifications.
        if (pendingInvite != null && hasCounselorRegistrationIntent) {
          final canRemainInRoute =
              isCounselorInviteWaitingRoute ||
              location == AppRoute.notifications ||
              location == AppRoute.notificationDetails ||
              location == AppRoute.inviteAccept;
          if (!canRemainInRoute) {
            return AppRoute.counselorInviteWaiting;
          }
          return null;
        }

        // 4. Verified but invite pending -> invite accept screen.
        //    Skip this block if the user already belongs to an institution.
        if (pendingInvite != null && !alreadyInInstitution) {
          if (pendingInviteRole == UserRole.student) {
            if (location != AppRoute.home) {
              return AppRoute.homeWithJoinCodeIntent();
            }
            return null;
          }
          if (location != AppRoute.inviteAccept) {
            return AppRoute.withInviteQuery(AppRoute.inviteAccept, inviteQuery);
          }
          return null;
        }

        // 5. Verified, role unresolved -> continue with base app flow.
        if (!roleResolved) {
          if (location != AppRoute.joinInstitution) {
            return AppRoute.home;
          }
          return null;
        }

        if (hasCounselorRegistrationIntent) {
          final canRemainInRoute =
              isCounselorInviteWaitingRoute ||
              location == AppRoute.notifications ||
              location == AppRoute.notificationDetails ||
              location == AppRoute.inviteAccept;
          if (!canRemainInRoute) {
            return AppRoute.counselorInviteWaiting;
          }
        } else if (isCounselorInviteWaitingRoute) {
          if (role == UserRole.institutionAdmin) {
            return AppRoute.institutionAdmin;
          }
          if (role == UserRole.counselor) {
            return needsCounselorSetup
                ? AppRoute.counselorSetup
                : AppRoute.counselorDashboard;
          }
          return AppRoute.home;
        }

        if (!isWindowsLoginOnlyMode &&
            role == UserRole.institutionAdmin &&
            profile?.institutionWelcomePending == true &&
            location != AppRoute.registerInstitutionSuccess) {
          final institutionName = (profile?.institutionName ?? '').trim();
          return institutionName.isEmpty
              ? AppRoute.registerInstitutionSuccess
              : Uri(
                  path: AppRoute.registerInstitutionSuccess,
                  queryParameters: <String, String>{
                    AppRoute.institutionNameQuery: institutionName,
                  },
                ).toString();
        }

        if (isOwnerRoute) {
          return AppRoute.home;
        }

        if (role == UserRole.institutionAdmin) {
          final institutionStatus =
              (institutionRequest?['status'] as String?) ?? 'approved';
          final isInstitutionBlocked = institutionStatus != 'approved';
          if (isInstitutionBlocked &&
              location != AppRoute.institutionPending &&
              location != AppRoute.registerInstitutionSuccess) {
            return AppRoute.institutionPending;
          }
          if (!isInstitutionBlocked &&
              location == AppRoute.institutionPending) {
            return AppRoute.institutionAdmin;
          }
        }

        // 6. Counselor setup gate (counselors do not run wellness onboarding).
        if (role == UserRole.counselor) {
          if (needsCounselorSetup && location != AppRoute.counselorSetup) {
            return AppRoute.counselorSetup;
          }
          if (!needsCounselorSetup && location == AppRoute.counselorSetup) {
            return AppRoute.counselorDashboard;
          }
          if (!needsCounselorSetup &&
              (isAuthRoute || location == AppRoute.verifyEmail)) {
            return AppRoute.counselorDashboard;
          }
        }

        // 7. Verified role set, questionnaire incomplete -> onboarding questionnaire.
        final needsOnboarding = onboardingRepository.requiresQuestionnaire(
          profile,
        );
        if (needsOnboarding && location != AppRoute.onboarding) {
          return AppRoute.onboarding;
        }

        // When onboarding is done, keep users off onboarding route.
        if (!needsOnboarding && location == AppRoute.onboarding) {
          if (role == UserRole.institutionAdmin) {
            return AppRoute.institutionAdmin;
          }
          if (role == UserRole.counselor) {
            return needsCounselorSetup
                ? AppRoute.counselorSetup
                : AppRoute.counselorDashboard;
          }
          return AppRoute.home;
        }

        // 8. Normal dashboard by role.
        if (role == UserRole.institutionAdmin && location == AppRoute.home) {
          return AppRoute.institutionAdmin;
        }

        if (role == UserRole.counselor && location == AppRoute.home) {
          return needsCounselorSetup
              ? AppRoute.counselorSetup
              : AppRoute.counselorDashboard;
        }

        if (role != UserRole.institutionAdmin && isInstitutionAdminRoute) {
          if (role == UserRole.counselor) {
            return needsCounselorSetup
                ? AppRoute.counselorSetup
                : AppRoute.counselorDashboard;
          }
          return AppRoute.home;
        }

        if (role != UserRole.counselor && isCounselorOpsRoute) {
          return role == UserRole.institutionAdmin
              ? AppRoute.institutionAdmin
              : AppRoute.home;
        }

        if (role == UserRole.counselor && isStudentCareRoute) {
          return needsCounselorSetup
              ? AppRoute.counselorSetup
              : AppRoute.counselorDashboard;
        }

        if (role == UserRole.institutionAdmin &&
            (isStudentCareRoute || isSharedCareRoute)) {
          return AppRoute.institutionAdmin;
        }

        if (role == UserRole.institutionAdmin && isLiveRoute) {
          return AppRoute.institutionAdmin;
        }

        if (role == UserRole.individual && isLiveRoute) {
          return AppRoute.home;
        }

        if (role == UserRole.institutionAdmin &&
            (isAuthRoute || location == AppRoute.verifyEmail)) {
          return AppRoute.institutionAdmin;
        }

        if (role != UserRole.institutionAdmin &&
            (isAuthRoute ||
                location == AppRoute.verifyEmail ||
                location == AppRoute.registerInstitutionSuccess)) {
          return AppRoute.home;
        }

        return null;
      } catch (e, st) {
        // Catch unexpected errors in redirect and report for debugging.
        final info = {
          'event': 'redirect_error',
          'error': e.toString(),
          'stack': st.toString(),
          'uri': state.uri.toString(),
          'matchedLocation': state.matchedLocation,
          'timestamp': DateTime.now().toIso8601String(),
        };
        trackInviteRouting(info);
        // Fail open: don't redirect on error so user can still reach the route.
        return null;
      }
    },
    routes: [
      GoRoute(
        path: AppRoute.login,
        builder: (context, state) {
          final inviteQuery = AppRoute.inviteQueryFromUri(state.uri);
          return LoginScreen(
            inviteId: inviteQuery[AppRoute.inviteIdQuery],
            invitedEmail: inviteQuery[AppRoute.invitedEmailQuery],
            invitedName: inviteQuery[AppRoute.invitedNameQuery],
            institutionName: inviteQuery[AppRoute.institutionNameQuery],
            intendedRole: inviteQuery[AppRoute.intendedRoleQuery],
          );
        },
      ),
      if (!isWindowsLoginOnlyMode) ...registrationRoutes,
      GoRoute(
        path: AppRoute.forgotPassword,
        builder: (context, state) {
          final inviteQuery = AppRoute.inviteQueryFromUri(state.uri);
          return ForgotPasswordScreen(
            inviteId: inviteQuery[AppRoute.inviteIdQuery],
            invitedEmail: inviteQuery[AppRoute.invitedEmailQuery],
            invitedName: inviteQuery[AppRoute.invitedNameQuery],
            institutionName: inviteQuery[AppRoute.institutionNameQuery],
            intendedRole: inviteQuery[AppRoute.intendedRoleQuery],
          );
        },
      ),
      GoRoute(
        path: AppRoute.verifyEmail,
        builder: (context, state) {
          final inviteQuery = AppRoute.inviteQueryFromUri(state.uri);
          final registrationIntent = AppRoute.registrationIntentFromUri(
            state.uri,
          );
          return VerifyEmailScreen(
            inviteId: inviteQuery[AppRoute.inviteIdQuery],
            invitedEmail: inviteQuery[AppRoute.invitedEmailQuery],
            invitedName: inviteQuery[AppRoute.invitedNameQuery],
            institutionName: inviteQuery[AppRoute.institutionNameQuery],
            intendedRole: inviteQuery[AppRoute.intendedRoleQuery],
            registrationIntent: registrationIntent,
          );
        },
      ),
      GoRoute(
        path: AppRoute.counselorInviteWaiting,
        builder: (context, state) => const CounselorInviteWaitingScreen(),
      ),
      GoRoute(
        path: AppRoute.inviteAccept,
        builder: (context, state) {
          try {
            final inviteQuery = AppRoute.inviteQueryFromUri(state.uri);
            trackInviteRouting({
              'event': 'inviteAccept_opened',
              'uri': state.uri.toString(),
              'matchedLocation': state.matchedLocation,
              'inviteQuery': inviteQuery,
              'timestamp': DateTime.now().toIso8601String(),
            });
            return InviteAcceptScreen(
              inviteId: inviteQuery[AppRoute.inviteIdQuery],
            );
          } catch (e, st) {
            trackInviteRouting({
              'event': 'inviteAccept_builder_error',
              'error': e.toString(),
              'stack': st.toString(),
              'uri': state.uri.toString(),
              'matchedLocation': state.matchedLocation,
              'timestamp': DateTime.now().toIso8601String(),
            });
            // Re-throw so GoRouter can surface the error during development.
            rethrow;
          }
        },
      ),
      GoRoute(
        path: AppRoute.onboarding,
        builder: (context, state) => const OnboardingQuestionnaireScreen(),
      ),
      GoRoute(
        path: AppRoute.onboardingLoading,
        builder: (context, state) => const OnboardingLoadingScreen(),
      ),
      GoRoute(
        path: AppRoute.counselorSetup,
        builder: (context, state) => const CounselorSetupScreen(),
      ),
      GoRoute(
        path: AppRoute.counselorDashboard,
        builder: (context, state) => const CounselorDashboardScreen(),
      ),
      GoRoute(
        path: AppRoute.counselorAvailability,
        builder: (context, state) => const CounselorAvailabilityScreen(),
      ),
      GoRoute(
        path: AppRoute.counselorAppointments,
        builder: (context, state) => const CounselorAppointmentsScreen(),
      ),
      GoRoute(
        path: AppRoute.counselorSettings,
        builder: (context, state) => const CounselorProfileSettingsScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => DesktopPrimaryShell(
          matchedLocation: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoute.home,
            builder: (context, state) =>
                const HomeScreen(embeddedInDesktopShell: true),
          ),
          GoRoute(
            path: AppRoute.counselorDirectory,
            builder: (context, state) =>
                const CounselorDirectoryScreen(embeddedInDesktopShell: true),
          ),
          GoRoute(
            path: AppRoute.studentAppointments,
            builder: (context, state) =>
                const StudentAppointmentsScreen(embeddedInDesktopShell: true),
          ),
          GoRoute(
            path: AppRoute.liveHub,
            builder: (context, state) {
              final openCreate = state.uri.queryParameters['openCreate'] == '1';
              return LiveHubScreen(
                autoOpenCreate: openCreate,
                embeddedInDesktopShell: true,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.counselorProfile,
        builder: (context, state) {
          final counselorId = state.uri.queryParameters['counselorId'] ?? '';
          return CounselorProfileScreen(counselorId: counselorId);
        },
      ),
      GoRoute(
        path: AppRoute.sessionDetails,
        builder: (context, state) {
          final appointmentId =
              state.uri.queryParameters['appointmentId'] ?? '';
          return SessionDetailsScreen(appointmentId: appointmentId);
        },
      ),
      GoRoute(
        path: AppRoute.notifications,
        builder: (context, state) => const NotificationCenterScreen(),
      ),
      GoRoute(
        path: AppRoute.notificationDetails,
        builder: (context, state) {
          final notificationId =
              state.uri.queryParameters['notificationId'] ?? '';
          return NotificationDetailsScreen(notificationId: notificationId);
        },
      ),
      GoRoute(
        path: AppRoute.carePlan,
        builder: (context, state) => const StudentCarePlanScreen(),
      ),
      GoRoute(
        path: AppRoute.crisisCounselorSupport,
        builder: (context, state) => const CrisisCounselorSupportScreen(),
      ),
      GoRoute(
        path: AppRoute.liveRoom,
        builder: (context, state) {
          final sessionId = state.uri.queryParameters['sessionId'] ?? '';
          return LiveRoomScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: AppRoute.privacyControls,
        builder: (context, state) => const PrivacyControlsScreen(),
      ),
      GoRoute(
        path: AppRoute.joinInstitution,
        redirect: (context, state) => AppRoute.homeWithJoinCodeIntent(),
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: AppRoute.institutionAdmin,
        builder: (context, state) => const InstitutionAdminScreen(),
      ),
      GoRoute(
        path: AppRoute.institutionAdminProfile,
        builder: (context, state) => const InstitutionAdminProfileScreen(),
      ),
      GoRoute(
        path: AppRoute.institutionAdminMessages,
        builder: (context, state) => const AdminMessagesScreen(),
      ),
      GoRoute(
        path: AppRoute.institutionPending,
        builder: (context, state) => const InstitutionPendingScreen(),
      ),
      GoRoute(
        path: AppRoute.ownerDashboard,
        builder: (context, state) => const OwnerDashboardScreen(),
      ),
    ],
  );
});

final _routerRefreshListenableProvider = Provider<ValueNotifier<int>>((ref) {
  final notifier = ValueNotifier<int>(0);

  void notify() {
    notifier.value++;
  }

  ref.listen<AsyncValue<AppAuthUser?>>(authStateChangesProvider, (
    previous,
    next,
  ) {
    notify();
  });
  ref.listen<AsyncValue<UserProfile?>>(
    currentUserProfileProvider,
    (previous, next) => notify(),
  );
  ref.listen<AsyncValue<dynamic>>(
    pendingUserInviteProvider,
    (previous, next) => notify(),
  );
  ref.listen<AsyncValue<dynamic>>(
    currentAdminInstitutionRequestProvider,
    (previous, next) => notify(),
  );

  ref.onDispose(notifier.dispose);
  return notifier;
});
