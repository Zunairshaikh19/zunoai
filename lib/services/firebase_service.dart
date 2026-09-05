import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
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

  // ImgBB API Key
  static const String _imgBBKey = "d06e36c9de1d91a12a0c824e8c8837e4";

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --- Auth Methods ---
  
  Future<UserCredential?> signInWithGoogle() async {
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
          await createUserProfile(user);
        }
      }
      return userCredential;
    } catch (e) {
      rethrow;
    }
  }
  
  Future<UserCredential> signUp(String email, String password, {String? referralCode}) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await createUserProfile(cred.user!, referredBy: referralCode);
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

  Future<void> createUserProfile(User user, {String? referredBy}) async {
    final referralCode = const Uuid().v4().substring(0, 8).toUpperCase();
    
    int initialCoins = 40;
    if (referredBy != null && referredBy.isNotEmpty) {
      initialCoins += 40;
    }

    final newUser = UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
      referralCode: referralCode,
      referredBy: referredBy,
      lastDailyReset: DateTime.now(),
      coins: initialCoins,
    );

    await _firestore.collection('users').doc(user.uid).set(newUser.toMap());

    if (referredBy != null && referredBy.isNotEmpty) {
      final inviterQuery = await _firestore
          .collection('users')
          .where('referralCode', isEqualTo: referredBy)
          .limit(1)
          .get();
      
      if (inviterQuery.docs.isNotEmpty) {
        final inviterDoc = inviterQuery.docs.first;
        await _firestore.collection('users').doc(inviterDoc.id).update({
          'coins': FieldValue.increment(40),
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
    await _firestore.collection('users').doc(uid).update({
      'lastActivity': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateFcmToken(String uid, String? token) async {
    await _firestore.collection('users').doc(uid).update({'fcmToken': token});
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

  Future<void> updateDailyAdCount(String uid, int count) async {
    await _firestore.collection('users').doc(uid).update({'dailyAdsWatched': count});
  }

  Future<void> resetDailyLimits(String uid, int coins) async {
    await _firestore.collection('users').doc(uid).update({
      'coins': coins,
      'dailyAdsWatched': 0,
      'lastDailyReset': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> saveToHistory(String uid, HistoryItem item) async {
    print("Saving history for user: $uid");
    try {
      await _firestore.collection('users').doc(uid).collection('history').add(item.toMap());
      print("History saved successfully.");
    } catch (e) {
      print("Failed to save history: $e");
      rethrow;
    }
  }

  Stream<List<HistoryItem>> historyStream(String uid) {
    print("Listening to history stream for: $uid");
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('history')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          print("Received history update. Count: ${snapshot.docs.length}");
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

  Future<String?> getGenerationApiKey() async {
    final doc = await _firestore.collection('settings').doc('config').get();
    return doc.data()?['nanoBananaApiKey'];
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

  Future<void> redeemReferralCode(String uid, String code) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final userData = userDoc.data();
    
    if (userData?['referredBy'] != null) {
      throw "You have already used a referral code.";
    }

    if (userData?['referralCode'] == code) {
      throw "You cannot use your own referral code.";
    }

    final inviterQuery = await _firestore
        .collection('users')
        .where('referralCode', isEqualTo: code)
        .limit(1)
        .get();

    if (inviterQuery.docs.isEmpty) {
      throw "Invalid referral code.";
    }

    final inviterDoc = inviterQuery.docs.first;

    final batch = _firestore.batch();
    batch.update(_firestore.collection('users').doc(uid), {
      'coins': FieldValue.increment(40),
      'referredBy': code,
    });
    batch.update(_firestore.collection('users').doc(inviterDoc.id), {
      'coins': FieldValue.increment(40),
      'referralCount': FieldValue.increment(1),
    });

    final noteRef = _firestore.collection('users').doc(inviterDoc.id).collection('notifications').doc();
    batch.set(noteRef, {
      'title': 'Referral Successful! 🎁',
      'message': 'A friend joined using your code! 40 coins added to your account.',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });

    await batch.commit();
  }
}
