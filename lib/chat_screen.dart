import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'main.dart' show AppColors, AppRadius, slideRoute;
import 'virtual_keyboard.dart';
import 'app_notify.dart';
import 'profile_screen.dart' show UserProfileViewScreen;

/// Builds a stable, deterministic chat ID for any pair of users — the same
/// two people always land in the same chat document, no matter who starts
/// the conversation first.
String chatIdFor(String uidA, String uidB) {
  final ids = [uidA, uidB]..sort();
  return '${ids[0]}_${ids[1]}';
}

class ChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showKeyboard = false;
  bool _isSending = false;
  bool _isUploadingImage = false;
  String? _replyingToText;
  String? _replyingToSenderName;
  int _markedReadForDocCount = -1;
  Timer? _typingTimer;
  bool _typingFlagSet = false;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _chatId => chatIdFor(_currentUserId, widget.otherUserId);

  // Created once per screen instance instead of inline in build(). A
  // StreamBuilder treats a new Stream object as "different" even when the
  // underlying query is identical, so building these inline would cancel
  // and reopen every Firestore listener on this screen on every rebuild
  // (e.g. every time dark mode is toggled, or setState runs for any
  // reason) — visible as a flash back to a loading state.
  late final Stream<DocumentSnapshot> _chatDocStream;
  late final Stream<DocumentSnapshot> _otherUserDocStream;
  late final Stream<QuerySnapshot> _messagesStream;

  @override
  void initState() {
    super.initState();
    _chatDocStream =
        FirebaseFirestore.instance.collection('chats').doc(_chatId).snapshots();
    _otherUserDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .snapshots();
    _messagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .snapshots();
    _markAsRead();
    _messageController.addListener(_onMessageChanged);
  }

  // Debounced "I'm typing" flag — set true while text is present, cleared
  // 3 seconds after the last keystroke (or immediately once sent/emptied).
  void _onMessageChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;

    if (hasText) {
      if (!_typingFlagSet) {
        _typingFlagSet = true;
        _setTyping(true);
      }
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _typingFlagSet = false;
        _setTyping(false);
      });
    } else {
      _typingTimer?.cancel();
      if (_typingFlagSet) {
        _typingFlagSet = false;
        _setTyping(false);
      }
    }
  }

  Future<void> _setTyping(bool isTyping) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
        'typing': {_currentUserId: isTyping},
      }, SetOptions(merge: true));
    } catch (_) {
      // Not critical — typing indicator just won't update this time.
    }
  }

  // Records that I've seen the conversation up to "now". Also used to
  // decide whether MY sent messages show as read (blue ticks) to me.
  Future<void> _markAsRead() async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
        'lastReadAt': {_currentUserId: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (_) {
      // Not critical — read ticks just won't update this time.
    }
  }

  void _hideKeyboard() {
    setState(() => _showKeyboard = false);
    FocusScope.of(context).unfocus();
  }

  void _showKeyboardNow() {
    setState(() => _showKeyboard = true);
  }

  Future<void> _pickAndSendImage() async {
    if (_isUploadingImage || _isSending) return;

    final picker = ImagePicker();
    // Kept small on purpose — this gets embedded as text directly inside
    // the Firestore message document (no Storage bucket needed), and
    // Firestore caps each document at 1 MiB.
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 720,
      imageQuality: 55,
    );
    if (picked == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final bytes = await picked.readAsBytes();

      if (bytes.lengthInBytes > 650000) {
        if (mounted) {
          showAppNotification(
            context,
            message: 'That photo is too large — try a different one.',
            isError: true,
          );
        }
        return;
      }

      final imageBase64 = base64Encode(bytes);
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);

      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      final myName = (currentUserDoc.data()?['name'] as String?) ?? 'Someone';
      final myGroup = (currentUserDoc.data()?['group'] as String?) ?? '';

      final otherUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();
      final otherGroup = (otherUserDoc.data()?['group'] as String?) ?? '';

      await chatRef.set({
        'participants': [_currentUserId, widget.otherUserId],
        'participantNames': {
          _currentUserId: myName,
          widget.otherUserId: widget.otherUserName,
        },
        'participantGroups': {
          _currentUserId: myGroup,
          widget.otherUserId: otherGroup,
        },
        'lastMessage': '📷 Photo',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': _currentUserId,
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderId': _currentUserId,
        'text': '',
        'imageBase64': imageBase64,
        'sentAt': FieldValue.serverTimestamp(),
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppNotification(context, message: 'Could not send photo.', isError: true);
      }
      // Upload failed — nothing was sent, so nothing to restore.
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final replyText = _replyingToText;
    final replySenderName = _replyingToSenderName;

    setState(() {
      _isSending = true;
      _replyingToText = null;
      _replyingToSenderName = null;
    });
    _messageController.clear();
    _typingTimer?.cancel();
    _typingFlagSet = false;
    _setTyping(false);

    try {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      final myName = (currentUserDoc.data()?['name'] as String?) ?? 'Someone';
      final myGroup = (currentUserDoc.data()?['group'] as String?) ?? '';

      final otherUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();
      final otherGroup = (otherUserDoc.data()?['group'] as String?) ?? '';

      // Make sure the parent chat doc exists / stays up to date, so it can
      // later power a "recent chats" list without extra reads.
      await chatRef.set({
        'participants': [_currentUserId, widget.otherUserId],
        'participantNames': {
          _currentUserId: myName,
          widget.otherUserId: widget.otherUserName,
        },
        'participantGroups': {
          _currentUserId: myGroup,
          widget.otherUserId: otherGroup,
        },
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': _currentUserId,
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderId': _currentUserId,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
        'replyToText': ?replyText,
        'replyToSenderName': ?replySenderName,
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {
      // If sending fails, put the text (and any reply) back so nothing is lost.
      if (mounted) {
        _messageController.text = text;
        setState(() {
          _replyingToText = replyText;
          _replyingToSenderName = replySenderName;
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showMessageActions({
    required String messageId,
    required bool isMine,
    required String text,
    required String senderName,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.reply, color: AppColors.primary),
                title: Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    _replyingToText = text;
                    _replyingToSenderName = senderName;
                  });
                },
              ),
              if (isMine)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _deleteMessage(messageId);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(messageId)
          .update({'deleted': true, 'text': ''});
    } catch (_) {
      // Not critical to surface — the message just won't delete this time.
    }
  }

  void _cancelReply() {
    setState(() {
      _replyingToText = null;
      _replyingToSenderName = null;
    });
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatLastSeen(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final time = _formatTime(ts);
    if (isToday) return 'Last seen today at $time';
    return 'Last seen ${dt.day}/${dt.month}/${dt.year}';
  }

  // Typing beats online/last-seen — if they're typing right now, that's
  // the more useful thing to show.
  Widget _statusSubtitle() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _chatDocStream,
      builder: (context, chatSnapshot) {
        bool otherIsTyping = false;
        if (chatSnapshot.data != null && chatSnapshot.data!.exists) {
          final data = chatSnapshot.data!.data() as Map<String, dynamic>;
          final typingMap = data['typing'] as Map<String, dynamic>?;
          otherIsTyping = typingMap?[widget.otherUserId] == true;
        }

        if (otherIsTyping) {
          return Text(
            'typing...',
            style: TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
          );
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: _otherUserDocStream,
          builder: (context, userSnapshot) {
            if (userSnapshot.data == null || !userSnapshot.data!.exists) {
              return SizedBox.shrink();
            }
            final data = userSnapshot.data!.data() as Map<String, dynamic>;
            final isOnline = data['online'] == true;
            final lastSeen = data['lastSeen'] as Timestamp?;

            if (isOnline) {
              return Text(
                'Online',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              );
            }
            if (lastSeen == null) return SizedBox.shrink();
            return Text(
              _formatLastSeen(lastSeen),
              style: TextStyle(fontSize: 12, color: Colors.white70),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageChanged);
    _typingTimer?.cancel();
    if (_typingFlagSet) _setTyping(false);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppColors.appBarGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  slideRoute(UserProfileViewScreen(
                    userId: widget.otherUserId,
                    fallbackName: widget.otherUserName,
                  )),
                );
              },
              // The chat only knows the other user's name/id from
              // navigation — their photo is streamed live from their user
              // doc so this always shows their actual current DP.
              child: StreamBuilder<DocumentSnapshot>(
                stream: _otherUserDocStream,
                builder: (context, userSnapshot) {
                  final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                  final photoBase64 = userData?['photoBase64'] as String?;
                  if (photoBase64 != null && photoBase64.isNotEmpty) {
                    try {
                      return CircleAvatar(
                        radius: 18,
                        backgroundImage: MemoryImage(base64Decode(photoBase64)),
                      );
                    } catch (_) {
                      // Fall through to initials below on decode failure.
                    }
                  }
                  return CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      widget.otherUserName.isNotEmpty
                          ? widget.otherUserName[0].toUpperCase()
                          : '?',
                      style:
                          TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherUserName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  _statusSubtitle(),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _hideKeyboard,
                behavior: HitTestBehavior.opaque,
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _chatDocStream,
                  builder: (context, chatSnapshot) {
                    Timestamp? otherUserReadAt;
                    if (chatSnapshot.data != null && chatSnapshot.data!.exists) {
                      final chatData =
                          chatSnapshot.data!.data() as Map<String, dynamic>;
                      final readMap = chatData['lastReadAt'] as Map<String, dynamic>?;
                      otherUserReadAt = readMap?[widget.otherUserId] as Timestamp?;
                    }

                    return StreamBuilder<QuerySnapshot>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Could not load messages: ${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];

                    // If the newest message just arrived from the other
                    // person while I'm actively looking at this screen,
                    // mark it read right away instead of waiting for my
                    // next visit.
                    if (docs.isNotEmpty && docs.length != _markedReadForDocCount) {
                      final newest = docs.first.data() as Map<String, dynamic>;
                      if (newest['senderId'] != _currentUserId) {
                        _markedReadForDocCount = docs.length;
                        _markAsRead();
                      }
                    }

                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  size: 56, color: AppColors.primary.withValues(alpha: 0.3)),
                              SizedBox(height: 12),
                              Text(
                                'Say hi to ${widget.otherUserName} 👋',
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final isDeleted = data['deleted'] == true;
                        final text = isDeleted ? '' : (data['text'] ?? '');
                        final imageBase64 = isDeleted ? null : data['imageBase64'] as String?;
                        Uint8List? imageBytes;
                        if (imageBase64 != null && imageBase64.isNotEmpty) {
                          try {
                            imageBytes = base64Decode(imageBase64);
                          } catch (_) {
                            imageBytes = null;
                          }
                        }
                        final senderId = data['senderId'] ?? '';
                        final sentAt = data['sentAt'] as Timestamp?;
                        final isMine = senderId == _currentUserId;
                        final isRead = isMine &&
                            sentAt != null &&
                            otherUserReadAt != null &&
                            otherUserReadAt.compareTo(sentAt) >= 0;
                        final replyToText = data['replyToText'] as String?;
                        final replyToSenderName = data['replyToSenderName'] as String?;
                        final replyActionText = imageBytes != null ? '📷 Photo' : text;

                        return GestureDetector(
                          onLongPress: isDeleted
                              ? null
                              : () => _showMessageActions(
                                    messageId: doc.id,
                                    isMine: isMine,
                                    text: replyActionText,
                                    senderName: isMine ? 'You' : widget.otherUserName,
                                  ),
                          child: Align(
                          alignment:
                              isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: EdgeInsets.symmetric(vertical: 4),
                            padding: EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: isMine ? AppColors.primary : AppColors.fieldFill,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                                bottomLeft: Radius.circular(isMine ? 16 : 4),
                                bottomRight: Radius.circular(isMine ? 4 : 16),
                              ),
                              border: isMine
                                  ? null
                                  : Border.all(color: AppColors.fieldBorder),
                              boxShadow: [
                                BoxShadow(
                                  color: (isMine ? AppColors.primary : Colors.black)
                                      .withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (replyToText != null && !isDeleted)
                                  Container(
                                    margin: EdgeInsets.only(bottom: 6),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isMine
                                          ? Colors.white.withValues(alpha: 0.15)
                                          : AppColors.background,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                          color: isMine
                                              ? Colors.white.withValues(alpha: 0.6)
                                              : AppColors.primary,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          replyToSenderName ?? '',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isMine
                                                ? Colors.white
                                                : AppColors.primary,
                                          ),
                                        ),
                                        Text(
                                          replyToText,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isMine
                                                ? Colors.white70
                                                : Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (imageBytes != null)
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        slideRoute(_FullscreenImageViewer(imageBytes: imageBytes!)),
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        imageBytes,
                                        width: 200,
                                        height: 200,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stack) => SizedBox(
                                          width: 200,
                                          height: 200,
                                          child: Center(child: Icon(Icons.broken_image_outlined)),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    isDeleted ? 'This message was deleted' : text,
                                    style: TextStyle(
                                      color: isDeleted
                                          ? (isMine
                                              ? Colors.white.withValues(alpha: 0.7)
                                              : Colors.grey)
                                          : (isMine ? Colors.white : AppColors.primaryDark),
                                      fontSize: 15,
                                      fontStyle:
                                          isDeleted ? FontStyle.italic : FontStyle.normal,
                                    ),
                                  ),
                                SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatTime(sentAt),
                                      style: TextStyle(
                                        color: isMine
                                            ? Colors.white.withValues(alpha: 0.75)
                                            : Colors.grey,
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (isMine && !isDeleted) ...[
                                      SizedBox(width: 4),
                                      Icon(
                                        isRead ? Icons.done_all : Icons.done,
                                        size: 14,
                                        color: isRead
                                            ? Color(0xFF63D4FF)
                                            : Colors.white.withValues(alpha: 0.75),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    );
                  },
                    );
                  },
                ),
              ),
            ),
            if (_replyingToText != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.fieldFill,
                  border: Border(
                    top: BorderSide(color: AppColors.fieldBorder),
                    left: BorderSide(color: AppColors.primary, width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Replying to ${_replyingToSenderName ?? ''}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            _replyingToText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: Colors.grey),
                      onPressed: _cancelReply,
                    ),
                  ],
                ),
              ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.fieldBorder)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: _isUploadingImage
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: AppColors.primary, strokeWidth: 2),
                          )
                        : Icon(Icons.image_outlined, color: AppColors.primary),
                    tooltip: 'Send a photo',
                    onPressed: _isUploadingImage ? null : _pickAndSendImage,
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _messageController,
                      showCursor: true,
                      minLines: 1,
                      maxLines: 4,
                      onTap: _showKeyboardNow,
                      style: TextStyle(color: AppColors.primaryDark),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: AppColors.fieldFill,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: AppColors.fieldBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: AppColors.fieldBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: _isSending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ),
                ],
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

/// Full-screen, pinch-to-zoom viewer opened by tapping an image bubble.
class _FullscreenImageViewer extends StatelessWidget {
  final Uint8List imageBytes;

  const _FullscreenImageViewer({required this.imageBytes});

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
            imageBytes,
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
