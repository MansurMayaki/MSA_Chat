import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart' show AppColors;
import 'chat_screen.dart';
import 'profile_screen.dart' show buildUserAvatar, UserProfileViewScreen;

class ChatsListScreen extends StatelessWidget {
  const ChatsListScreen({super.key});

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $period';
    if (isToday) return time;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('Chats'),
      ),
      // No orderBy here on purpose — combining array-contains with orderBy
      // on a different field needs a composite index. Sorting the small
      // result set in Dart avoids that entirely.
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: _currentUserId)
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
                'Could not load chats: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final docs = (snapshot.data?.docs ?? []).toList()
            ..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['lastMessageAt'] as Timestamp?;
              final bTime = bData['lastMessageAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 64, color: AppColors.primary.withValues(alpha: 0.3)),
                    SizedBox(height: 16),
                    Text(
                      'No conversations yet',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tap someone in a group to start chatting.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (context, index) =>
                Divider(color: AppColors.fieldBorder, height: 1, indent: 76),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final participants = List<String>.from(data['participants'] ?? []);
              final otherUserId = participants.firstWhere(
                (id) => id != _currentUserId,
                orElse: () => '',
              );
              final participantNames =
                  (data['participantNames'] as Map<String, dynamic>?) ?? {};
              final otherUserName =
                  (participantNames[otherUserId] as String?) ?? 'Unknown';
              final lastMessage = (data['lastMessage'] as String?) ?? '';
              final lastMessageAt = data['lastMessageAt'] as Timestamp?;
              final lastSenderId = data['lastSenderId'] as String?;

              final readMap = data['lastReadAt'] as Map<String, dynamic>?;
              final myReadAt = readMap?[_currentUserId] as Timestamp?;
              final isUnread = lastSenderId != _currentUserId &&
                  lastMessageAt != null &&
                  (myReadAt == null || myReadAt.compareTo(lastMessageAt) < 0);

              return ListTile(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfileViewScreen(
                          userId: otherUserId,
                          fallbackName: otherUserName,
                        ),
                      ),
                    );
                  },
                  // Chat docs only store the other person's name, not their
                  // photo, so their live user doc is streamed here to keep
                  // the DP in sync with whatever they've set in Profile.
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(otherUserId)
                        .snapshots(),
                    builder: (context, userSnapshot) {
                      final userData =
                          userSnapshot.data?.data() as Map<String, dynamic>?;
                      return buildUserAvatar(
                        userData: userData,
                        fallbackName: otherUserName,
                        radius: 26,
                      );
                    },
                  ),
                ),
                title: Text(
                  otherUserName,
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  lastSenderId == _currentUserId ? 'You: $lastMessage' : lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isUnread ? AppColors.primaryDark : Colors.grey,
                    fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTimestamp(lastMessageAt),
                      style: TextStyle(
                        color: isUnread ? AppColors.primary : Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                    if (isUnread) ...[
                      SizedBox(height: 6),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        otherUserId: otherUserId,
                        otherUserName: otherUserName,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
