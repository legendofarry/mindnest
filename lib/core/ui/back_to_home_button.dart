import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';

class BackToHomeButton extends StatelessWidget {
  const BackToHomeButton({super.key});

  static const String _sourceQueryKey = 'from';
  static const String _notificationSourceValue = 'notifications';
  static const String _profileSourceValue = 'profile';
  static const String _counselorsSourceValue = 'counselors';
  static const String _studentAppointmentsSourceValue = 'studentAppointments';
  static const String _openProfileQueryKey = 'openProfile';
  static const String _profileOpenTokenQueryKey = 'profileOpenTs';

  @override
  Widget build(BuildContext context) {
    final source = GoRouterState.of(
      context,
    ).uri.queryParameters[_sourceQueryKey];
    final shouldReturnToNotifications = source == _notificationSourceValue;
    final shouldReturnToProfile = source == _profileSourceValue;
    final shouldReturnToCounselors = source == _counselorsSourceValue;
    final shouldReturnToStudentAppointments =
        source == _studentAppointmentsSourceValue;
    return IconButton(
      tooltip: shouldReturnToNotifications
          ? 'Back to Notifications'
          : shouldReturnToStudentAppointments
          ? 'Back to Sessions'
          : shouldReturnToCounselors
          ? 'Back to Counselors'
          : shouldReturnToProfile
          ? 'Back to Profile'
          : 'Back to Home',
      onPressed: () {
        if (shouldReturnToNotifications) {
          context.go(AppRoute.notifications);
          return;
        }
        if (shouldReturnToCounselors) {
          context.go(AppRoute.counselorDirectory);
          return;
        }
        if (shouldReturnToStudentAppointments) {
          context.go(AppRoute.studentAppointments);
          return;
        }
        if (shouldReturnToProfile) {
          final homeWithProfile = Uri(
            path: AppRoute.home,
            queryParameters: <String, String>{
              _openProfileQueryKey: '1',
              _profileOpenTokenQueryKey: DateTime.now().millisecondsSinceEpoch
                  .toString(),
            },
          );
          context.go(homeWithProfile.toString());
          return;
        }
        context.go(AppRoute.home);
      },
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }
}
