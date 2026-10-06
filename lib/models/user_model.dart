import 'package:cloud_firestore/cloud_firestore.dart';

enum UserTier { free, paid }

class UserModel {
  final String uid;
  final String email;
  final int coins;

  /// Effective tier: a `paid` profile whose `premiumExpiresAt` is in the past
  /// is shown as `free` immediately (the server also downgrades it).
  final UserTier tier;
  final DateTime? premiumExpiresAt;

  /// 'monthly' | 'yearly' | null
  final String? premiumPlan;
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

  final int loginStreak;
  final DateTime? lastStreakClaim;

  /// 'male' | 'female' | 'unisex' | null (not chosen yet) — drives which
  /// prompts show up in this user's gallery.
  final String? gender;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.coins = 0,
    this.tier = UserTier.free,
    this.premiumExpiresAt,
    this.premiumPlan,
    required this.referralCode,
    this.referredBy,
    required this.lastDailyReset,
    this.dailyAdsWatched = 0,
    this.referralCount = 0,
    this.isBlocked = false,
    this.lastActivity,
    this.fcmToken,
    this.loginStreak = 0,
    this.lastStreakClaim,
    this.gender,
  });

  bool get isPremium => tier == UserTier.paid;

  /// Firestore may hand back int or double (e.g. after an admin edit) — never
  /// crash on either.
  static int _int(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

  static DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

  factory UserModel.fromMap(Map<String, dynamic> data, String uid) {
    final expires = _date(data['premiumExpiresAt']);
    final rawPaid = data['tier'] == 'paid';
    final stillPaid = rawPaid && expires != null && expires.isAfter(DateTime.now());

    return UserModel(
      uid: uid,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      photoUrl: data['photoUrl'],
      coins: _int(data['coins']),
      tier: stillPaid ? UserTier.paid : UserTier.free,
      premiumExpiresAt: expires,
      premiumPlan: data['premiumPlan'] as String?,
      referralCode: data['referralCode'] ?? '',
      referredBy: data['referredBy'],
      lastDailyReset: _date(data['lastDailyReset']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      dailyAdsWatched: _int(data['dailyAdsWatched']),
      referralCount: _int(data['referralCount']),
      isBlocked: data['isBlocked'] ?? false,
      lastActivity: _date(data['lastActivity']),
      fcmToken: data['fcmToken'],
      loginStreak: _int(data['loginStreak']),
      lastStreakClaim: _date(data['lastStreakClaim']),
      gender: data['gender'],
    );
  }

  UserModel copyWith({
    String? displayName,
    String? photoUrl,
    String? gender,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      coins: coins,
      tier: tier,
      premiumExpiresAt: premiumExpiresAt,
      premiumPlan: premiumPlan,
      referralCode: referralCode,
      referredBy: referredBy,
      lastDailyReset: lastDailyReset,
      dailyAdsWatched: dailyAdsWatched,
      referralCount: referralCount,
      isBlocked: isBlocked,
      lastActivity: lastActivity,
      fcmToken: fcmToken,
      loginStreak: loginStreak,
      lastStreakClaim: lastStreakClaim,
      gender: gender ?? this.gender,
    );
  }
}
