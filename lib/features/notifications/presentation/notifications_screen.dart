import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/user_provider.dart';
import '../../../models/notification_model.dart';

final notificationsProvider = StreamProvider.family<List<NotificationModel>, String>((ref, uid) {
  return ref.watch(firebaseServiceProvider).getNotifications(uid);
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).value;
    if (user == null) return const Scaffold(body: Center(child: Text("Please log in")));

    final notificationsAsync = ref.watch(notificationsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 80, color: Colors.white12),
                  const SizedBox(height: 16),
                  const Text(
                    "No notifications yet",
                    style: TextStyle(fontSize: 18, color: Colors.white54),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final note = notifications[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: note.isRead ? Colors.grey[800] : Colors.purpleAccent,
                  child: Icon(
                    note.isRead ? Icons.notifications_none : Icons.notifications_active,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  note.title,
                  style: TextStyle(
                    fontWeight: note.isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(note.message),
                    if (note.coinReward != null && note.coinReward! > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.generating_tokens, color: Colors.amber, size: 14),
                            const SizedBox(width: 4),
                            Text("+${note.coinReward} Coins", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.jm().add_yMMMd().format(note.timestamp),
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
                onTap: () {
                  if (!note.isRead) {
                    ref.read(firebaseServiceProvider).markNotificationAsRead(user.uid, note.id);
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text("Error: $err")),
      ),
    );
  }
}
