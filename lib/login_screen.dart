import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' show AppColors;
import 'virtual_keyboard.dart';
import 'app_notify.dart';
import 'register_screen.dart';
import 'group_screen.dart';

const _lastLoginIdKey = 'last_login_id';

// Same sanitization used everywhere an ID number is turned into a doc key.
String sanitizeIdForDoc(String id) {
  return id.trim().toUpperCase().replaceAll('/', '_');
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  TextEditingController? _activeController;

  @override
  void initState() {
    super.initState();
    _loadRememberedId();
  }

  Future<void> _loadRememberedId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_lastLoginIdKey);
      if (savedId != null && savedId.isNotEmpty && mounted) {
        setState(() => _idController.text = savedId);
      }
    } catch (_) {
      // Storage unavailable — just skip the prefill, no need to crash.
    }
  }

  Future<void> _rememberId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastLoginIdKey, id);
    } catch (_) {
      // Storage unavailable — login already succeeded, so don't block on this.
    }
  }

  void _hideKeyboard() {
    setState(() => _activeController = null);
    FocusScope.of(context).unfocus();
  }

  void _showKeyboardFor(TextEditingController controller) {
    setState(() => _activeController = controller);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final docId = sanitizeIdForDoc(_idController.text);

      // Look up which email this ID number is linked to.
      final indexDoc = await FirebaseFirestore.instance
          .collection('id_index')
          .doc(docId)
          .get();

      if (!indexDoc.exists) {
        throw FirebaseAuthException(
          code: 'id-not-found',
          message: 'Incorrect ID number or password',
        );
      }

      final email = indexDoc.data()!['email'] as String;

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );

      // Remember this ID so next time only the password is needed.
      await _rememberId(_idController.text.trim().toUpperCase());

      if (!mounted) return;
      showAppNotification(context, message: 'Logged in successfully!');
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const GroupRouter()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = 'Login failed';
      if (e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'id-not-found') {
        message = 'Incorrect ID number or password';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect ID number or password';
      } else if (e.message != null) {
        message = e.message!;
      }
      showAppNotification(context, message: message, isError: true);
    } on FirebaseException catch (e) {
      // Covers Firestore errors, e.g. permission-denied from security rules.
      if (!mounted) return;
      showAppNotification(
        context,
        message: 'Could not look up your account (${e.code}). Check Firestore rules.',
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

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    bool isSending = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reset Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the email address you registered with. '
                    'We\'ll send a password reset link to it.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          final emailRegex =
                              RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                          if (!emailRegex.hasMatch(email)) {
                            showAppNotification(
                              dialogContext,
                              message: 'Enter a valid email address',
                              isError: true,
                            );
                            return;
                          }
                          setDialogState(() => isSending = true);
                          try {
                            await FirebaseAuth.instance
                                .sendPasswordResetEmail(email: email);

                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            showAppNotification(
                              context,
                              message: 'Reset link sent! Check your email.',
                            );
                          } on FirebaseAuthException catch (e) {
                            setDialogState(() => isSending = false);
                            if (!dialogContext.mounted) return;
                            String message = e.message ?? 'Could not send reset link';
                            if (e.code == 'user-not-found') {
                              message = 'No account found with that email';
                            }
                            showAppNotification(
                              dialogContext,
                              message: message,
                              isError: true,
                            );
                          }
                        },
                  child: isSending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Link'),
                ),
              ],
            );
          },
        );
      },
    );
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
                        constraints: BoxConstraints(maxWidth: 400),
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
                              'Welcome Back',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Login with your ID number',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 28),

                            _buildTextField(
                              controller: _idController,
                              label: 'Student/Staff ID',
                              icon: Icons.badge_outlined,
                              helperText: 'e.g. MSA/12345 or FAC/12345',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your ID number';
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
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 8),

                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _showForgotPasswordDialog,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 12),

                            ElevatedButton(
                              onPressed: _isLoading ? null : _login,
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
                                      'Login',
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
                                  "Don't have an account? ",
                                  style: TextStyle(color: Colors.grey),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            RegisterScreen(),
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
                                    'Register',
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
