import express from "express";
import nodemailer from "nodemailer";
import cors from "cors";
import admin from "firebase-admin";
import fs from "fs";
import dotenv from "dotenv";

dotenv.config();
const app = express();
app.use(express.json());
app.use(cors({
  origin: "*", // 👈 or specific "http://localhost:5000"
  methods: ["GET", "POST"],
  allowedHeaders: ["Content-Type"],
}));

// Log requests (for debugging)
app.use((req, res, next) => {
  console.log(`[${req.method}] ${req.url}`, req.body);
  next();
});

// ✅ Firebase setup
const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!fs.existsSync(serviceAccountPath)) {
  console.error("❌ Firebase key file not found:", serviceAccountPath);
  process.exit(1);
}
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

// ✅ Send Verification Email API
app.post("/send-verification", async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: "Email is required." });

  try {
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const usersRef = admin.firestore().collection("users");
    const query = await usersRef.where("email", "==", email).limit(1).get();

    if (query.empty) {
      return res.status(404).json({ error: "User not found in Firestore." });
    }

    const userDoc = query.docs[0];
    await usersRef.doc(userDoc.id).update({ verificationCode: code });

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
    res.status(200).json({ success: true });
  } catch (error) {
    console.error("❌ Error sending verification:", error);
    res.status(500).json({ error: "Failed to send email." });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 Server running on http://localhost:${PORT}`));
