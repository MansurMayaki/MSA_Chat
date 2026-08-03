import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' show AppColors;
import 'login_screen.dart';
import 'broadcasts_screen.dart';
import 'send_notification_screen.dart';
import 'presence.dart';
import 'chat_screen.dart';
import 'chats_list_screen.dart';
import 'profile_screen.dart';

const _lastNotifSeenKeyPrefix = 'last_notif_seen_millis_';

// The "seen" marker must be per-account, not per-browser — otherwise one
// account's "already read" state leaks into the next account that logs
// in on the same device.
String _lastNotifSeenKeyForCurrentUser() {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
  return '$_lastNotifSeenKeyPrefix$uid';
}

Future<int> _loadLastNotifSeenMillis() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastNotifSeenKeyForCurrentUser()) ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<void> _saveLastNotifSeenMillis(int millis) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastNotifSeenKeyForCurrentUser(), millis);
  } catch (_) {
    // Storage unavailable — not critical, just skip.
  }
}

/// Counts broadcasts newer than [lastSeenMillis], excluding ones sent by
/// [excludeSenderId] — a sender should never see their own notification
/// as "new" to them.
int _countUnread(
  AsyncSnapshot<QuerySnapshot> snapshot,
  String excludeSenderId,
) {
  final docs = snapshot.data?.docs ?? [];
  return docs.where((doc) {
    final data = doc.data() as Map<String, dynamic>;
    return data['senderId'] != excludeSenderId;
  }).length;
}

/// Looks up the logged-in user's role in Firestore, then shows the
/// group-picker screen. Shown right after login / on app reopen.
class GroupRouter extends StatelessWidget {
  const GroupRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return LoginScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Text(
                'Could not find your profile. Please try logging in again.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final role = data['role'] ?? 'student';

          return MainScreen(role: role);
        },
      ),
    );
  }
}

/// The app's home screen after login: a WhatsApp-style bottom nav with
/// "Chats" (pick a group to message people in) and "Profile" (update your
/// own info) tabs. More tabs (Status, Calls, etc.) can be added later —
/// this starts with the two that matter now.
class MainScreen extends StatefulWidget {
  final String role;

  const MainScreen({super.key, required this.role});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _lastSeenMillis = 0;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get _isStaff => widget.role == 'staff';

  @override
  void initState() {
    super.initState();
    _loadLastSeen();
  }

  Future<void> _loadLastSeen() async {
    final millis = await _loadLastNotifSeenMillis();
    if (mounted) setState(() => _lastSeenMillis = millis);
  }

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
    // Opening the Announcements tab counts as "seen" — same behavior as
    // tapping the old notification bell.
    if (index == 2) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _saveLastNotifSeenMillis(now);
      setState(() => _lastSeenMillis = now);
    }
  }

  Future<void> _logout(BuildContext context) async {
    if (_currentUserId.isNotEmpty) await setUserOffline(_currentUserId);
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps both tabs alive in the background (so switching
    // tabs doesn't reset scroll position, re-fetch data, or restart the
    // presence/stream listeners each time), matching how WhatsApp's own
    // tabs behave.
    final tabs = [
      ChooseGroupScreen(role: widget.role),
      ProfileForm(),
      AnnouncementsTab(),
    ];

    final titles = ['Chats', 'My Profile', 'Announcements'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          titles[_selectedIndex],
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: Icon(Icons.forum_outlined, color: Colors.white),
              tooltip: 'Direct Messages',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ChatsListScreen()),
                );
              },
            ),
          if (_selectedIndex == 2 && _isStaff)
            IconButton(
              icon: Icon(Icons.campaign_outlined, color: Colors.white),
              tooltip: 'Send Announcement',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SendNotificationScreen()),
                );
              },
            ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: () => _logout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        backgroundColor: AppColors.fieldFill,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: _announcementsIcon(active: false),
            activeIcon: _announcementsIcon(active: true),
            label: 'Announcements',
          ),
        ],
      ),
    );
  }

  Widget _announcementsIcon({required bool active}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('broadcasts')
          .where(
            'sentAt',
            isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(_lastSeenMillis),
          )
          .snapshots(),
      builder: (context, snapshot) {
        final unread = _countUnread(snapshot, _currentUserId);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(active ? Icons.campaign : Icons.campaign_outlined),
            if (unread > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Lets the user pick which group to enter, showing a live headcount
/// under each group name, plus an unread-notifications badge on
/// Staff Group (since that's where notifications come from).
class ChooseGroupScreen extends StatefulWidget {
  final String role;

  const ChooseGroupScreen({super.key, required this.role});

  @override
  State<ChooseGroupScreen> createState() => _ChooseGroupScreenState();
}

class _ChooseGroupScreenState extends State<ChooseGroupScreen> {
  static const _groups = [
    {'key': 'beginners', 'label': 'Beginners Group', 'icon': Icons.emoji_objects_outlined},
    {'key': 'intermediate', 'label': 'Intermediate Group', 'icon': Icons.trending_up},
    {'key': 'advance', 'label': 'Advance Group', 'icon': Icons.workspace_premium_outlined},
    {'key': 'staff', 'label': 'Staff Group', 'icon': Icons.badge_outlined},
  ];

  int _lastSeenMillis = 0;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadLastSeen();
    if (_currentUserId.isNotEmpty) setUserOnline(_currentUserId);
  }

  Future<void> _loadLastSeen() async {
    final millis = await _loadLastNotifSeenMillis();
    if (mounted) setState(() => _lastSeenMillis = millis);
  }

  // No Scaffold/AppBar here on purpose: this widget is now hosted as a tab
  // body inside MainScreen, which owns the shared app bar, bottom nav, and
  // logout action.
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: _currentUserId)
          .snapshots(),
      builder: (context, chatsSnapshot) {
        final unreadByGroup = _computeUnreadChatCountsByGroup(
          chatsSnapshot.data?.docs ?? [],
          _currentUserId,
        );

        return ListView.separated(
          padding: EdgeInsets.all(16),
          itemCount: _groups.length,
          separatorBuilder: (context, index) => SizedBox(height: 12),
          itemBuilder: (context, index) {
            final g = _groups[index];
            final groupKey = g['key'] as String;
            return _GroupCard(
              groupKey: groupKey,
              label: g['label'] as String,
              icon: g['icon'] as IconData,
              role: widget.role,
              showNotifBadge: groupKey == 'staff',
              lastSeenMillis: _lastSeenMillis,
              currentUserId: _currentUserId,
              onReturn: _loadLastSeen,
              unreadChatCount: unreadByGroup[groupKey] ?? 0,
            );
          },
        );
      },
    );
  }
}

/// Counts, per group, how many unread 1-on-1 chats I have with someone
/// from that group — so a group card can show "someone from here messaged
/// you" without opening every group to check.
Map<String, int> _computeUnreadChatCountsByGroup(
  List<QueryDocumentSnapshot> chatDocs,
  String currentUserId,
) {
  final counts = <String, int>{};
  for (final doc in chatDocs) {
    final data = doc.data() as Map<String, dynamic>;
    final lastSenderId = data['lastSenderId'] as String?;
    if (lastSenderId == null || lastSenderId == currentUserId) continue;

    final lastMessageAt = data['lastMessageAt'] as Timestamp?;
    if (lastMessageAt == null) continue;

    final readMap = data['lastReadAt'] as Map<String, dynamic>?;
    final myReadAt = readMap?[currentUserId] as Timestamp?;
    final isUnread = myReadAt == null || myReadAt.compareTo(lastMessageAt) < 0;
    if (!isUnread) continue;

    final participants = List<String>.from(data['participants'] ?? []);
    final otherUserId =
        participants.firstWhere((id) => id != currentUserId, orElse: () => '');
    final groups = data['participantGroups'] as Map<String, dynamic>?;
    final otherGroup = groups?[otherUserId] as String?;
    if (otherGroup == null || otherGroup.isEmpty) continue;

    counts[otherGroup] = (counts[otherGroup] ?? 0) + 1;
  }
  return counts;
}

/// The groups a student can be moved between. Deliberately excludes
/// 'staff' — this feature is for repositioning students by skill level,
/// not for promoting someone to staff.
const _studentGroupOptions = [
  {'key': 'beginners', 'label': 'Beginners Group', 'icon': Icons.emoji_objects_outlined},
  {'key': 'intermediate', 'label': 'Intermediate Group', 'icon': Icons.trending_up},
  {'key': 'advance', 'label': 'Advance Group', 'icon': Icons.workspace_premium_outlined},
];

String _labelForGroupKey(String key) {
  final match = _studentGroupOptions.firstWhere(
    (g) => g['key'] == key,
    orElse: () => const {'label': 'Unknown Group'},
  );
  return match['label'] as String;
}

class _GroupCard extends StatelessWidget {
  final String groupKey;
  final String label;
  final IconData icon;
  final String role;
  final bool showNotifBadge;
  final int lastSeenMillis;
  final String currentUserId;
  final VoidCallback onReturn;
  final int unreadChatCount;

  const _GroupCard({
    required this.groupKey,
    required this.label,
    required this.icon,
    required this.role,
    required this.showNotifBadge,
    required this.lastSeenMillis,
    required this.currentUserId,
    required this.onReturn,
    required this.unreadChatCount,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fieldFill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GroupScreen(group: groupKey, role: role),
            ),
          );
          // Refresh our unread badge in case notifications were viewed
          // while inside that group.
          onReturn();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.fieldBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        if (showNotifBadge) ...[
                          SizedBox(width: 8),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('broadcasts')
                                .where(
                                  'sentAt',
                                  isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(
                                      lastSeenMillis),
                                )
                                .snapshots(),
                            builder: (context, snapshot) {
                              final unread = _countUnread(snapshot, currentUserId);
                              if (unread == 0) return SizedBox.shrink();
                              return Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.notifications,
                                        color: Colors.white, size: 12),
                                    SizedBox(width: 3),
                                    Text(
                                      unread > 9 ? '9+' : '$unread',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                        if (unreadChatCount > 0) ...[
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble,
                                    color: Colors.white, size: 12),
                                SizedBox(width: 3),
                                Text(
                                  unreadChatCount > 9 ? '9+' : '$unreadChatCount',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 4),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .where('group', isEqualTo: groupKey)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final count = snapshot.data?.docs.length ?? 0;
                        return Text(
                          snapshot.connectionState == ConnectionState.waiting
                              ? 'Loading...'
                              : '$count ${count == 1 ? 'participant' : 'participants'}',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupScreen extends StatefulWidget {
  final String group;
  final String role;

  const GroupScreen({super.key, required this.group, required this.role});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  int _lastSeenMillis = 0;

  bool get _isStaff => widget.role == 'staff';

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _groupLabel {
    switch (widget.group) {
      case 'beginners':
        return 'Beginners Group';
      case 'intermediate':
        return 'Intermediate Group';
      case 'advance':
        return 'Advance Group';
      case 'staff':
        return 'Staff Group';
      default:
        return 'Group';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLastSeen();
  }

  Future<void> _loadLastSeen() async {
    final millis = await _loadLastNotifSeenMillis();
    if (mounted) setState(() => _lastSeenMillis = millis);
  }

  // Notifications are only ever revealed by tapping this bell — nothing
  // shows their content anywhere else, WhatsApp-style.
  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BroadcastsScreen()),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await _saveLastNotifSeenMillis(now);
    if (mounted) setState(() => _lastSeenMillis = now);
  }

  /// Shows a picker of the other student groups, then moves [studentId]
  /// into whichever one staff taps. Silent on success apart from a
  /// snackbar — no history log, per how this app currently works.
  Future<void> _showMoveGroupDialog({
    required String studentId,
    required String studentName,
    required String currentGroup,
  }) async {
    final selectedKey = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.background,
        title: Text('Move $studentName to...'),
        children: _studentGroupOptions
            .where((g) => g['key'] != currentGroup)
            .map(
              (g) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, g['key'] as String),
                child: Row(
                  children: [
                    Icon(g['icon'] as IconData, color: AppColors.primary),
                    SizedBox(width: 12),
                    Text(
                      g['label'] as String,
                      style: TextStyle(color: AppColors.primaryDark),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );

    if (selectedKey == null || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .update({'group': selectedKey});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$studentName moved to ${_labelForGroupKey(selectedKey)}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to move $studentName: $e')),
        );
      }
    }
  }

  Future<void> _openSendNotification() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SendNotificationScreen()),
    );
  }

  Future<void> _logout(BuildContext context) async {
    if (_currentUserId.isNotEmpty) await setUserOffline(_currentUserId);
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _notifBell() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('broadcasts')
          .where(
            'sentAt',
            isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(_lastSeenMillis),
          )
          .snapshots(),
      builder: (context, snapshot) {
        final unread = _countUnread(snapshot, _currentUserId);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_outlined, color: Colors.white),
              tooltip: 'Notifications',
              onPressed: _openNotifications,
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary, width: 1),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', width: 30),
            SizedBox(width: 10),
            Text(
              _groupLabel,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          if (_isStaff)
            IconButton(
              icon: Icon(Icons.campaign_outlined, color: Colors.white),
              tooltip: 'Send notification to everyone',
              onPressed: _openSendNotification,
            ),
          _notifBell(),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: () => _logout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('group', isEqualTo: widget.group)
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
                'Something went wrong loading this group.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          // Every member of the group is shown, including yourself.
          final members = snapshot.data?.docs ?? [];

          if (members.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 64, color: AppColors.primary.withValues(alpha: 0.3)),
                    SizedBox(height: 16),
                    Text(
                      'No one here yet',
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

          return ListView.separated(
            padding: EdgeInsets.symmetric(vertical: 8),
            itemCount: members.length,
            separatorBuilder: (context, index) =>
                Divider(color: AppColors.fieldBorder, height: 1, indent: 76),
            itemBuilder: (context, index) {
              final data = members[index].data() as Map<String, dynamic>;
              final name = data['name'] ?? 'Unknown';
              final memberRole = data['role'] ?? '';
              final isSelf = members[index].id == _currentUserId;

              return ListTile(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => isSelf
                            ? ProfileScreen()
                            : UserProfileViewScreen(
                                userId: members[index].id,
                                fallbackName: name,
                              ),
                      ),
                    );
                  },
                  child: buildUserAvatar(userData: data, fallbackName: name),
                ),
                title: Text(
                  isSelf ? '$name (You)' : name,
                  style: TextStyle(
                      color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  memberRole == 'staff' ? 'Staff' : 'Student',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                trailing: isSelf
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MemberUnreadBadge(
                            currentUserId: _currentUserId,
                            otherUserId: members[index].id,
                          ),
                          if (_isStaff && memberRole != 'staff')
                            IconButton(
                              icon: Icon(Icons.swap_horiz,
                                  color: AppColors.primary),
                              tooltip: 'Move to another group',
                              onPressed: () => _showMoveGroupDialog(
                                studentId: members[index].id,
                                studentName: name,
                                currentGroup: widget.group,
                              ),
                            ),
                        ],
                      ),
                onTap: isSelf
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ProfileScreen()),
                        );
                      }
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              otherUserId: members[index].id,
                              otherUserName: name,
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

/// Small chat-bubble badge shown next to a group member's name if they've
/// sent you messages you haven't opened yet — with a running unread count.
class _MemberUnreadBadge extends StatelessWidget {
  final String currentUserId;
  final String otherUserId;

  const _MemberUnreadBadge({
    required this.currentUserId,
    required this.otherUserId,
  });

  @override
  Widget build(BuildContext context) {
    final chatId = chatIdFor(currentUserId, otherUserId);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots(),
      builder: (context, chatSnapshot) {
        Timestamp? myReadAt;
        if (chatSnapshot.data != null && chatSnapshot.data!.exists) {
          final data = chatSnapshot.data!.data() as Map<String, dynamic>;
          final readMap = data['lastReadAt'] as Map<String, dynamic>?;
          myReadAt = readMap?[currentUserId] as Timestamp?;
        }

        return StreamBuilder<QuerySnapshot>(
          // Ordered by sentAt only — filtering by sender happens below in
          // Dart, so this never needs a composite index.
          stream: FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .orderBy('sentAt', descending: true)
              .snapshots(),
          builder: (context, msgSnapshot) {
            final docs = msgSnapshot.data?.docs ?? [];
            final unread = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              if (data['senderId'] != otherUserId) return false;
              final sentAt = data['sentAt'] as Timestamp?;
              if (sentAt == null) return false;
              if (myReadAt == null) return true;
              return myReadAt.compareTo(sentAt) < 0;
            }).length;

            if (unread == 0) return SizedBox.shrink();

            return Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text(
                    unread > 99 ? '99+' : '$unread',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
