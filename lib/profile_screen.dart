import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_notify.dart';
import 'main.dart'
    show
        AppColors,
        ThemeController,
        AppRadius,
        appCardShadow,
        buildAppBar,
        slideRoute,
        appRouteObserver;
import 'fix_account_link_screen.dart';

/// Max size (in encoded base64 characters) we'll accept for a profile
/// photo. Firestore documents cap out at 1MiB total, so this keeps a
/// single photo comfortably under that with plenty of room left for the
/// rest of the user doc. image_picker's maxWidth/maxHeight/imageQuality
/// keep us well under this in practice — this is just a safety net.
const _maxPhotoBase64Length = 700000;

/// Builds a circular avatar from a user's Firestore data: shows their
/// decoded photo if they have one, otherwise falls back to their
/// initial letter. Shared so every screen renders avatars the same way.
Widget buildUserAvatar({
  required Map<String, dynamic>? userData,
  required String fallbackName,
  double radius = 26,
}) {
  final photoBase64 = userData?['photoBase64'] as String?;

  if (photoBase64 != null && photoBase64.isNotEmpty) {
    try {
      final bytes = base64Decode(photoBase64);
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        backgroundImage: MemoryImage(bytes),
      );
    } catch (_) {
      // Corrupt/undecodable data — fall through to initials rather than
      // crashing the list this avatar is rendered in.
    }
  }

  return CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
    child: Text(
      fallbackName.isNotEmpty ? fallbackName[0].toUpperCase() : '?',
      style: TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.bold,
        fontSize: radius * 0.7,
      ),
    ),
  );
}

/// Lets the signed-in user update their own username, phone number, bio,
/// and profile picture. Email, ID number, role, and group are shown
/// read-only for context — those are controlled elsewhere (registration /
/// staff group-moves), not from here.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(title: 'My Profile'),
      body: ProfileForm(),
    );
  }
}

/// The actual profile-editing form — no Scaffold/AppBar of its own, so it
/// can be dropped into any host: the standalone [ProfileScreen] above (for
/// when it's reached via push, e.g. tapping your own name in a group), or
/// directly as a bottom-nav tab body in [MainScreen].
class ProfileForm extends StatefulWidget {
  const ProfileForm({super.key});

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> with RouteAware {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _photoBase64;
  Map<String, dynamic>? _userData;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // Fires when a screen pushed on top of this one (e.g. the profile view
  // opened by tapping your own name in a group) is popped and this tab
  // becomes visible again — the trigger for the "stale Profile tab" bug.
  @override
  void didPopNext() {
    _loadProfile(silent: true);
  }

  Future<void> _loadProfile({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final data = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _nameController.text = (data['name'] as String?) ?? '';
        _phoneController.text = (data['phone'] as String?) ?? '';
        _bioController.text = (data['bio'] as String?) ?? '';
        _photoBase64 = data['photoBase64'] as String?;
        _userData = data;
      });
    } catch (_) {
      // If this fails the form just starts blank — the user can still
      // fill it in and save, which will populate the doc going forward.
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final encoded = base64Encode(bytes);

      if (encoded.length > _maxPhotoBase64Length) {
        if (!mounted) return;
        showAppNotification(
          context,
          message: 'That photo is too large — try a smaller or simpler image.',
          isError: true,
        );
        return;
      }

      setState(() => _photoBase64 = encoded);
    } catch (e) {
      if (!mounted) return;
      showAppNotification(
        context,
        message: 'Could not open photo picker: $e',
        isError: true,
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'bio': _bioController.text.trim(),
        'photoBase64': _photoBase64,
      });

      if (!mounted) return;
      showAppNotification(context, message: 'Profile updated');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      showAppNotification(
        context,
        message: 'Could not save (${e.code}). Check Firestore rules.',
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;
      showAppNotification(context, message: 'Something went wrong: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        : SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 420),
                  child: Column(
                    children: [
                      _avatarPicker(),
                      SizedBox(height: 28),
                      TextFormField(
                        controller: _nameController,
                        // Keep the fallback-initial avatar in sync while typing.
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: AppColors.primaryDark),
                        decoration: _decoration('Username', Icons.person_outline),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
                      ),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(color: AppColors.primaryDark),
                        decoration: _decoration('Phone number', Icons.phone_outlined),
                      ),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _bioController,
                        maxLines: 3,
                        maxLength: 150,
                        style: TextStyle(color: AppColors.primaryDark),
                        decoration: _decoration('Bio', Icons.info_outline),
                      ),
                      if (_userData != null) _readOnlyInfo(),
                      if (_userData?['role'] == 'staff') _adminToolsSection(),
                      SizedBox(height: 16),
                      _darkModeToggle(),
                      SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
  }

  Widget _avatarPicker() {
    final hasPhoto = _photoBase64 != null && _photoBase64!.isNotEmpty;

    return Stack(
      children: [
        GestureDetector(
          // Tapping the picture itself just views it full-size. There's
          // nothing to view yet if no photo has been set, so no tap
          // handler in that case — only the camera badge picks a photo.
          onTap: hasPhoto ? _viewFullPhoto : null,
          child: hasPhoto
              ? CircleAvatar(
                  radius: 56,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  backgroundImage: MemoryImage(base64Decode(_photoBase64!)),
                )
              : CircleAvatar(
                  radius: 56,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    _nameController.text.isNotEmpty
                        ? _nameController.text[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 40,
                    ),
                  ),
                ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: AppColors.accent,
            shape: CircleBorder(),
            child: InkWell(
              customBorder: CircleBorder(),
              onTap: _pickPhoto,
              child: Padding(
                padding: EdgeInsets.all(9),
                child: Icon(Icons.camera_alt, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _viewFullPhoto() {
    if (_photoBase64 == null || _photoBase64!.isEmpty) return;
    Navigator.push(
      context,
      slideRoute(_FullscreenProfilePhoto(bytes: base64Decode(_photoBase64!))),
    );
  }

  Widget _readOnlyInfo() {
    final email = _userData?['email'] as String? ?? '';
    final idNumber = _userData?['id_number'] as String? ?? '';
    final role = _userData?['role'] as String? ?? '';
    final group = _userData?['group'] as String? ?? '';

    return Padding(
      padding: EdgeInsets.only(top: 20),
      child: Container(
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
            _infoRow('Email', email),
            _infoRow('ID Number', idNumber),
            _infoRow('Role', role == 'staff' ? 'Staff' : 'Student'),
            _infoRow('Group', group),
          ],
        ),
      ),
    );
  }

  Widget _adminToolsSection() {
    return Padding(
      padding: EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: appCardShadow(),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                slideRoute(const FixAccountLinkScreen()),
              );
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.link, color: AppColors.primary, size: 20),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fix Account Link',
                          style: TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Check or repair someone\'s ID login link',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _darkModeToggle() {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.instance.isDark,
      builder: (context, isDark, _) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.fieldFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.fieldBorder),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: isDark,
            onChanged: (_) => ThemeController.instance.toggle(),
            activeThumbColor: AppColors.accent,
            title: Text(
              'Dark Mode',
              style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            secondary: Icon(
              isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary),
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
    );
  }
}

/// Read-only view of another user's profile — reachable by tapping their
/// avatar in a group member list or chat list. Shows the same info as
/// [ProfileForm] but with no editable fields and no camera/save controls.
class UserProfileViewScreen extends StatefulWidget {
  final String userId;
  final String fallbackName;

  const UserProfileViewScreen({
    super.key,
    required this.userId,
    required this.fallbackName,
  });

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  // userId is fixed for this screen's whole lifetime, so this only needs
  // to be built once — an inline stream in build() would otherwise be
  // torn down and reopened on every rebuild, e.g. every dark-mode toggle.
  late final Stream<DocumentSnapshot> _userDocStream;

  @override
  void initState() {
    super.initState();
    _userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(title: 'Profile'),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _userDocStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            // Most likely cause: Firestore security rules are blocking this
            // read (e.g. rules only allow reading your own user doc, or
            // only members of the same group). Surface that clearly instead
            // of silently falling back to blank fields, which looked like
            // "the ID/level just isn't showing" with no explanation.
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, color: Colors.grey, size: 40),
                    SizedBox(height: 12),
                    Text(
                      'Could not load this profile',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'This is usually a Firestore permissions issue — ask an '
                      'admin to check that the "users" collection can be read '
                      'across groups, not just within the same one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final name = (data['name'] as String?) ?? widget.fallbackName;
          final photoBase64 = data['photoBase64'] as String?;
          final bio = (data['bio'] as String?) ?? '';
          final phone = (data['phone'] as String?) ?? '';
          final role = (data['role'] as String?) ?? '';
          final group = (data['group'] as String?) ?? '';
          final idNumber = (data['id_number'] as String?) ?? '';
          final hasPhoto = photoBase64 != null && photoBase64.isNotEmpty;

          return SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: hasPhoto
                          ? () => Navigator.push(
                                context,
                                slideRoute(_FullscreenProfilePhoto(
                                  bytes: base64Decode(photoBase64),
                                )),
                              )
                          : null,
                      child: buildUserAvatar(
                        userData: data,
                        fallbackName: name,
                        radius: 56,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      name,
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      role == 'staff' ? 'Staff' : 'Student',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    SizedBox(height: 24),
                    Container(
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
                          if (bio.isNotEmpty) ...[
                            Text(
                              'Bio',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            SizedBox(height: 4),
                            Text(
                              bio,
                              style: TextStyle(
                                color: AppColors.primaryDark,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 14),
                          ],
                          _viewInfoRow('Phone', phone.isEmpty ? 'Not set' : phone),
                          _viewInfoRow('ID Number', idNumber.isEmpty ? 'Not set' : idNumber),
                          _viewInfoRow('Group', group),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _viewInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen, pinch-to-zoom view of the profile picture — opened by
/// tapping the picture itself (not the camera badge, which picks a new one).
class _FullscreenProfilePhoto extends StatelessWidget {
  final Uint8List bytes;

  const _FullscreenProfilePhoto({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(
            bytes,
            errorBuilder: (context, error, stack) => Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}
