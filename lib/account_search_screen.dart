import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'main.dart' show AppColors, AppRadius, appCardShadow, buildAppBar, slideRoute;
import 'profile_screen.dart' show buildUserAvatar;
import 'user_record_screen.dart';

/// Staff-only: search every account by name, from any group, without
/// needing to know their ID number or which group they're in first.
/// Tapping a result opens the same View & Edit screen as the group list
/// and the Fix Account Link tool.
class AccountSearchScreen extends StatefulWidget {
  const AccountSearchScreen({super.key});

  @override
  State<AccountSearchScreen> createState() => _AccountSearchScreenState();
}

class _AccountSearchScreenState extends State<AccountSearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  // Built once instead of inline in build() — an inline stream here would
  // be recreated (cancelling and reopening this Firestore listener) on
  // every rebuild, e.g. every dark-mode toggle or each keystroke's
  // setState if the query filtering were done via this stream directly.
  late final Stream<QuerySnapshot> _usersStream =
      FirebaseFirestore.instance.collection('users').snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _labelForGroup(String? group) {
    switch (group) {
      case 'beginners':
        return 'Beginners Group';
      case 'intermediate':
        return 'Intermediate Group';
      case 'advance':
        return 'Advance Group';
      case 'staff':
        return 'Staff Group';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(title: 'Find an Account'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: AppColors.primaryDark),
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Search by name...',
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.search, color: AppColors.primary),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.fieldFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.fieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.fieldBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
              ),
            ),
            Expanded(child: _resultsList()),
          ],
        ),
      ),
    );
  }

  Widget _resultsList() {
    if (_query.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_search_outlined,
                  size: 64, color: AppColors.primary.withValues(alpha: 0.3)),
              SizedBox(height: 16),
              Text(
                'Start typing a name to find their account',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _usersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Something went wrong loading accounts.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final needle = _query.toLowerCase();
        final results = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] as String? ?? '').toLowerCase();
          return name.contains(needle);
        }).toList();

        if (results.isEmpty) {
          return Center(
            child: Text(
              'No accounts match "$_query"',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final doc = results[index];
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['name'] as String?) ?? 'Unknown';
            final role = (data['role'] as String?) ?? '';
            final groupLabel = role == 'staff'
                ? 'Staff'
                : _labelForGroup(data['group'] as String?);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: appCardShadow(),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: buildUserAvatar(userData: data, fallbackName: name),
                  title: Text(
                    name,
                    style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    groupLabel,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right, color: AppColors.primary),
                  onTap: () {
                    Navigator.push(
                      context,
                      slideRoute(UserRecordScreen(uid: doc.id)),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
