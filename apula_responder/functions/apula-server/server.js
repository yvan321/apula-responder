import express from "express";
import nodemailer from "nodemailer";
import cors from "cors";
import admin from "firebase-admin";
import fs from "fs";
import dotenv from "dotenv";

dotenv.config(); // ✅ Load .env variables

const app = express();
app.use(express.json());
app.use(cors());

// ✅ Read Firebase service account from path in .env
const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!fs.existsSync(serviceAccountPath)) {
  console.error("❌ Firebase key file not found:", serviceAccountPath);
  process.exit(1);
}

const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));

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

    // 🔐 Gmail transporter using .env credentials
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: process.env.EMAIL_USER,
        pass: process.env.EMAIL_PASS,
      },
    });

    const mailOptions = {
      from: `"Apula Responder" <${process.env.EMAIL_USER}>`,
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
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});
