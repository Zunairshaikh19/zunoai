import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Error returned by (or on the way to) a backend Edge Function. [message] is
/// always safe to show to the user.
class ApiException implements Exception {
  final String message;
  final String code;
  final int status;

  const ApiException(this.message, {this.code = 'ERROR', this.status = 0});

  bool get isInsufficientCoins => code == 'INSUFFICIENT_COINS';
  bool get isEmailNotVerified => code == 'EMAIL_NOT_VERIFIED';
  bool get isPremiumOnly => code == 'PREMIUM_ONLY';

  @override
  String toString() => message;
}

/// Thin client for the Supabase Edge Functions. Every call carries the user's
/// Firebase ID token (and an App Check token when available); the server
/// verifies both, so the app never needs — and never contains — any secret.
class ApiClient {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ylenfbneddyuzrkckaul.supabase.co/functions/v1',
  );

  Future<Map<String, dynamic>> post(
    String function,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const ApiException('Please sign in first.', code: 'UNAUTHENTICATED', status: 401);
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final idToken = await user.getIdToken(attempt > 0);
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      };
      try {
        final appCheckToken = await FirebaseAppCheck.instance.getToken();
        if (appCheckToken != null) headers['X-Firebase-AppCheck'] = appCheckToken;
      } catch (e) {
        debugPrint('App Check token unavailable: $e');
      }

      http.Response res;
      try {
        res = await http
            .post(Uri.parse('$baseUrl/$function'), headers: headers, body: jsonEncode(body))
            .timeout(timeout);
      } on TimeoutException {
        throw const ApiException(
          'This is taking longer than expected. Please check again in a moment.',
          code: 'TIMEOUT',
        );
      } on SocketException {
        throw const ApiException('No internet connection. Please try again.', code: 'OFFLINE');
      } on http.ClientException {
        throw const ApiException('No internet connection. Please try again.', code: 'OFFLINE');
      }

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Non-JSON body (gateway error page, etc.) — handled below.
      }

      if (res.statusCode == 200 && data['success'] == true) return data;

      final code = (data['code'] as String?) ?? 'ERROR';
      // An expired token is the only error worth one silent retry.
      if (res.statusCode == 401 && code == 'UNAUTHENTICATED' && attempt == 0) continue;

      throw ApiException(
        (data['error'] as String?) ?? 'Something went wrong. Please try again.',
        code: code,
        status: res.statusCode,
      );
    }
    throw const ApiException('Something went wrong. Please try again.');
  }
}
