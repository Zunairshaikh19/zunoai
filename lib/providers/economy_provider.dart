import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/economy_config.dart';

/// Live-updating economy config from Firestore `settings/economy`, so an
/// admin can change coin amounts/limits without an app store release.
/// Falls back to the current hardcoded defaults if a field (or the whole
/// document) hasn't been configured yet. Kept separate from `settings/config`
/// (which holds the AI provider API key) so the mobile app never needs read
/// access to that secret.
final economyConfigProvider = StreamProvider<EconomyConfig>((ref) {
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('economy')
      .snapshots()
      .map((doc) => EconomyConfig.fromMap(doc.data()));
});
