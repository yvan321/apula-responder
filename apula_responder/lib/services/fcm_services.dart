import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FCMService {
  static Future<void> saveFcmToken(String userId, String email) async {
    final fcm = FirebaseMessaging.instance;

    // Ask for permission
    await fcm.requestPermission();

    // Get the FCM device token
    final token = await fcm.getToken();
    if (token == null) return;

    // Save to Firestore
    await FirebaseFirestore.instance
        .collection("fcm_tokens")
        .doc(userId)
        .set({
      "userId": userId,
      "email": email,
      "token": token,
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }
}
