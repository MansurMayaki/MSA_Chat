import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart' show AppColors, buildAppBar;
import 'virtual_keyboard.dart';
import 'app_notify.dart';

class SendNotificationScreen extends StatefulWidget {
  const SendNotificationScreen({super.key});

  @override
  State<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends State<SendNotificationScreen> {
  final _messageController = TextEditingController();
  bool _isSending = false;
  bool _showKeyboard = false;

  void _hideKeyboard() {
    setState(() => _showKeyboard = false);
    FocusScope.of(context).unfocus();
  }

  void _showKeyboardNow() {
    setState(() => _showKeyboard = true);
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      showAppNotification(context, message: 'Please type a message', isError: true);
      return;
    }

    setState(() => _isSending = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      String senderName = 'Staff';
      if (uid != null) {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        senderName = (userDoc.data()?['name'] as String?) ?? 'Staff';
      }

      await FirebaseFirestore.instance.collection('broadcasts').add({
        'message': text,
        'senderId': uid,
        'senderName': senderName,
        'sentAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      showAppNotification(context, message: 'Notification sent to everyone!');
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showAppNotification(context, message: 'Could not send notification', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(title: 'Send Notification'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onTap: _hideKeyboard,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'This will be sent to everybody in the chat.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _messageController,
                      showCursor: true,
                      maxLines: 5,
                      onTap: _showKeyboardNow,
                      style: TextStyle(color: AppColors.primaryDark),
                      decoration: InputDecoration(
                        labelText: 'Message',
                        hintText: 'Type your announcement...',
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
                          borderSide:
                              BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      ),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isSending ? null : _send,
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
                      child: _isSending
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Send to Everyone',
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
            if (_showKeyboard)
              VirtualKeyboard(
                controller: _messageController,
                onDone: _hideKeyboard,
              ),
          ],
        ),
      ),
    );
  }
}
