const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendDispatchNotification = functions.firestore
  .document("dispatches/{dispatchId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();

    const responderEmails = data.responderEmails || [];
    const alertLocation = data.userAddress || "Unknown location";

    if (responderEmails.length === 0) return;

    // Get tokens for responders
    const tokenSnap = await admin.firestore()
      .collection("fcm_tokens")
      .where("email", "in", responderEmails)
      .get();

    const tokens = tokenSnap.docs.map(doc => doc.data().token);
    if (!tokens.length) return;

    const payload = {
      notification: {
        title: "🚨 Dispatch Alert!",
        body: `You have been dispatched to: ${alertLocation}`,
      },
      data: {
        type: "dispatch",
        location: alertLocation,
      },
    };

    await admin.messaging().sendToDevice(tokens, payload);

    console.log("📨 Notification sent to responders:", responderEmails);
  });
