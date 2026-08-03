import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart' show AppColors;

String _formatTimestamp(Timestamp? ts) {
  if (ts == null) return '';
  final dt = ts.toDate();
  final now = DateTime.now();
  final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  final time = '$hour:$minute $period';
  if (isToday) return 'Today, $time';
  return '${dt.day}/${dt.month}/${dt.year}, $time';
}

/// First screen you see when you tap the notifications bell: a list of
/// senders (staff members) who have sent a notification, newest activity
/// first, with how many notifications each of them sent.
class BroadcastsScreen extends StatelessWidget {
  const BroadcastsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('Notifications'),
      ),
      body: AnnouncementsTab(),
    );
  }
}

/// The same list of senders, without its own Scaffold/AppBar — this is
/// what actually renders inside the Announcements bottom-nav tab in
/// MainScreen. [BroadcastsScreen] above just wraps this for the older
/// entry point (the notification bell inside a group screen).
class AnnouncementsTab extends StatelessWidget {
  const AnnouncementsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('broadcasts')
            .orderBy('sentAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Something went wrong loading notifications.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none,
                        size: 64, color: AppColors.primary.withValues(alpha: 0.3)),
                    SizedBox(height: 16),
                    Text(
                      'No notifications yet',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Group broadcasts by sender, keep the newest-first order.
          final senderOrder = <String>[];
          final countBySender = <String, int>{};
          final nameBySender = <String, String>{};
          final latestBySender = <String, Timestamp?>{};

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final senderId = (data['senderId'] as String?) ?? 'unknown';
            final senderName = (data['senderName'] as String?) ?? 'Staff';
            if (!countBySender.containsKey(senderId)) {
              senderOrder.add(senderId);
              nameBySender[senderId] = senderName;
              latestBySender[senderId] = data['sentAt'] as Timestamp?;
            }
            countBySender[senderId] = (countBySender[senderId] ?? 0) + 1;
          }

          return ListView.separated(
            padding: EdgeInsets.symmetric(vertical: 8),
            itemCount: senderOrder.length,
            separatorBuilder: (context, index) =>
                Divider(color: AppColors.fieldBorder, height: 1, indent: 76),
            itemBuilder: (context, index) {
              final senderId = senderOrder[index];
              final senderName = nameBySender[senderId] ?? 'Staff';
              final count = countBySender[senderId] ?? 0;
              final latest = latestBySender[senderId];

              return ListTile(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                  child: Text(
                    senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: AppColors.primaryDark, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  senderName,
                  style: TextStyle(
                      color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '$count ${count == 1 ? 'notification' : 'notifications'} • ${_formatTimestamp(latest)}',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SenderMessagesScreen(
                        senderId: senderId,
                        senderName: senderName,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
  }
}

/// Second screen: all the notifications sent by one particular sender,
/// opened after tapping their name in the list above.
class SenderMessagesScreen extends StatelessWidget {
  final String senderId;
  final String senderName;

  const SenderMessagesScreen({
    super.key,
    required this.senderId,
    required this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(senderName),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Ordered by sentAt only (single field) — filtering by sender
        // happens below, in Dart, so this never needs a composite index.
        stream: FirebaseFirestore.instance
            .collection('broadcasts')
            .orderBy('sentAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load notifications: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final docs = (snapshot.data?.docs ?? []).where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['senderId'] == senderId;
          }).toList();

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No notifications from this sender.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (context, index) => SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final message = data['message'] ?? '';
              final sentAt = data['sentAt'] as Timestamp?;

              return Container(
                width: double.infinity,
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.fieldFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.fieldBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      _formatTimestamp(sentAt),
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
