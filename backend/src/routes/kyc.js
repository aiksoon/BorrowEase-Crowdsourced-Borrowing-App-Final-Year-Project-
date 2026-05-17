const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

function isAdmin(req) {
  const admins = typeof pool.getConfiguredAdminEmails === 'function'
    ? pool.getConfiguredAdminEmails()
    : [];
  return admins.includes((req.user.email || '').toLowerCase());
}

router.get('/', auth, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT id, email, name, phone, kyc_status, kyc_note,
              kyc_doc_type, kyc_id_image_url, kyc_selfie_image_url
       FROM users WHERE id = ? LIMIT 1`,
      [req.user.id]
    );
    if (!rows.length) return res.status(404).json({ message: 'User not found' });
    if (!rows[0].kyc_status) {
      rows[0].kyc_status = 'unverified';
    }
    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch KYC info', error: err.message });
  }
});

router.get('/pending', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });
  try {
    const [rows] = await pool.execute(
      `SELECT id, email, name, phone, avatar_url, kyc_status,
              kyc_doc_type, kyc_id_image_url, kyc_selfie_image_url
       FROM users
       WHERE kyc_status = 'pending'
       ORDER BY id DESC`
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch pending KYC users', error: err.message });
  }
});

router.get('/:userId', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });
  const { userId } = req.params;
  try {
    const [rows] = await pool.execute(
      `SELECT id, email, name, phone, avatar_url, kyc_status, kyc_note,
              kyc_doc_type, kyc_id_image_url, kyc_selfie_image_url
       FROM users WHERE id = ? LIMIT 1`,
      [userId]
    );
    if (!rows.length) {
      return res.status(404).json({ message: 'User not found' });
    }
    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch user KYC', error: err.message });
  }
});

router.post('/submit', auth, async (req, res) => {
  const { kyc_note, kyc_doc_type, kyc_id_image_url, kyc_selfie_image_url } = req.body || {};
  const docType = (kyc_doc_type || '').toString().trim();
  const idImageUrl = (kyc_id_image_url || '').toString().trim();
  const selfieImageUrl = (kyc_selfie_image_url || '').toString().trim();

  if (!idImageUrl || !selfieImageUrl) {
    return res.status(400).json({ message: 'Both ID image and selfie image are required' });
  }
  if (!docType) {
    return res.status(400).json({ message: 'Document type is required' });
  }

  try {
    await pool.execute(
      `UPDATE users
       SET kyc_note = ?,
           kyc_doc_type = ?,
           kyc_id_image_url = ?,
           kyc_selfie_image_url = ?,
           kyc_status = ?
       WHERE id = ?`,
      [kyc_note || null, docType, idImageUrl, selfieImageUrl, 'pending', req.user.id]
    );
    return res.json({
      id: req.user.id,
      kyc_status: 'pending',
      kyc_doc_type: docType,
      kyc_id_image_url: idImageUrl,
      kyc_selfie_image_url: selfieImageUrl,
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to submit KYC', error: err.message });
  }
});

router.patch('/:userId/status', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });
  const { userId } = req.params;
  const { status, note } = req.body;
  if (!['unverified', 'pending', 'verified', 'rejected'].includes(status)) {
    return res.status(400).json({ message: 'Invalid status' });
  }
  const id = Number(userId);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ message: 'Invalid userId' });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [rows] = await conn.execute(
      'SELECT id, kyc_status FROM users WHERE id = ? LIMIT 1 FOR UPDATE',
      [id]
    );
    if (!rows.length) {
      await conn.rollback();
      return res.status(404).json({ message: 'User not found' });
    }

    const previousStatus = (rows[0].kyc_status || '').toString().toLowerCase();

    await conn.execute(
      'UPDATE users SET kyc_status = ?, kyc_note = ? WHERE id = ?',
      [status, note || null, id]
    );

    if (status === 'verified' && previousStatus !== 'verified') {
      const title = 'KYC Verification Approved';
      const message = 'Your KYC verification has been approved. Your account is now verified.';
      const payload = JSON.stringify({
        event: 'kyc_verified',
        kyc_status: 'verified',
      });

      await conn.execute(
        `INSERT INTO system_notifications (user_id, category, title, message, action, payload_json)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [id, 'kyc', title, message, 'kyc', payload]
      );
    }

    await conn.commit();
    return res.json({ id, kyc_status: status });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: 'Failed to update KYC status', error: err.message });
  } finally {
    conn.release();
  }
});

module.exports = router;
