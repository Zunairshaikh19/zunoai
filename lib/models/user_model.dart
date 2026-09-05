import 'package:cloud_firestore/cloud_firestore.dart';

enum UserTier { free, paid }

class UserModel {
  final String uid;
  final String email;
  final int coins;
  final UserTier tier;
  final String referralCode;
  final String? referredBy;
  final DateTime lastDailyReset;
  final int dailyAdsWatched;

  final int referralCount;

  final String? displayName;
  final String? photoUrl;

  final bool isBlocked;
  final DateTime? lastActivity;
  final String? fcmToken;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.coins = 40,
    this.tier = UserTier.free,
    required this.referralCode,
    this.referredBy,
    required this.lastDailyReset,
    this.dailyAdsWatched = 0,
    this.referralCount = 0,
    this.isBlocked = false,
    this.lastActivity,
    this.fcmToken,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      photoUrl: data['photoUrl'],
      coins: data['coins'] ?? 40,
      tier: data['tier'] == 'paid' ? UserTier.paid : UserTier.free,
      referralCode: data['referralCode'] ?? '',
      referredBy: data['referredBy'],
      lastDailyReset: (data['lastDailyReset'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dailyAdsWatched: data['dailyAdsWatched'] ?? 0,
      referralCount: data['referralCount'] ?? 0,
      isBlocked: data['isBlocked'] ?? false,
      lastActivity: (data['lastActivity'] as Timestamp?)?.toDate(),
      fcmToken: data['fcmToken'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'coins': coins,
      'tier': tier == UserTier.paid ? 'paid' : 'free',
      'referralCode': referralCode,
      'referredBy': referredBy,
      'lastDailyReset': Timestamp.fromDate(lastDailyReset),
      'dailyAdsWatched': dailyAdsWatched,
      'referralCount': referralCount,
      'isBlocked': isBlocked,
      'lastActivity': lastActivity != null ? Timestamp.fromDate(lastActivity!) : FieldValue.serverTimestamp(),
      'fcmToken': fcmToken,
    };
  }

  UserModel copyWith({
    String? displayName,
    String? photoUrl,
    int? coins,
    UserTier? tier,
    int? dailyAdsWatched,
    DateTime? lastDailyReset,
    int? referralCount,
    bool? isBlocked,
    DateTime? lastActivity,
    String? fcmToken,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      coins: coins ?? this.coins,
      tier: tier ?? this.tier,
      referralCode: referralCode,
      referredBy: referredBy,
      lastDailyReset: lastDailyReset ?? this.lastDailyReset,
      dailyAdsWatched: dailyAdsWatched ?? this.dailyAdsWatched,
      referralCount: referralCount ?? this.referralCount,
      isBlocked: isBlocked ?? this.isBlocked,
      lastActivity: lastActivity ?? this.lastActivity,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }
}
