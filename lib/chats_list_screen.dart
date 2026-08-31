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

  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _myChatsStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _currentUserId)
        .snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  Future<void> _togglePin(String chatDocId, bool currentlyPinned) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatDocId).set({
        'pinnedBy': {_currentUserId: !currentlyPinned},
      }, SetOptions(merge: true));
    } catch (_) {
      // Not critical — pin state just won't update this time.
    }
  }

  Future<void> _toggleMute(String chatDocId, bool currentlyMuted) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatDocId).set({
        'mutedBy': {_currentUserId: !currentlyMuted},
      }, SetOptions(merge: true));
    } catch (_) {
      // Not critical — mute state just won't update this time.
    }
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
      appBar: buildAppBar(
        title: 'Chats',
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? 'Close search' : 'Search chats',
            onPressed: _toggleSearch,
          ),
        ],
      ),
      // No orderBy here on purpose — combining array-contains with orderBy
      // on a different field needs a composite index. Sorting the small
      // result set in Dart avoids that entirely.
      body: Column(
        children: [
          if (_isSearching)
            Container(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: AppColors.primaryDark),
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  prefixIcon: Icon(Icons.search, color: AppColors.primary, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.fieldFill,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: AppColors.fieldBorder),
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
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

          bool isPinnedDoc(QueryDocumentSnapshot doc) {
            final data = doc.data() as Map<String, dynamic>;
            final pinnedMap = data['pinnedBy'] as Map<String, dynamic>?;
            return pinnedMap?[_currentUserId] == true;
          }

          var docs = (snapshot.data?.docs ?? []).toList()
            ..sort((a, b) {
              final aPinned = isPinnedDoc(a);
              final bPinned = isPinnedDoc(b);
              if (aPinned != bPinned) return aPinned ? -1 : 1;
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['lastMessageAt'] as Timestamp?;
              final bTime = bData['lastMessageAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

          if (_searchQuery.isNotEmpty) {
            docs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final participants = List<String>.from(data['participants'] ?? []);
              final otherUserId = participants.firstWhere(
                (id) => id != _currentUserId,
                orElse: () => '',
              );
              final participantNames =
                  (data['participantNames'] as Map<String, dynamic>?) ?? {};
              final otherUserName =
                  ((participantNames[otherUserId] as String?) ?? '').toLowerCase();
              return otherUserName.contains(_searchQuery);
            }).toList();
          }

          if (docs.isEmpty) {
            final noResults = _searchQuery.isNotEmpty;
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(noResults ? Icons.search_off : Icons.chat_bubble_outline,
                        size: 64, color: AppColors.primary.withValues(alpha: 0.3)),
                    SizedBox(height: 16),
                    Text(
                      noResults ? 'No chats match "$_searchQuery"' : 'No conversations yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!noResults) ...[
                      SizedBox(height: 8),
                      Text(
                        'Tap someone in a group to start chatting.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
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
              final pinnedMap = data['pinnedBy'] as Map<String, dynamic>?;
              final mutedMap = data['mutedBy'] as Map<String, dynamic>?;
              final isPinned = pinnedMap?[_currentUserId] == true;
              final isMuted = mutedMap?[_currentUserId] == true;
              final isUnread = !isMuted &&
                  lastSenderId != _currentUserId &&
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
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        otherUserName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isPinned) ...[
                      SizedBox(width: 5),
                      Icon(Icons.push_pin, size: 13, color: AppColors.primary),
                    ],
                    if (isMuted) ...[
                      SizedBox(width: 5),
                      Icon(Icons.notifications_off_outlined, size: 13, color: Colors.grey),
                    ],
                  ],
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
                child: Dismissible(
                  key: ValueKey(docs[index].id),
                  direction: DismissDirection.horizontal,
                  // Both directions just toggle a flag and snap back —
                  // nothing is actually removed from the list, so
                  // confirmDismiss always returns false after acting.
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      await _togglePin(docs[index].id, isPinned);
                    } else {
                      await _toggleMute(docs[index].id, isMuted);
                    }
                    return false;
                  },
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.only(left: 22),
                    margin: EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                      color: Colors.white,
                    ),
                  ),
                  secondaryBackground: Container(
                    alignment: Alignment.centerRight,
                    padding: EdgeInsets.only(right: 22),
                    margin: EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      isMuted ? Icons.notifications_active_outlined : Icons.notifications_off,
                      color: Colors.white,
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
                ),
              );
            },
          );
        },
            ),
          ),
        ],
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
