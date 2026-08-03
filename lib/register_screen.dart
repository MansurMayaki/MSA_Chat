import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart' show AppColors;
import 'virtual_keyboard.dart';
import 'app_notify.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _role; // 'student' or 'staff'
  String? _level; // 'beginners' | 'intermediate' | 'advance' (students only)

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  TextEditingController? _activeController;

  void _hideKeyboard() {
    setState(() => _activeController = null);
    FocusScope.of(context).unfocus();
  }

  void _showKeyboardFor(TextEditingController controller) {
    setState(() => _activeController = controller);
  }

  void _onRoleChanged(String? value) {
    setState(() {
      _role = value;
      _level = null; // reset level whenever role changes
      if (value == 'student') {
        _idController.text = 'MSA/${DateTime.now().year}/';
      } else if (value == 'staff') {
        _idController.text = 'FAC/';
      } else {
        _idController.text = '';
      }
      _idController.selection = TextSelection.collapsed(
        offset: _idController.text.length,
      );
    });
  }

  String get _idHelperText {
    if (_role == 'student') return 'Format: MSA/${DateTime.now().year}/1234 (year can vary)';
    if (_role == 'staff') return 'Format: FAC/12345';
    return 'Select a role first';
  }

  // Builds the group this user belongs to, based on role + level.
  // This is what routes them straight into the right group after signup.
  String _computeGroup() {
    if (_role == 'staff') return 'staff';
    return _level ?? 'beginners';
  }

  Future<void> _register() async {
    if (_role == null) {
      showAppNotification(
        context,
        message: 'Please select a role',
        isError: true,
      );
      return;
    }
    if (_role == 'student' && _level == null) {
      showAppNotification(
        context,
        message: 'Please select your level',
        isError: true,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final idDocId = sanitizeIdForDoc(_idController.text);
      final group = _computeGroup();

      // Make sure this ID number isn't already registered before we
      // create a Firebase Auth account for it.
      final existingIndex = await FirebaseFirestore.instance
          .collection('id_index')
          .doc(idDocId)
          .get();
      if (existingIndex.exists) {
        throw FirebaseAuthException(
          code: 'id-already-in-use',
          message: 'This ID number is already registered',
        );
      }

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email,
            password: _passwordController.text.trim(),
          );

      final uid = credential.user!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': _nameController.text.trim(),
        'email': email,
        'id_number': _idController.text.trim().toUpperCase(),
        'role': _role,
        'level': _role == 'student' ? _level : null,
        'group': group,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Lookup table so people can log in / reset their password using
      // just their ID number instead of typing an email.
      await FirebaseFirestore.instance
          .collection('id_index')
          .doc(idDocId)
          .set({'email': email, 'uid': uid});

      // Sign out immediately after registering — the user must log in
      // themselves next.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      showAppNotification(context, message: 'Account created successfully!');
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = e.message ?? 'Registration failed';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already registered';
      } else if (e.code == 'id-already-in-use') {
        message = 'This ID number is already registered';
      }
      showAppNotification(context, message: message, isError: true);
    } on FirebaseException catch (e) {
      // Covers Firestore errors, e.g. permission-denied from security rules.
      if (!mounted) return;
      showAppNotification(
        context,
        message: 'Could not save your account (${e.code}). Check Firestore rules.',
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;
      showAppNotification(
        context,
        message: 'Something went wrong: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _hideKeyboard,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Form(
                      key: _formKey,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 150,
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Create Account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Join MSA_Chat',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 28),

                            _buildTextField(
                              controller: _nameController,
                              label: 'Full Name',
                              icon: Icons.person_outline,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your full name';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 16),

                            _buildTextField(
                              controller: _emailController,
                              label: 'Email',
                              icon: Icons.email_outlined,
                              helperText:
                                  'Used only for password reset',
                              validator: (value) {
                                final v = (value ?? '').trim();
                                if (v.isEmpty) {
                                  return 'Please enter your email';
                                }
                                final emailRegex =
                                    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                                if (!emailRegex.hasMatch(v)) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 16),

                            // Role dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _role,
                              decoration: _dropdownDecoration(
                                'Role',
                                Icons.badge_outlined,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'student',
                                  child: Text('Student'),
                                ),
                                DropdownMenuItem(
                                  value: 'staff',
                                  child: Text('Staff'),
                                ),
                              ],
                              onChanged: _onRoleChanged,
                              validator: (value) =>
                                  value == null ? 'Please select a role' : null,
                            ),
                            SizedBox(height: 16),

                            // Level dropdown (students only) — this decides
                            // which group they're dropped into right away.
                            if (_role == 'student') ...[
                              DropdownButtonFormField<String>(
                                initialValue: _level,
                                decoration: _dropdownDecoration(
                                  'Level',
                                  Icons.stairs_outlined,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'beginners',
                                    child: Text('Beginners'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'intermediate',
                                    child: Text('Intermediate'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'advance',
                                    child: Text('Advance'),
                                  ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _level = value),
                                validator: (value) => value == null
                                    ? 'Please select your level'
                                    : null,
                              ),
                              SizedBox(height: 16),
                            ],

                            // ID Number field
                            _buildTextField(
                              controller: _idController,
                              label: _role == 'staff'
                                  ? 'Staff ID'
                                  : 'Student ID',
                              icon: Icons.badge_outlined,
                              helperText: _idHelperText,
                              validator: (value) {
                                if (_role == null) return 'Select a role first';
                                final v = (value ?? '').trim().toUpperCase();
                                if (_role == 'student' &&
                                    !RegExp(r'^MSA/\d{4}/\d+$').hasMatch(v)) {
                                  return 'Must be like MSA/${DateTime.now().year}/1234';
                                }
                                if (_role == 'staff' &&
                                    !RegExp(r'^FAC/\d+$').hasMatch(v)) {
                                  return 'Must be like FAC/12345';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 16),

                            _buildTextField(
                              controller: _passwordController,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a password';
                                }
                                if (value.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 16),

                            _buildTextField(
                              controller: _confirmPasswordController,
                              label: 'Confirm Password',
                              icon: Icons.lock_outline,
                              obscureText: _obscureConfirmPassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                              ),
                              validator: (value) {
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 26),

                            ElevatedButton(
                              onPressed: _isLoading ? null : _register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Register',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            SizedBox(height: 20),

                            Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                Text(
                                  'Already have an account? ',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            LoginScreen(),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Login',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_activeController != null)
              VirtualKeyboard(
                controller: _activeController!,
                onDone: _hideKeyboard,
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label, IconData icon) {
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      showCursor: true,
      onTap: () => _showKeyboardFor(controller),
      style: TextStyle(color: AppColors.primaryDark),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: suffixIcon,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 16,
        ),
      ),
    );
  }
}
