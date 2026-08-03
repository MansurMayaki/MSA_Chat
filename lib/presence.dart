import 'package:cloud_firestore/cloud_firestore.dart';

/// Marks a user online/offline in Firestore. This is best-effort — since
/// we're not using Realtime Database's onDisconnect, an abrupt tab close
/// (rather than a normal logout) won't flip someone offline instantly, but
/// app lifecycle changes (backgrounding, logging out) are covered.
Future<void> setUserOnline(String uid) async {
  if (uid.isEmpty) return;
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'online': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (_) {
    // Not critical — presence just won't update this time.
  }
}

Future<void> setUserOffline(String uid) async {
  if (uid.isEmpty) return;
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'online': false,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (_) {
    // Not critical — presence just won't update this time.
  }
}
