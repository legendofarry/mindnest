import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Simple invite routing diagnostics helper.
// By default `kInviteTrackingUrl` is empty (no network calls).
// Set it to a valid URL to receive JSON payloads for failed flows.
const String kInviteTrackingUrl = '';

Future<void> trackInviteRouting(Map<String, Object?> payload) async {
  // Always print locally for immediate debugging.
  debugPrint('[invite_debug] ${jsonEncode(payload)}');

  if (kInviteTrackingUrl.isEmpty) {
    return;
  }

  try {
    final res = await http.post(
      Uri.parse(kInviteTrackingUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    debugPrint('[invite_debug] tracking status: ${res.statusCode}');
  } catch (e, st) {
    debugPrint('[invite_debug] tracking failed: $e\n$st');
  }
}
