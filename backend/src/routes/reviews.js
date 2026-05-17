const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

router.post('/', auth, async (req, res) => {
  const { request_id, reviewee_id, rating, comment } = req.body;
  if (!request_id || !reviewee_id || rating === undefined) {
    return res.status(400).json({ message: 'request_id, reviewee_id, rating are required' });
  }
  if (rating < 1 || rating > 5) return res.status(400).json({ message: 'rating must be between 1 and 5' });
  try {
    const [requests] = await pool.execute(
      'SELECT borrower_id, owner_id, status FROM borrow_requests WHERE id = ? LIMIT 1',
      [request_id]
    );
    if (!requests.length) return res.status(404).json({ message: 'Request not found' });
    const reqRow = requests[0];
    if (![reqRow.borrower_id, reqRow.owner_id].includes(req.user.id)) {
      return res.status(403).json({ message: 'Not part of this request' });
    }
    if (![reqRow.borrower_id, reqRow.owner_id].includes(reviewee_id)) {
      return res.status(400).json({ message: 'Reviewee must be borrower or owner' });
    }
    if (reviewee_id === req.user.id) return res.status(400).json({ message: 'Cannot review yourself' });
    if (reqRow.status !== 'completed') {
      return res.status(400).json({ message: 'Request must be completed before reviewing' });
    }

    const [result] = await pool.execute(
      'INSERT INTO reviews (request_id, reviewer_id, reviewee_id, rating, comment) VALUES (?, ?, ?, ?, ?)',
      [request_id, req.user.id, reviewee_id, rating, comment || null]
    );
    return res.status(201).json({ id: result.insertId });
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ message: 'Review already submitted for this order' });
    }
    return res.status(500).json({ message: 'Failed to create review', error: err.message });
  }
});

router.get('/', auth, async (req, res) => {
  const targetId = req.query.user_id || req.user.id;
  try {
    const [rows] = await pool.execute(
      `SELECT r.*, u.name AS reviewer_name, u.avatar_url AS reviewer_avatar,
              COALESCE(i.title, CONCAT('Request #', r.request_id)) AS item_title,
              CASE
                WHEN r.reviewer_id = br.borrower_id THEN 'borrower'
                WHEN r.reviewer_id = br.owner_id THEN 'lender'
                ELSE 'user'
              END AS reviewer_role
       FROM reviews r
       JOIN users u ON r.reviewer_id = u.id
       LEFT JOIN borrow_requests br ON br.id = r.request_id
       LEFT JOIN items i ON i.id = br.item_id
       WHERE r.reviewee_id = ?
       ORDER BY r.created_at DESC`,
      [targetId]
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch reviews', error: err.message });
  }
});

module.exports = router;
