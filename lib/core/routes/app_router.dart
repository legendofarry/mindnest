import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/go_router_refresh_stream.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/forgot_password_screen.dart';
import 'package:mindnest/features/auth/presentation/login_screen.dart';
import 'package:mindnest/features/auth/presentation/register_details_screen.dart';
import 'package:mindnest/features/auth/presentation/register_screen.dart';
import 'package:mindnest/features/auth/presentation/register_institution_screen.dart';
import 'package:mindnest/features/auth/presentation/verify_email_screen.dart';
import 'package:mindnest/features/care/presentation/counselor_appointments_screen.dart';
import 'package:mindnest/features/care/presentation/counselor_availability_screen.dart';
import 'package:mindnest/features/care/presentation/counselor_directory_screen.dart';
import 'package:mindnest/features/care/presentation/counselor_profile_screen.dart';
import 'package:mindnest/features/care/presentation/crisis_counselor_support_screen.dart';
import 'package:mindnest/features/care/presentation/notification_center_screen.dart';
import 'package:mindnest/features/care/presentation/session_details_screen.dart';
import 'package:mindnest/features/care/presentation/student_care_plan_screen.dart';
import 'package:mindnest/features/care/presentation/student_appointments_screen.dart';
import 'package:mindnest/features/counselor/data/counselor_providers.dart';
import 'package:mindnest/features/counselor/presentation/counselor_dashboard_screen.dart';
import 'package:mindnest/features/counselor/presentation/counselor_profile_settings_screen.dart';
import 'package:mindnest/features/counselor/presentation/counselor_setup_screen.dart';
import 'package:mindnest/features/home/presentation/home_screen.dart';
import 'package:mindnest/features/home/presentation/privacy_controls_screen.dart';
import 'package:mindnest/features/institutions/presentation/institution_admin_screen.dart';
import 'package:mindnest/features/institutions/presentation/invite_accept_screen.dart';
import 'package:mindnest/features/institutions/presentation/join_institution_screen.dart';
import 'package:mindnest/features/institutions/presentation/post_signup_decision_screen.dart';
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
  static const forgotPassword = '/forgot-password';
  static const postSignup = '/post-signup';
  static const verifyEmail = '/verify-email';
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
  static const carePlan = '/care-plan';
  static const crisisCounselorSupport = '/crisis-counselor-support';
  static const liveHub = '/live-hub';
  static const liveRoom = '/live-room';
  static const privacyControls = '/privacy-controls';
  static const home = '/home';
  static const joinInstitution = '/join-institution';
  static const institutionAdmin = '/institution-admin';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final firebaseAuth = ref.watch(firebaseAuthProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  final profileAsync = ref.watch(currentUserProfileProvider);
  final pendingInviteAsync = ref.watch(pendingUserInviteProvider);
  final onboardingRepository = ref.watch(onboardingRepositoryProvider);
  final counselorRepository = ref.watch(counselorRepositoryProvider);

  return GoRouter(
    initialLocation: AppRoute.login,
    refreshListenable: GoRouterRefreshStream(authRepository.authStateChanges()),
    redirect: (context, state) {
      final authState = firebaseAuth.currentUser;
      final isEmailVerified = authState?.emailVerified ?? false;
      final location = state.matchedLocation;
      final isAuthRoute =
          location == AppRoute.login ||
          location == AppRoute.register ||
          location == AppRoute.registerDetails ||
          location == AppRoute.forgotPassword ||
          location == AppRoute.registerInstitution;
      final isPreVerificationOnboardingRoute =
          location == AppRoute.verifyEmail ||
          location == AppRoute.joinInstitution ||
          location == AppRoute.postSignup;
      final isCounselorOpsRoute =
          location == AppRoute.counselorSetup ||
          location == AppRoute.counselorDashboard ||
          location == AppRoute.counselorAvailability ||
          location == AppRoute.counselorAppointments ||
          location == AppRoute.counselorSettings;
      final isStudentCareRoute =
          location == AppRoute.counselorDirectory ||
          location == AppRoute.counselorProfile ||
          location == AppRoute.studentAppointments ||
          location == AppRoute.sessionDetails ||
          location == AppRoute.carePlan;
      final isLiveRoute =
          location == AppRoute.liveHub || location == AppRoute.liveRoom;

      if (authState == null) {
        return isAuthRoute ? null : AppRoute.login;
      }

      if (!isEmailVerified && !isPreVerificationOnboardingRoute) {
        return AppRoute.verifyEmail;
      }

      if (!isEmailVerified) {
        return null;
      }

      if (profileAsync.isLoading || pendingInviteAsync.isLoading) {
        return null;
      }

      final profile = profileAsync.valueOrNull;
      final pendingInvite = pendingInviteAsync.valueOrNull;
      final role = profile?.role ?? UserRole.other;
      final roleResolved = role != UserRole.other;
      final needsCounselorSetup = counselorRepository.requiresSetup(profile);

      // 3. Verified but invite pending -> invite accept screen.
      if (pendingInvite != null) {
        if (location != AppRoute.inviteAccept) {
          return AppRoute.inviteAccept;
        }
        return null;
      }

      // 4. Verified, role unresolved -> post-signup role selection.
      if (!roleResolved) {
        if (location != AppRoute.postSignup &&
            location != AppRoute.joinInstitution) {
          return AppRoute.postSignup;
        }
        return null;
      }

      // 5. Counselor setup gate (counselors do not run wellness onboarding).
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

      // 6. Verified role set, questionnaire incomplete -> onboarding questionnaire.
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

      // 7. Normal dashboard by role.
      if (role == UserRole.institutionAdmin && location == AppRoute.home) {
        return AppRoute.institutionAdmin;
      }

      if (role == UserRole.counselor && location == AppRoute.home) {
        return needsCounselorSetup
            ? AppRoute.counselorSetup
            : AppRoute.counselorDashboard;
      }

      if (role != UserRole.institutionAdmin &&
          location == AppRoute.institutionAdmin) {
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

      if (role == UserRole.institutionAdmin && isStudentCareRoute) {
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
          (isAuthRoute || location == AppRoute.verifyEmail)) {
        return AppRoute.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoute.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoute.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoute.registerDetails,
        builder: (context, state) => const RegisterDetailsScreen(),
      ),
      GoRoute(
        path: AppRoute.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoute.registerInstitution,
        builder: (context, state) => const RegisterInstitutionScreen(),
      ),
      GoRoute(
        path: AppRoute.postSignup,
        builder: (context, state) => const PostSignupDecisionScreen(),
      ),
      GoRoute(
        path: AppRoute.verifyEmail,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoute.inviteAccept,
        builder: (context, state) => const InviteAcceptScreen(),
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
      GoRoute(
        path: AppRoute.counselorDirectory,
        builder: (context, state) => const CounselorDirectoryScreen(),
      ),
      GoRoute(
        path: AppRoute.counselorProfile,
        builder: (context, state) {
          final counselorId = state.uri.queryParameters['counselorId'] ?? '';
          return CounselorProfileScreen(counselorId: counselorId);
        },
      ),
      GoRoute(
        path: AppRoute.studentAppointments,
        builder: (context, state) => const StudentAppointmentsScreen(),
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
        path: AppRoute.carePlan,
        builder: (context, state) => const StudentCarePlanScreen(),
      ),
      GoRoute(
        path: AppRoute.crisisCounselorSupport,
        builder: (context, state) => const CrisisCounselorSupportScreen(),
      ),
      GoRoute(
        path: AppRoute.liveHub,
        builder: (context, state) {
          final openCreate = state.uri.queryParameters['openCreate'] == '1';
          return LiveHubScreen(autoOpenCreate: openCreate);
        },
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
        path: AppRoute.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoute.joinInstitution,
        builder: (context, state) => const JoinInstitutionScreen(),
      ),
      GoRoute(
        path: AppRoute.institutionAdmin,
        builder: (context, state) => const InstitutionAdminScreen(),
      ),
    ],
  );
});
