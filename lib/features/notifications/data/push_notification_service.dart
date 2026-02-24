import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static const String _androidChannelId = 'mindnest_alerts';
  static const String _androidChannelName = 'MindNest Alerts';
  static const String _androidChannelDescription =
      'Appointments, live updates, and reminders.';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _bootstrapped = false;
  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static String? _currentUserId;

  static Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    if (!kIsWeb) {
      await _initLocalNotifications();
    }

    await _requestPermission();

    await FirebaseMessaging.instance.setAutoInitEnabled(true);

    if (!kIsWeb) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    _onMessageSub = FirebaseMessaging.onMessage.listen((message) async {
      await _showForegroundNotification(message);
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      final previousUserId = _currentUserId;
      _currentUserId = user?.uid;

      if (previousUserId != null && previousUserId != _currentUserId) {
        await _disableTokensForUser(previousUserId);
      }

      if (user != null) {
        await _registerCurrentDeviceToken(user.uid);
      }
    });

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return;
      }
      await _upsertToken(uid: uid, token: token);
    });
  }

  static Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    await _onMessageSub?.cancel();
    _authSub = null;
    _tokenRefreshSub = null;
    _onMessageSub = null;
    _bootstrapped = false;
  }

  static Future<void> _requestPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (_) {
      // Keep app startup resilient if notification permission APIs fail.
    }
  }

  static Future<void> _registerCurrentDeviceToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) {
        return;
      }
      await _upsertToken(uid: uid, token: token.trim());
    } catch (_) {
      // Keep app startup resilient if token acquisition fails.
    }
  }

  static Future<void> _upsertToken({
    required String uid,
    required String token,
  }) async {
    final docId = _tokenDocId(token);
    await FirebaseFirestore.instance
        .collection('user_push_tokens')
        .doc(docId)
        .set({
          'userId': uid,
          'token': token,
          'platform': defaultTargetPlatform.name,
          'isEnabled': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  static Future<void> _disableTokensForUser(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('user_push_tokens')
        .where('userId', isEqualTo: uid)
        .where('isEnabled', isEqualTo: true)
        .limit(25)
        .get();
    if (snapshot.docs.isEmpty) {
      return;
    }
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'isEnabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static String _tokenDocId(String token) {
    return base64UrlEncode(utf8.encode(token)).replaceAll('=', '');
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _localNotifications.initialize(settings);

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: _androidChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (kIsWeb) {
      return;
    }

    final title =
        message.notification?.title ??
        (message.data['title'] as String?)?.trim() ??
        'MindNest';
    final body =
        message.notification?.body ??
        (message.data['body'] as String?)?.trim() ??
        'You have a new update.';

    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _localNotifications.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: _androidChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ticker: 'mindnest',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}
