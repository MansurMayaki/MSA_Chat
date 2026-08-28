import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart' show AppColors, AppRadius, appCardShadow, buildAppBar, slideRoute;
import 'chat_screen.dart';
import 'profile_screen.dart' show buildUserAvatar, UserProfileViewScreen;

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Built once per screen instance instead of inline in build() — a
  // StreamBuilder treats a new Stream object as "different" even when the
  // query is identical, so an inline stream here would cancel and reopen
  // this Firestore listener on every rebuild (e.g. every dark-mode toggle).
  late final Stream<QuerySnapshot> _myChatsStream;

  @override
  void initState() {
    super.initState();
    _myChatsStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _currentUserId)
        .snapshots();
  }

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
      appBar: buildAppBar(title: 'Chats'),
      // No orderBy here on purpose — combining array-contains with orderBy
      // on a different field needs a composite index. Sorting the small
      // result set in Dart avoids that entirely.
      body: StreamBuilder<QuerySnapshot>(
        stream: _myChatsStream,
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

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
            itemCount: docs.length,
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

              final tile = ListTile(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      slideRoute(UserProfileViewScreen(
                        userId: otherUserId,
                        fallbackName: otherUserName,
                      )),
                    );
                  },
                  // Chat docs only store the other person's name, not their
                  // photo, so their live user doc is streamed here to keep
                  // the DP in sync with whatever they've set in Profile.
                  child: _ChatAvatarStream(
                    otherUserId: otherUserId,
                    fallbackName: otherUserName,
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
                    slideRoute(ChatScreen(
                      otherUserId: otherUserId,
                      otherUserName: otherUserName,
                    )),
                  );
                },
              );

              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 320 + (index * 30).clamp(0, 300)),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 12),
                    child: child,
                  ),
                ),
                child: Container(
                  margin: EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: appCardShadow(),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: tile,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A chat list tile's avatar, kept live-synced to the other person's user
/// doc (for their current photo). Split out into its own StatefulWidget so
/// its Firestore listener can be cached per-tile — otherwise every tile's
/// avatar stream would be rebuilt (and its listener reopened) whenever the
/// list rebuilds for any reason, not just when that person's photo changes.
class _ChatAvatarStream extends StatefulWidget {
  final String otherUserId;
  final String fallbackName;

  const _ChatAvatarStream({
    required this.otherUserId,
    required this.fallbackName,
  });

  @override
  State<_ChatAvatarStream> createState() => _ChatAvatarStreamState();
}

class _ChatAvatarStreamState extends State<_ChatAvatarStream> {
  late final Stream<DocumentSnapshot> _userDocStream;

  @override
  void initState() {
    super.initState();
    _userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _userDocStream,
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        return buildUserAvatar(
          userData: userData,
          fallbackName: widget.fallbackName,
          radius: 26,
        );
      },
    );
  }
}
