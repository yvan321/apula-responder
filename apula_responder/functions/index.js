const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendDispatchNotification = functions.firestore
  .document("dispatches/{dispatchId}")
  .onWrite(async (change, context) => {
    try {
      const beforeExists = change.before.exists;
      const afterExists = change.after.exists;

      if (!afterExists) return null;

      const beforeData = beforeExists ? change.before.data() : null;
      const afterData = change.after.data();

      const beforeStatus = beforeData?.status || null;
      const afterStatus = afterData?.status || null;

      // Send only when status becomes Dispatched
      if (afterStatus !== "Dispatched") return null;
      if (beforeStatus === "Dispatched") return null;

      const responderEmails = Array.isArray(afterData.responderEmails)
        ? afterData.responderEmails
        : [];

      const alertLocation = afterData.userAddress || "Unknown location";

      if (responderEmails.length === 0) {
        console.log("No responder emails found.");
        return null;
      }

      // Firestore "in" query allows max 10 items
      const emailChunks = [];
      for (let i = 0; i < responderEmails.length; i += 10) {
        emailChunks.push(responderEmails.slice(i, i + 10));
      }

      const tokenSet = new Set();

      for (const chunk of emailChunks) {
        const tokenSnap = await admin
          .firestore()
          .collection("fcm_tokens")
          .where("email", "in", chunk)
          .get();

        tokenSnap.forEach((doc) => {
          const token = doc.data().token;
          if (token && typeof token === "string" && token.trim() !== "") {
            tokenSet.add(token.trim());
          }
        });
      }

      const tokens = Array.from(tokenSet);

      if (tokens.length === 0) {
        console.log("No valid FCM tokens found for:", responderEmails);
        return null;
      }

      const message = {
        tokens,
        notification: {
          title: "🚨 Dispatch Alert!",
          body: `You have been dispatched to: ${alertLocation}`,
        },
        data: {
          type: "dispatch",
          route: "dispatch",
          dispatchId: context.params.dispatchId,
          location: String(alertLocation),
          status: "Dispatched",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "high_importance_channel",
            sound: "default",
            priority: "max",
            defaultSound: true,
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);

      console.log("Notification sent.");
      console.log("Success count:", response.successCount);
      console.log("Failure count:", response.failureCount);

      // Remove invalid tokens
      const invalidTokens = [];

      response.responses.forEach((result, index) => {
        if (!result.success && result.error) {
          const code = result.error.code || "";
          console.log(`Failed token: ${tokens[index]} | Code: ${code}`);

          if (
            code === "messaging/invalid-registration-token" ||
            code === "messaging/registration-token-not-registered"
          ) {
            invalidTokens.push(tokens[index]);
          }
        }
      });

      if (invalidTokens.length > 0) {
        for (let i = 0; i < invalidTokens.length; i += 10) {
          const tokenChunk = invalidTokens.slice(i, i + 10);

          const badTokenSnap = await admin
            .firestore()
            .collection("fcm_tokens")
            .where("token", "in", tokenChunk)
            .get();

          const batch = admin.firestore().batch();
          badTokenSnap.forEach((doc) => batch.delete(doc.ref));
          await batch.commit();
        }

        console.log("Deleted invalid tokens:", invalidTokens.length);
      }

      return null;
    } catch (error) {
      console.error("sendDispatchNotification error:", error);
      return null;
    }
  });