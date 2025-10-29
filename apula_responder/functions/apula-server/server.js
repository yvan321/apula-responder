import express from "express";
import nodemailer from "nodemailer";
import cors from "cors";
import admin from "firebase-admin";
import fs from "fs";

const app = express();
app.use(express.json());
app.use(cors());

// ✅ Read service account JSON manually (works in Node 22+)
const serviceAccount = JSON.parse(fs.readFileSync("./serviceAccountKey.json", "utf8"));

// 🔥 Initialize Firebase Admin SDK
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

// ✅ Send verification email route
app.post("/send-verification", async (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.status(400).json({ error: "Email is required." });
  }

  try {
    // Generate a 6-digit random code
    const code = Math.floor(100000 + Math.random() * 900000).toString();

    // 🔍 Find user by email
    const usersRef = admin.firestore().collection("users");
    const query = await usersRef.where("email", "==", email).limit(1).get();

    if (query.empty) {
      return res.status(404).json({ error: "User not found." });
    }

    const userDoc = query.docs[0];
    await usersRef.doc(userDoc.id).update({ verificationCode: code });

    // 🔐 Gmail transporter (App Password required)
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: "alexanderthegreat09071107@gmail.com",
        pass: "amnwssmjqyexxnfu", // ⚠️ Make sure this is your Gmail App Password
      },
    });

    const mailOptions = {
      from: '"Apula Responder" <alexanderthegreat09071107@gmail.com>',
      to: email,
      subject: "Your Verification Code",
      html: `
        <div style="font-family: Arial, sans-serif; text-align: center;">
          <h2>Verification Code</h2>
          <p>Your verification code is:</p>
          <h1 style="color: #A30000;">${code}</h1>
          <p>Enter this code in the app to verify your account.</p>
        </div>
      `,
    };

    await transporter.sendMail(mailOptions);

    console.log(`✅ Email sent to ${email} with code ${code}`);
    res.status(200).json({ success: true, code });
  } catch (error) {
    console.error("❌ Failed to send email:", error);
    res.status(500).json({ error: "Failed to send verification email." });
  }
});

// ✅ Start server
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});
