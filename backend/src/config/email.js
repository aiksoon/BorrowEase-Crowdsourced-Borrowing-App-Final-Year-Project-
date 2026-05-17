const nodemailer = require('nodemailer');

const user = process.env.GMAIL_USER;
const appPassword = process.env.GMAIL_APP_PASSWORD;

if (!user || !appPassword) {
  console.warn('GMAIL_USER or GMAIL_APP_PASSWORD is not set. OTP emails will fail until configured.');
}

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user,
    pass: appPassword,
  },
});

async function sendOtpEmail(targetEmail, otp) {
  if (!user || !appPassword) {
    throw new Error('Email sender is not configured');
  }

  const mailOptions = {
    from: `BorrowEase <${user}>`,
    to: targetEmail,
    subject: 'Password Reset Verification Code',
    text: `Your verification code is: ${otp}. It will expire in 15 minutes.`,
  };

  await transporter.sendMail(mailOptions);
}

module.exports = { sendOtpEmail };
