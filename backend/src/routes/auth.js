const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('../config/db');
const auth = require('../middleware/auth');
const { sendOtpEmail } = require('../config/email');

const router = express.Router();
const OTP_TTL_MS = 15 * 60 * 1000; // 15 minutes
const strongPassword = (pwd) =>
  typeof pwd === 'string' &&
  pwd.length >= 8 &&
  /[A-Z]/.test(pwd) &&
  /[a-z]/.test(pwd) &&
  /[0-9]/.test(pwd) &&
  /[!@#$%^&*]/.test(pwd);

router.get('/me', auth, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT id, email, name, phone, location, avatar_url, kyc_status,
              is_banned, payout_bank_name, payout_account_holder, payout_account_number
       FROM users WHERE id = ? LIMIT 1`,
      [req.user.id]
    );
    if (!rows.length) return res.status(404).json({ message: 'User not found' });
    return res.json({ user: rows[0] });
  } catch (err) {
    return res.status(500).json({ message: 'Could not fetch profile', error: err.message });
  }
});

router.post('/register', async (req, res) => {
  const { email, password, name, phone, location } = req.body;
  const normalizedEmail = (email || '').toString().trim().toLowerCase();
  const normalizedName = (name || '').toString().trim();
  const normalizedNameLower = normalizedName.toLowerCase();
  const normalizedPhoneRaw = (phone ?? '').toString().trim();
  const normalizedPhone = normalizedPhoneRaw.length === 0 ? null : normalizedPhoneRaw;

  if (!normalizedEmail || !password || !normalizedName) {
    return res.status(400).json({ message: 'email, password, name are required' });
  }
  if (normalizedPhone && !/^[0-9]+$/.test(normalizedPhone)) {
    return res.status(400).json({ code: 'PHONE_INVALID', message: 'Phone must contain numbers only' });
  }

  const adminEmails = (process.env.ADMIN_EMAILS || '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const defaultAdminEmail = (process.env.DEFAULT_ADMIN_EMAIL || 'admin@crowdborrow.local').trim().toLowerCase();
  const defaultAdminUsername = (process.env.DEFAULT_ADMIN_USERNAME || 'admin').trim().toLowerCase();
  if (defaultAdminEmail && !adminEmails.includes(defaultAdminEmail)) {
    adminEmails.push(defaultAdminEmail);
  }
  if (adminEmails.includes(normalizedEmail) || normalizedNameLower === defaultAdminUsername) {
    return res.status(403).json({
      code: 'RESERVED_ACCOUNT',
      message: 'This account identity is reserved by the system',
    });
  }

  try {
    const [existingEmail] = await pool.execute('SELECT id FROM users WHERE email = ? LIMIT 1', [normalizedEmail]);
    if (existingEmail.length) {
      return res.status(409).json({ code: 'EMAIL_EXISTS', message: 'Email already registered' });
    }

    const [existingName] = await pool.execute('SELECT id FROM users WHERE name = ? LIMIT 1', [normalizedName]);
    if (existingName.length) {
      return res.status(409).json({ code: 'USERNAME_EXISTS', message: 'Username already taken' });
    }

    const hash = await bcrypt.hash(password, 10);
    const [result] = await pool.execute(
      'INSERT INTO users (email, password_hash, name, phone, location, kyc_status) VALUES (?, ?, ?, ?, ?, ?)',
      [normalizedEmail, hash, normalizedName, normalizedPhone, location || null, 'unverified']
    );

    const token = jwt.sign({ id: result.insertId, email: normalizedEmail }, process.env.JWT_SECRET, { expiresIn: '7d' });
    return res.status(201).json({
      token,
      user: {
        id: result.insertId,
        email: normalizedEmail,
        name: normalizedName,
        phone: normalizedPhone,
        location: location || null,
        avatar_url: null,
        kyc_status: 'unverified',
      },
    });
  } catch (err) {
    return res.status(500).json({ message: 'Registration failed', error: err.message });
  }
});

router.post('/login', async (req, res) => {
  // email 字段可填邮箱或用户名
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ message: 'email (or username) and password are required' });
  try {
    const identifier = email;
    const [rows] = await pool.execute(
      `SELECT id, email, password_hash, name, phone, location, avatar_url, kyc_status,
              is_banned, payout_bank_name, payout_account_holder, payout_account_number
       FROM users WHERE email = ? OR name = ? LIMIT 1`,
      [identifier, identifier]
    );
    if (!rows.length) return res.status(401).json({ message: 'Invalid credentials' });
    const user = rows[0];
    if (Number(user.is_banned || 0) === 1) {
      return res.status(403).json({ message: 'Account is banned' });
    }
    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) return res.status(401).json({ message: 'Invalid credentials' });

    const token = jwt.sign({ id: user.id, email: user.email }, process.env.JWT_SECRET, { expiresIn: '7d' });
    return res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phone: user.phone,
        location: user.location,
        avatar_url: user.avatar_url,
        kyc_status: user.kyc_status,
        is_banned: Number(user.is_banned || 0) === 1,
        payout_bank_name: user.payout_bank_name,
        payout_account_holder: user.payout_account_holder,
        payout_account_number: user.payout_account_number,
      },
    });
  } catch (err) {
    return res.status(500).json({ message: 'Login failed', error: err.message });
  }
});

router.patch('/me', auth, async (req, res) => {
  const body = req.body || {};
  const hasName = Object.prototype.hasOwnProperty.call(body, 'name');
  const hasEmail = Object.prototype.hasOwnProperty.call(body, 'email');
  if (hasName || hasEmail) {
    return res.status(400).json({ message: 'name and email cannot be changed' });
  }

  const hasPhone = Object.prototype.hasOwnProperty.call(body, 'phone');
  const hasLocation = Object.prototype.hasOwnProperty.call(body, 'location');
  const hasAvatar = Object.prototype.hasOwnProperty.call(body, 'avatar_url');
  const hasPayoutBank = Object.prototype.hasOwnProperty.call(body, 'payout_bank_name');
  const hasPayoutHolder = Object.prototype.hasOwnProperty.call(body, 'payout_account_holder');
  const hasPayoutAccount = Object.prototype.hasOwnProperty.call(body, 'payout_account_number');

  if (
    !hasPhone &&
    !hasLocation &&
    !hasAvatar &&
    !hasPayoutBank &&
    !hasPayoutHolder &&
    !hasPayoutAccount
  ) {
    return res.status(400).json({ message: 'No updatable fields provided' });
  }

  const fields = [];
  const params = [];

  if (hasPhone) {
    const raw = (body.phone ?? '').toString().trim();
    const normalizedPhone = raw.length === 0 ? null : raw;
    if (normalizedPhone && !/^[0-9]+$/.test(normalizedPhone)) {
      return res.status(400).json({ message: 'Phone must contain numbers only' });
    }
    fields.push('phone = ?');
    params.push(normalizedPhone);
  }

  if (hasLocation) {
    const location = (body.location ?? '').toString().trim();
    fields.push('location = ?');
    params.push(location.length === 0 ? null : location);
  }

  if (hasAvatar) {
    const avatar = (body.avatar_url ?? '').toString().trim();
    fields.push('avatar_url = ?');
    params.push(avatar.length === 0 ? null : avatar);
  }

  if (hasPayoutBank || hasPayoutHolder || hasPayoutAccount) {
    const payoutBank = (body.payout_bank_name ?? '').toString().trim();
    const payoutHolder = (body.payout_account_holder ?? '').toString().trim();
    const payoutAccount = (body.payout_account_number ?? '').toString().trim();

    const hasAnyPayoutValue =
      payoutBank.length > 0 || payoutHolder.length > 0 || payoutAccount.length > 0;

    if (hasAnyPayoutValue) {
      if (!payoutBank || !payoutHolder || !payoutAccount) {
        return res.status(400).json({
          message: 'payout_bank_name, payout_account_holder, and payout_account_number are required together',
        });
      }
      if (!/^[0-9]{6,25}$/.test(payoutAccount)) {
        return res.status(400).json({ message: 'Invalid payout account number format' });
      }
    }

    fields.push('payout_bank_name = ?');
    params.push(payoutBank.length === 0 ? null : payoutBank);
    fields.push('payout_account_holder = ?');
    params.push(payoutHolder.length === 0 ? null : payoutHolder);
    fields.push('payout_account_number = ?');
    params.push(payoutAccount.length === 0 ? null : payoutAccount);
  }

  try {
    params.push(req.user.id);
    await pool.execute(`UPDATE users SET ${fields.join(', ')} WHERE id = ?`, params);
    const [rows] = await pool.execute(
      `SELECT id, email, name, phone, location, avatar_url, kyc_status,
              is_banned, payout_bank_name, payout_account_holder, payout_account_number
       FROM users WHERE id = ? LIMIT 1`,
      [req.user.id]
    );
    if (!rows.length) return res.status(404).json({ message: 'User not found' });
    return res.json({ user: rows[0] });
  } catch (err) {
    return res.status(500).json({ message: 'Could not update profile', error: err.message });
  }
});

router.post('/change-password', auth, async (req, res) => {
  const { current_password: currentPassword, new_password: newPassword } = req.body || {};
  if (!currentPassword || !newPassword) {
    return res.status(400).json({ message: 'current_password and new_password are required' });
  }
  if (!strongPassword(newPassword)) {
    return res.status(400).json({ message: 'Password must be 8+ chars with A-Z, a-z, 0-9, and !@#$%^&*' });
  }

  try {
    const [rows] = await pool.execute(
      'SELECT id, password_hash FROM users WHERE id = ? LIMIT 1',
      [req.user.id]
    );
    if (!rows.length) {
      return res.status(404).json({ message: 'User not found' });
    }

    const ok = await bcrypt.compare(currentPassword, rows[0].password_hash);
    if (!ok) {
      return res.status(400).json({ message: 'Current password is incorrect' });
    }

    const hash = await bcrypt.hash(newPassword, 10);
    await pool.execute('UPDATE users SET password_hash = ? WHERE id = ?', [hash, req.user.id]);
    return res.json({ message: 'Password updated' });
  } catch (err) {
    return res.status(500).json({ message: 'Could not change password', error: err.message });
  }
});

// Request password reset: generate OTP and email it
router.post('/forgot', async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ message: 'email is required' });

  try {
    const [users] = await pool.execute('SELECT id FROM users WHERE email = ? LIMIT 1', [email]);
    if (!users.length) {
      return res.json({ message: 'If the account exists, a code has been sent' });
    }

    const user = users[0];
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const expires = new Date(Date.now() + OTP_TTL_MS);

    await pool.execute('UPDATE users SET reset_otp = ?, reset_otp_expires = ? WHERE id = ?', [otp, expires, user.id]);

    try {
      await sendOtpEmail(email, otp);
    } catch (err) {
      console.error('Failed to send OTP email:', err.message);
      return res.status(500).json({ message: 'Failed to send email' });
    }

    return res.json({ message: 'If the account exists, a code has been sent' });
  } catch (err) {
    return res.status(500).json({ message: 'Could not process reset request', error: err.message });
  }
});

// Verify OTP and set new password
router.post('/reset-password', async (req, res) => {
  const { email, otp, new_password: newPassword } = req.body;
  if (!email || !otp || !newPassword) {
    return res.status(400).json({ message: 'email, otp, and new_password are required' });
  }

  if (!strongPassword(newPassword)) {
    return res.status(400).json({ message: 'Password must be 8+ chars with A-Z, a-z, 0-9, and !@#$%^&*' });
  }

  try {
    const [users] = await pool.execute(
      'SELECT id, reset_otp, reset_otp_expires FROM users WHERE email = ? LIMIT 1',
      [email]
    );

    if (!users.length) {
      return res.status(400).json({ message: 'Invalid code or expired' });
    }

    const user = users[0];
    if (!user.reset_otp || !user.reset_otp_expires) {
      return res.status(400).json({ message: 'Invalid code or expired' });
    }

    const expires = new Date(user.reset_otp_expires);
    if (user.reset_otp !== otp || expires.getTime() < Date.now()) {
      return res.status(400).json({ message: 'Invalid code or expired' });
    }

    const hash = await bcrypt.hash(newPassword, 10);
    await pool.execute(
      'UPDATE users SET password_hash = ?, reset_otp = NULL, reset_otp_expires = NULL WHERE id = ?',
      [hash, user.id]
    );

    return res.json({ message: 'Password reset successful' });
  } catch (err) {
    return res.status(500).json({ message: 'Could not reset password', error: err.message });
  }
});

module.exports = router;
