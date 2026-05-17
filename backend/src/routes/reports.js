const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

function normalizeMediaUrls(input) {
  if (!Array.isArray(input)) return [];
  const normalized = input
    .map((u) => (u ?? '').toString().trim())
    .filter((u) => u.length > 0);
  return Array.from(new Set(normalized));
}

router.post('/', auth, async (req, res) => {
  const {
    request_id,
    reason_category,
    description,
    media_urls,
    target_type,
    target_id,
    reason,
  } = req.body;

  const requestId = Number(request_id || target_id || 0);
  const hasRequest = Number.isInteger(requestId) && requestId > 0;
  const category = (reason_category || 'Other').toString().trim();
  const fullDescription = (description || reason || '').toString().trim();
  const media = normalizeMediaUrls(media_urls);

  if (!hasRequest) {
    return res.status(400).json({ message: 'request_id is required' });
  }
  if (!fullDescription) {
    return res.status(400).json({ message: 'description is required' });
  }

  try {
    const [requestRows] = await pool.execute(
      'SELECT borrower_id, owner_id FROM borrow_requests WHERE id = ? LIMIT 1',
      [requestId]
    );
    if (!requestRows.length) {
      return res.status(404).json({ message: 'Request not found' });
    }
    const requestRow = requestRows[0];
    if (![requestRow.borrower_id, requestRow.owner_id].includes(req.user.id)) {
      return res.status(403).json({ message: 'You are not part of this order' });
    }

    const [existingRows] = await pool.execute(
      `SELECT id
       FROM reports
       WHERE reporter_id = ?
         AND COALESCE(request_id, target_id) = ?
       LIMIT 1`,
      [req.user.id, requestId]
    );
    if (existingRows.length) {
      return res.status(409).json({ message: 'You have already submitted a report for this order' });
    }

    const reasonSummary = fullDescription.slice(0, 500);
    const [result] = await pool.execute(
      `INSERT INTO reports (
         reporter_id,
         target_type,
         target_id,
         request_id,
         reason,
         reason_category,
         description,
         media_urls
       ) VALUES (?, 'request', ?, ?, ?, ?, ?, ?)`,
      [
        req.user.id,
        requestId,
        requestId,
        reasonSummary,
        category,
        fullDescription,
        media.length ? JSON.stringify(media) : null,
      ]
    );
    return res.status(201).json({ id: result.insertId });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to submit report', error: err.message });
  }
});

router.get('/', auth, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT r.*,
              br.item_id,
              i.title AS item_title,
              rep.name AS reporter_name,
              IF(r.reporter_id = br.borrower_id, owner.name, borrower.name) AS reported_user_name
       FROM reports r
       LEFT JOIN borrow_requests br ON br.id = COALESCE(r.request_id, r.target_id)
       LEFT JOIN items i ON i.id = br.item_id
       LEFT JOIN users rep ON rep.id = r.reporter_id
       LEFT JOIN users borrower ON borrower.id = br.borrower_id
       LEFT JOIN users owner ON owner.id = br.owner_id
       WHERE r.reporter_id = ?
       ORDER BY r.created_at DESC`,
      [req.user.id]
    );
    const normalized = rows.map((row) => {
      let mediaUrls = [];
      try {
        mediaUrls = row.media_urls ? JSON.parse(row.media_urls) : [];
      } catch (_) {
        mediaUrls = [];
      }
      return {
        ...row,
        media_urls: Array.isArray(mediaUrls) ? mediaUrls : [],
      };
    });
    return res.json(normalized);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch reports', error: err.message });
  }
});

module.exports = router;
