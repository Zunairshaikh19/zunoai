import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import '../models/image_prompt.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/history_item.dart';
import '../models/notification_model.dart';
import '../models/support_message.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // ImgBB API Key — pass at build time with:
  //   flutter build ... --dart-define=IMGBB_API_KEY=your_key
  // (rotate the old key on imgbb.com since it was previously committed to source control)
  static const String _imgBBKey = String.fromEnvironment('IMGBB_API_KEY');

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --- Auth Methods ---
  
  Future<UserCredential?> signInWithGoogle({int signupBonus = 40, int referralReward = 40}) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user != null) {
        final existingProfile = await getUserData(user.uid);
        if (existingProfile == null) {
          await createUserProfile(user, signupBonus: signupBonus, referralReward: referralReward);
        }
      }
      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserCredential> signUp(
    String email,
    String password, {
    String? referralCode,
    int signupBonus = 40,
    int referralReward = 40,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await createUserProfile(
      cred.user!,
      referredBy: referralCode,
      signupBonus: signupBonus,
      referralReward: referralReward,
    );
    return cred;
  }

  Future<UserCredential> login(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // --- Profile & Referral Logic ---

  Future<UserModel?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data()!, uid);
    }
    return null;
  }

  Stream<UserModel?> userStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data()!, uid);
      }
      return null;
    });
  }

  Future<void> createUserProfile(
    User user, {
    String? referredBy,
    int signupBonus = 40,
    int referralReward = 40,
  }) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final referralCode = const Uuid().v4().substring(0, 8).toUpperCase();

    int initialCoins = signupBonus;
    if (referredBy != null && referredBy.isNotEmpty) {
      initialCoins += referralReward;
    }

    // Runs as a transaction, not a plain read-then-write, for two reasons:
    // 1. signUp()/signInWithGoogle() and UserNotifier's "no profile yet"
    //    fallback can both call this for the same brand-new uid at nearly the
    //    same time; a transaction lets Firestore serialize them so only one
    //    ever actually creates the profile (with one referral code) instead
    //    of a plain read-then-write race letting both think they're first.
    // 2. An unrelated, unawaited write (updateLastActivity()/updateFcmToken(),
    //    both fired the moment auth state changes) can land first and create
    //    a *bare partial* doc — Firestore's `.set(merge:true)` upserts. A
    //    naive "does the doc exist?" check would then see that partial doc
    //    and skip real profile creation forever, leaving the account with no
    //    email/referralCode/tier ever written (exactly the bug this fixes).
    // The check is specifically "does `email` have a real value", not "does
    // the doc exist" — and any field a concurrent call already wrote onto
    // that partial doc (coins, dailyAdsWatched, loginStreak, lastStreakClaim,
    // fcmToken, lastActivity) is read back and preserved rather than reset,
    // so nothing earned during that race window is lost.
    final didCreate = await _firestore.runTransaction<bool>((tx) async {
      final snapshot = await tx.get(docRef);
      final existingData = snapshot.data();
      final existingEmail = existingData?['email'] as String?;
      if (existingEmail != null && existingEmail.isNotEmpty) {
        return false; // A real profile already exists — never overwrite it.
      }

      final newUser = UserModel(
        uid: user.uid,
        email: user.email ?? '',
        displayName: (existingData?['displayName'] as String?) ?? user.displayName,
        photoUrl: (existingData?['photoUrl'] as String?) ?? user.photoURL,
        referralCode: referralCode,
        referredBy: referredBy,
        lastDailyReset: DateTime.now(),
        coins: (existingData?['coins'] as int?) ?? initialCoins,
        dailyAdsWatched: (existingData?['dailyAdsWatched'] as int?) ?? 0,
        referralCount: (existingData?['referralCount'] as int?) ?? 0,
        loginStreak: (existingData?['loginStreak'] as int?) ?? 0,
        lastStreakClaim: (existingData?['lastStreakClaim'] as Timestamp?)?.toDate(),
        fcmToken: existingData?['fcmToken'] as String?,
        lastActivity: (existingData?['lastActivity'] as Timestamp?)?.toDate(),
      );

      tx.set(docRef, newUser.toMap(), SetOptions(merge: true));
      return true;
    });

    if (!didCreate) return;

    await _firestore.collection('referralCodes').doc(referralCode).set({'uid': user.uid});

    if (referredBy != null && referredBy.isNotEmpty) {
      final codeDoc = await _firestore.collection('referralCodes').doc(referredBy).get();
      final inviterUid = codeDoc.data()?['uid'] as String?;

      if (inviterUid != null) {
        await _firestore.collection('users').doc(inviterUid).update({
          'coins': FieldValue.increment(referralReward),
          'referralCount': FieldValue.increment(1),
        });
      }
    }
  }

  Future<String> _uploadToImgBB(File file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.imgbb.com/1/upload?key=$_imgBBKey'),
    );
    request.files.add(await http.MultipartFile.fromPath('image', file.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      final resData = await response.stream.bytesToString();
      final json = jsonDecode(resData);
      return json['data']['url'];
    } else {
      throw "Hosting failed: ${response.statusCode}";
    }
  }

  Future<String> uploadProfilePicture(String uid, File imageFile) async {
    try {
      final url = await _uploadToImgBB(imageFile);
      await _firestore.collection('users').doc(uid).update({'photoUrl': url});
      return url;
    } catch (e) {
      throw "Upload error: $e";
    }
  }

  Future<String> uploadAttachment(File file) async {
    return await _uploadToImgBB(file);
  }

  Future<void> updateDisplayName(String uid, String name) async {
    await _firestore.collection('users').doc(uid).update({'displayName': name});
  }

  Future<void> updateLastActivity(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'lastActivity': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error updating last activity: $e");
    }
  }

  Future<void> updateFcmToken(String uid, String? token) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error updating FCM token: $e");
    }
  }

  // --- Dashboard Data ---

  Future<List<ImagePrompt>> getImagePrompts() async {
    final snapshot = await _firestore.collection('prompts').get();
    return snapshot.docs
        .map((doc) => ImagePrompt.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<void> updateUserCoins(String uid, int newBalance) async {
    await _firestore.collection('users').doc(uid).update({'coins': newBalance});
  }

  /// One-time choice (male/female/unisex) that decides which prompts show up
  /// in this user's gallery.
  Future<void> updateUserGender(String uid, String gender) async {
    await _firestore.collection('users').doc(uid).update({'gender': gender});
  }

  Future<void> updateDailyAdCount(String uid, int count) async {
    await _firestore.collection('users').doc(uid).update({'dailyAdsWatched': count});
  }

  Future<void> backfillReferralCode(String uid) async {
    final code = const Uuid().v4().substring(0, 8).toUpperCase();
    await _firestore.collection('users').doc(uid).update({'referralCode': code});
    await _firestore.collection('referralCodes').doc(code).set({'uid': uid});
  }

  Future<void> claimDailyStreak(String uid, {required int newStreak, required int coins}) async {
    await _firestore.collection('users').doc(uid).update({
      'loginStreak': newStreak,
      'lastStreakClaim': Timestamp.fromDate(DateTime.now()),
      'coins': FieldValue.increment(coins),
    });
  }

  Future<void> expirePremium(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'tier': 'free',
      'premiumExpiresAt': null,
    });
  }

  Future<void> resetDailyLimits(String uid, int dailyBonusCoins) async {
    // Adds the daily bonus on top of whatever the user already has — a plain
    // `set` here would wipe out coins they earned from ads/referrals since
    // their last reset, which is not what "daily bonus" is supposed to mean.
    await _firestore.collection('users').doc(uid).update({
      'coins': FieldValue.increment(dailyBonusCoins),
      'dailyAdsWatched': 0,
      'lastDailyReset': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> saveToHistory(String uid, HistoryItem item) async {
    debugPrint("Saving history for user: $uid");
    try {
      await _firestore.collection('users').doc(uid).collection('history').add(item.toMap());
      debugPrint("History saved successfully.");
    } catch (e) {
      debugPrint("Failed to save history: $e");
      rethrow;
    }
  }

  Stream<List<HistoryItem>> historyStream(String uid) {
    debugPrint("Listening to history stream for: $uid");
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('history')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          debugPrint("Received history update. Count: ${snapshot.docs.length}");
          return snapshot.docs
            .map((doc) => HistoryItem.fromMap(doc.data(), doc.id))
            .toList();
        });
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

  Future<void> sendNotification(String uid, String title, String message) async {
    await _firestore.collection('users').doc(uid).collection('notifications').add({
      'title': title,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  Future<void> markNotificationAsRead(String uid, String notificationId) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // Supabase Edge Function URL (100% Free & Secure Proxy)
  static const String _supabaseFunctionUrl = "https://ylenfbneddyuzrkckaul.supabase.co/functions/v1/generate-image";
  static const String _confirmPurchaseUrl = "https://ylenfbneddyuzrkckaul.supabase.co/functions/v1/confirm-purchase";

  /// Verifies a completed store purchase with the backend and activates the
  /// user's premium tier there — the client can never set `tier` itself
  /// (blocked by Firestore rules), since a device could otherwise fake a
  /// "successful" purchase locally.
  Future<DateTime> activatePremium({
    required String productId,
    required String purchaseToken,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw "User not authenticated";
    final idToken = await user.getIdToken();

    final response = await http.post(
      Uri.parse(_confirmPurchaseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'productId': productId, 'purchaseToken': purchaseToken}),
    );

    final jsonData = jsonDecode(response.body);
    if (response.statusCode == 200 && jsonData['success'] == true) {
      return DateTime.parse(jsonData['premiumExpiresAt'] as String);
    }
    throw jsonData['error'] ?? "Failed to activate premium";
  }

  Future<String?> generateImageSecurely({
    required String prompt,
    File? referenceImage,
    File? referenceImage2,
    String? templateImageUrl,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw "User not authenticated";

      final idToken = await user.getIdToken();

      String? base64Img;
      if (referenceImage != null) {
        final bytes = await referenceImage.readAsBytes();
        base64Img = base64Encode(bytes);
      }

      String? base64Img2;
      if (referenceImage2 != null) {
        final bytes2 = await referenceImage2.readAsBytes();
        base64Img2 = base64Encode(bytes2);
      }

      final response = await http.post(
        Uri.parse(_supabaseFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'prompt': prompt,
          if (base64Img != null) 'referenceImageBase64': base64Img,
          if (base64Img2 != null) 'referenceImageBase64_2': base64Img2,
          if (templateImageUrl != null) 'templateImageUrl': templateImageUrl,
        }),
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw "Generation timed out. Please try again.",
      );

      Map<String, dynamic>? jsonData;
      try {
        jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw "Generation failed. Please try again.";
      }

      if (response.statusCode == 200 && jsonData['success'] == true) {
        return jsonData['imageUrl'] as String?;
      } else {
        throw jsonData['error'] ?? "Generation failed. Please try again.";
      }
    } catch (e) {
      rethrow;
    }
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

  Future<void> redeemReferralCode(String uid, String code, {int referralReward = 40}) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final userData = userDoc.data();
    
    if (userData?['referredBy'] != null) {
      throw "You have already used a referral code.";
    }

    if (userData?['referralCode'] == code) {
      throw "You cannot use your own referral code.";
    }

    final codeDoc = await _firestore.collection('referralCodes').doc(code).get();
    final inviterUid = codeDoc.data()?['uid'] as String?;

    if (inviterUid == null) {
      throw "Invalid referral code.";
    }

    // Written sequentially (not batched) so each write is evaluated against
    // already-committed state — the security rules verify the referral
    // relationship by reading the referrer's own `referredBy` field, which
    // must already exist before the inviter's document can be credited.
    await _firestore.collection('users').doc(uid).update({
      'coins': FieldValue.increment(referralReward),
      'referredBy': code,
    });

    await _firestore.collection('users').doc(inviterUid).update({
      'coins': FieldValue.increment(referralReward),
      'referralCount': FieldValue.increment(1),
    });

    await _firestore.collection('users').doc(inviterUid).collection('notifications').add({
      'title': 'Referral Successful! 🎁',
      'message': 'A friend joined using your code! $referralReward coins added to your account.',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }
}
