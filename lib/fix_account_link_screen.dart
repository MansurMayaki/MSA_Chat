import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'main.dart' show AppColors, AppRadius, appCardShadow, buildAppBar, slideRoute;
import 'login_screen.dart' show sanitizeIdForDoc;
import 'virtual_keyboard.dart';
import 'app_notify.dart';
import 'user_record_screen.dart';

/// Staff-only tool for diagnosing and repairing the ID→account "link"
/// that login depends on. Login works by looking up `id_index/{ID}` to
/// find an email, then signing in with that email — so if that document
/// ever points at the wrong email/uid (bad data entry, a duplicate ID,
/// etc.), someone can type in a perfectly correct ID number and land in
/// a completely different person's account with no warning at all.
///
/// This screen finds the account that actually owns a given ID number
/// (by querying `users` directly, which is unaffected by a bad index
/// doc), compares that against what `id_index` currently points to, and
/// lets staff overwrite the index with the correct mapping in one tap.
class FixAccountLinkScreen extends StatefulWidget {
  const FixAccountLinkScreen({super.key});

  @override
  State<FixAccountLinkScreen> createState() => _FixAccountLinkScreenState();
}

enum _LinkStatus { ok, missing, mismatch }

class _FixAccountLinkScreenState extends State<FixAccountLinkScreen> {
  final _idController = TextEditingController();
  bool _showKeyboard = false;
  bool _checking = false;
  bool _fixing = false;

  // Result of the last check.
  bool _checked = false;
  List<QueryDocumentSnapshot>? _matchingUsers; // users with this id_number
  DocumentSnapshot? _indexDoc; // id_index/{docId}, may not exist
  Map<String, dynamic>? _currentlyLinkedUser; // whoever id_index currently points to, if different
  _LinkStatus? _status;

  void _hideKeyboard() {
    setState(() => _showKeyboard = false);
    FocusScope.of(context).unfocus();
  }

  Future<void> _check() async {
    final typed = _idController.text.trim();
    if (typed.isEmpty) {
      showAppNotification(context, message: 'Enter an ID number to check', isError: true);
      return;
    }
    _hideKeyboard();
    setState(() {
      _checking = true;
      _checked = false;
      _matchingUsers = null;
      _indexDoc = null;
      _currentlyLinkedUser = null;
      _status = null;
    });

    try {
      final docId = sanitizeIdForDoc(typed);
      final idUpper = typed.toUpperCase();

      // The source of truth: whoever's own user doc actually has this
      // id_number, regardless of what the index says.
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('id_number', isEqualTo: idUpper)
          .get();

      final indexDoc =
          await FirebaseFirestore.instance.collection('id_index').doc(docId).get();

      _LinkStatus status;
      Map<String, dynamic>? linkedUser;

      if (usersQuery.docs.isEmpty) {
        // No account owns this ID at all — nothing to link.
        status = _LinkStatus.missing;
      } else if (!indexDoc.exists) {
        status = _LinkStatus.missing;
      } else {
        final correctUid = usersQuery.docs.first.id;
        final linkedUid = (indexDoc.data() as Map<String, dynamic>?)?['uid'] as String?;
        if (linkedUid == correctUid) {
          status = _LinkStatus.ok;
        } else {
          status = _LinkStatus.mismatch;
          if (linkedUid != null && linkedUid.isNotEmpty) {
            final wrongUserDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(linkedUid)
                .get();
            linkedUser = wrongUserDoc.data() as Map<String, dynamic>?;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _matchingUsers = usersQuery.docs;
        _indexDoc = indexDoc;
        _currentlyLinkedUser = linkedUser;
        _status = status;
        _checked = true;
      });
    } catch (e) {
      if (!mounted) return;
      showAppNotification(context, message: 'Could not check this ID: $e', isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _fixLink() async {
    final matches = _matchingUsers;
    if (matches == null || matches.isEmpty) return;

    final correct = matches.first;
    final data = correct.data() as Map<String, dynamic>;
    final name = (data['name'] as String?) ?? 'this user';
    final email = (data['email'] as String?) ?? '';
    final docId = sanitizeIdForDoc(_idController.text.trim());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Fix this link?'),
        content: Text(
          'This ID number will be linked to $name\'s account. Anyone logging in '
          'with this ID will sign into their account from now on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Fix Link',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _fixing = true);
    try {
      await FirebaseFirestore.instance.collection('id_index').doc(docId).set({
        'email': email,
        'uid': correct.id,
      });
      if (!mounted) return;
      showAppNotification(context, message: 'Link fixed — this ID now points to $name.');
      await _check(); // refresh the status to show it's now OK
    } catch (e) {
      if (!mounted) return;
      showAppNotification(context, message: 'Could not fix the link: $e', isError: true);
    } finally {
      if (mounted) setState(() => _fixing = false);
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(title: 'Fix Account Link'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _hideKeyboard,
                behavior: HitTestBehavior.opaque,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'If someone logs in with the right ID number but lands in '
                        'someone else\'s account, that ID\'s login link is pointing '
                        'to the wrong person. Check it here and fix it in one tap.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      SizedBox(height: 20),
                      TextField(
                        controller: _idController,
                        showCursor: true,
                        onTap: () => setState(() => _showKeyboard = true),
                        textCapitalization: TextCapitalization.characters,
                        style: TextStyle(color: AppColors.primaryDark),
                        decoration: InputDecoration(
                          labelText: 'ID number to check',
                          hintText: 'e.g. MSA/2024/045',
                          prefixIcon: Icon(Icons.badge_outlined, color: AppColors.primary),
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
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        ),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _checking ? null : _check,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          elevation: 4,
                          shadowColor: AppColors.primary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _checking
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Check Link',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      if (_checked) ...[
                        SizedBox(height: 24),
                        _resultCard(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (_showKeyboard)
              VirtualKeyboard(
                controller: _idController,
                onDone: _hideKeyboard,
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard() {
    final matches = _matchingUsers ?? [];

    if (matches.isEmpty) {
      return _statusCard(
        icon: Icons.help_outline,
        color: Colors.grey,
        title: 'No account has this ID number',
        body: 'Double-check the ID number, or this person may not be '
            'registered yet.',
      );
    }

    if (matches.length > 1) {
      final names = matches
          .map((d) => (d.data() as Map<String, dynamic>)['name'] as String? ?? 'Unknown')
          .join(', ');
      return _statusCard(
        icon: Icons.error_outline,
        color: Colors.redAccent,
        title: 'This ID is registered on multiple accounts',
        body: 'Accounts: $names. This needs to be fixed manually in the '
            'Firestore console — a duplicate ID number can\'t be safely '
            'auto-corrected here.',
      );
    }

    final matchDoc = matches.first;
    final data = matchDoc.data() as Map<String, dynamic>;
    final name = (data['name'] as String?) ?? 'Unknown';
    final email = (data['email'] as String?) ?? '';

    switch (_status!) {
      case _LinkStatus.ok:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusCard(
              icon: Icons.check_circle_outline,
              color: AppColors.accent,
              title: 'Correctly linked',
              body: 'This ID number signs in to $name\'s account ($email), as expected.',
            ),
            SizedBox(height: 14),
            _viewAccountButton(matchDoc.id, name),
          ],
        );

      case _LinkStatus.missing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusCard(
              icon: Icons.link_off,
              color: Colors.orange,
              title: 'No login link exists for this ID',
              body: '$name owns this ID number, but there\'s no way to log in '
                  'with it yet. Fixing this will create the missing link.',
            ),
            SizedBox(height: 14),
            _fixButton(),
            SizedBox(height: 10),
            _viewAccountButton(matchDoc.id, name),
          ],
        );

      case _LinkStatus.mismatch:
        final wrongName =
            (_currentlyLinkedUser?['name'] as String?) ?? 'a different account';
        final wrongEmail = (_currentlyLinkedUser?['email'] as String?) ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusCard(
              icon: Icons.error_outline,
              color: Colors.redAccent,
              title: 'This ID is linked to the wrong account',
              body: '$name owns this ID number, but logging in with it currently '
                  'signs into $wrongName\'s account instead'
                  '${wrongEmail.isNotEmpty ? ' ($wrongEmail)' : ''}.',
            ),
            SizedBox(height: 14),
            _fixButton(),
            SizedBox(height: 10),
            _viewAccountButton(matchDoc.id, name),
          ],
        );
    }
  }

  // Lets staff jump straight from a confirmed ID lookup into that
  // person's full account — view every field, edit it, and move
  // students between groups — without needing to hunt for them
  // again inside a Group screen.
  Widget _viewAccountButton(String uid, String name) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.push(context, slideRoute(UserRecordScreen(uid: uid)));
      },
      icon: Icon(Icons.manage_accounts_outlined, size: 18, color: AppColors.primary),
      label: Text(
        'View & Edit $name\'s Account',
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _fixButton() {
    return ElevatedButton.icon(
      onPressed: _fixing ? null : _fixLink,
      icon: _fixing
          ? SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : Icon(Icons.build_outlined, size: 18),
      label: Text('Fix Link', style: TextStyle(fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: appCardShadow(),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
