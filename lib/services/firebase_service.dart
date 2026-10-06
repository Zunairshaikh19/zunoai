import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/history_item.dart';
import '../models/image_prompt.dart';
import '../models/notification_model.dart';
import '../models/support_message.dart';
import '../models/user_model.dart';
import 'api_client.dart';

/// Result of a successful generation.
class GenerationResult {
  final String imageUrl;
  final String? historyId;
  final int? coins;
  const GenerationResult({required this.imageUrl, this.historyId, this.coins});
}

/// Everything that changes coins, premium, ad counters, streaks or referrals
/// goes through the backend ([ApiClient]) — Firestore security rules do not
/// allow the app to write those fields itself.
class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final ApiClient _api = ApiClient();

  /// Referral code typed at signup; kept until the profile is created.
  String? _pendingReferral;

  /// Whether the referral code typed at the last signup was accepted (null = none typed).
  bool? lastSignupReferralApplied;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --- Auth Methods ---

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    await ensureProfile();
    return userCredential;
  }

  Future<UserCredential> signUp(
    String email,
    String password, {
    String? referralCode,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    _pendingReferral = (referralCode ?? '').trim().toUpperCase();
    try {
      await cred.user?.sendEmailVerification();
    } catch (e) {
      debugPrint('Could not send verification email: $e');
    }
    final hadCode = _pendingReferral != null && _pendingReferral!.isNotEmpty;
    final applied = await ensureProfile();
    lastSignupReferralApplied = hadCode ? applied : null;
    return cred;
  }

  Future<UserCredential> login(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> resendVerificationEmail() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  Future<void> signOut() async {
    _pendingReferral = null;
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  /// Permanently deletes the account and all its data (server-side), then
  /// signs out locally. Required by Google Play for apps with accounts.
  Future<void> deleteAccount() async {
    await _api.post('economy', {'action': 'delete-account'}, timeout: const Duration(seconds: 60));
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  // --- Profile ---

  Future<UserModel?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      return UserModel.fromMap(doc.data()!, uid);
    }
    return null;
  }

  Stream<UserModel?> userStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null && (doc.data()!['email'] != null || doc.data()!['profileCreated'] == true)) {
        return UserModel.fromMap(doc.data()!, uid);
      }
      return null;
    });
  }

  /// Creates the profile on the server (signup bonus, referral code, optional
  /// referral reward). Safe to call repeatedly — it is a no-op once the
  /// profile exists. Returns true if a typed referral code was accepted.
  Future<bool> ensureProfile() async {
    final referral = _pendingReferral;
    final data = await _api.post('economy', {
      'action': 'init-profile',
      if (referral != null && referral.isNotEmpty) 'referralCode': referral,
    });
    _pendingReferral = null;
    return data['referralApplied'] == true;
  }

  Future<String> _uploadImage(File file) async {
    final bytes = await file.readAsBytes();
    final data = await _api.post(
      'upload-image',
      {'imageBase64': base64Encode(bytes)},
      timeout: const Duration(seconds: 60),
    );
    return data['url'] as String;
  }

  Future<String> uploadProfilePicture(String uid, File imageFile) async {
    final url = await _uploadImage(imageFile);
    await _firestore.collection('users').doc(uid).update({'photoUrl': url});
    return url;
  }

  Future<String> uploadAttachment(File file) async {
    return await _uploadImage(file);
  }

  Future<void> updateDisplayName(String uid, String name) async {
    await _firestore.collection('users').doc(uid).update({'displayName': name});
  }

  Future<void> updateLastActivity(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'lastActivity': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error updating last activity: $e");
    }
  }

  Future<void> updateFcmToken(String uid, String? token) async {
    try {
      await _firestore.collection('users').doc(uid).update({'fcmToken': token});
    } catch (e) {
      debugPrint("Error updating FCM token: $e");
    }
  }

  /// One-time choice (male/female/unisex) that decides which prompts show up
  /// in this user's gallery.
  Future<void> updateUserGender(String uid, String gender) async {
    await _firestore.collection('users').doc(uid).update({'gender': gender});
  }

  // --- Dashboard Data ---

  Future<List<ImagePrompt>> getImagePrompts() async {
    final snapshot = await _firestore.collection('prompts').get();
    return snapshot.docs
        .map((doc) => ImagePrompt.fromMap(doc.data(), doc.id))
        .toList();
  }

  // --- Economy (all server-side) ---

  /// Credits today's daily bonus if it hasn't been credited yet (UTC day).
  Future<void> claimDaily() async {
    await _api.post('economy', {'action': 'claim-daily'});
  }

  /// Claims today's login-streak reward. Returns the coins granted.
  Future<({int streak, int reward})> claimDailyStreak() async {
    final data = await _api.post('economy', {'action': 'claim-streak'});
    return (streak: (data['streak'] as num).toInt(), reward: (data['reward'] as num).toInt());
  }

  Future<int> redeemReferralCode(String code) async {
    final data = await _api.post('economy', {'action': 'redeem-referral', 'code': code});
    return (data['reward'] as num?)?.toInt() ?? 0;
  }

  Future<void> unlockWatermark(String historyId) async {
    await _api.post('economy', {'action': 'unlock-watermark', 'historyId': historyId});
  }

  // --- History ---

  Stream<List<HistoryItem>> historyStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('history')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => HistoryItem.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<List<HistoryItem>> getUserHistory(String uid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('history')
        .orderBy('timestamp', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => HistoryItem.fromMap(doc.data(), doc.id))
        .toList();
  }

  // --- Notifications ---

  Stream<List<NotificationModel>> getNotifications(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<void> markNotificationAsRead(String uid, String notificationId) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // --- Premium ---

  /// Verifies a completed Play purchase on the server and activates premium.
  /// Throws [ApiException] if the purchase is not genuine/active.
  Future<DateTime> activatePremium({
    required String productId,
    required String purchaseToken,
  }) async {
    final data = await _api.post(
      'confirm-purchase',
      {'productId': productId, 'purchaseToken': purchaseToken, 'platform': Platform.isIOS ? 'ios' : 'android'},
      timeout: const Duration(seconds: 45),
    );
    return DateTime.parse(data['premiumExpiresAt'] as String);
  }

  /// Re-checks the stored subscription with Google Play (renewals, cancels).
  Future<void> refreshPremium() async {
    await _api.post('confirm-purchase', {'refresh': true}, timeout: const Duration(seconds: 45));
  }

  // --- Generation ---

  /// Asks the server to generate an image. The server picks the prompt (by
  /// [promptId]), charges coins atomically, refunds on failure and records the
  /// history entry itself.
  Future<GenerationResult> generateImageSecurely({
    required String promptId,
    required File referenceImage,
    File? referenceImage2,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ApiException('Please sign in first.', code: 'UNAUTHENTICATED', status: 401);
    await _ensureEmailVerified(user);

    final bytes = await referenceImage.readAsBytes();
    final bytes2 = referenceImage2 != null ? await referenceImage2.readAsBytes() : null;

    final data = await _api.post(
      'generate-image',
      {
        'promptId': promptId,
        'referenceImageBase64': base64Encode(bytes),
        if (bytes2 != null) 'referenceImageBase64_2': base64Encode(bytes2),
      },
      timeout: const Duration(seconds: 130),
    );

    final url = data['imageUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw const ApiException('Generation failed. Please try again.', code: 'GENERATION_FAILED');
    }
    return GenerationResult(
      imageUrl: url,
      historyId: data['historyId'] as String?,
      coins: (data['coins'] as num?)?.toInt(),
    );
  }

  /// Email/password accounts must confirm their email before spending coins.
  Future<void> _ensureEmailVerified(User user) async {
    final usesPassword = user.providerData.any((p) => p.providerId == 'password');
    if (!usesPassword || user.emailVerified) return;

    await user.reload();
    final fresh = _auth.currentUser;
    if (fresh != null && !fresh.emailVerified) {
      throw const ApiException(
        'Please verify your email address first — we sent you a link. Check your inbox (and spam).',
        code: 'EMAIL_NOT_VERIFIED',
        status: 403,
      );
    }
    await fresh?.getIdToken(true); // pick up the new email_verified claim
  }

  // --- Support Chat ---

  Stream<List<SupportMessage>> getSupportMessages(String uid) {
    return _firestore
        .collection('support_tickets')
        .doc(uid)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SupportMessage.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<void> sendSupportMessage(String uid, SupportMessage message) async {
    await _firestore
        .collection('support_tickets')
        .doc(uid)
        .set({
          'lastMessage': message.text,
          'lastTimestamp': FieldValue.serverTimestamp(),
          'userId': uid,
          'status': 'open',
        }, SetOptions(merge: true));

    await _firestore
        .collection('support_tickets')
        .doc(uid)
        .collection('messages')
        .add(message.toMap());
  }
}
