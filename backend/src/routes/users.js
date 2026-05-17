const express = require('express');
const router = express.Router();
const pool = require('../config/db');
const auth = require('../middleware/auth');

function parsePayload(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

router.get('/me/system-notifications', auth, async (req, res) => {
  try {
    const limitRaw = Number(req.query?.limit);
    const limit = Number.isInteger(limitRaw)
      ? Math.min(Math.max(limitRaw, 1), 200)
      : 80;

    const [rows] = await pool.execute(
      `SELECT id, category, title, message, action, payload_json, created_at
       FROM system_notifications
       WHERE user_id = ?
       ORDER BY created_at DESC, id DESC
       LIMIT ?`,
      [req.user.id, limit]
    );

    return res.json(
      rows.map((row) => ({
        id: row.id,
        category: row.category,
        title: row.title,
        message: row.message,
        action: row.action,
        payload: parsePayload(row.payload_json),
        created_at: row.created_at,
      }))
    );
  } catch (error) {
    return res.status(500).json({ message: 'Failed to fetch notifications', error: error.message });
  }
});

router.get('/:id/profile', async (req, res) => {
  try {
    const userId = Number(req.params.id);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ message: 'Invalid user id' });
    }

    // Get user details
    const [userRows] = await pool.execute(
      `SELECT id, name, avatar_url, kyc_status
       FROM users WHERE id = ?`,
      [userId]
    );

    if (userRows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }
    const user = userRows[0];

    // Get items lent count (items owned by this user)
    const [itemsRows] = await pool.execute(
      'SELECT COUNT(*) AS count FROM items WHERE owner_id = ?',
      [userId]
    );
    const itemsLentCount = Number(itemsRows[0].count || 0);

    // Get completed transactions count where user participated as owner or borrower.
    const [transRows] = await pool.execute(
      `SELECT COUNT(DISTINCT br.id) AS count 
       FROM borrow_requests br
       WHERE br.status = 'completed'
         AND (br.owner_id = ? OR br.borrower_id = ?)`,
      [userId, userId]
    );
    const transactionsCount = Number(transRows[0].count || 0);

    // Get items borrowed count (borrow requests made by this user that reached active/completed lifecycle)
    const [borrowedRows] = await pool.execute(
      `SELECT COUNT(*) AS count
       FROM borrow_requests br
       WHERE br.borrower_id = ?
         AND br.status IN ('accepted', 'handover', 'in_use', 'return_pending', 'completed')`,
      [userId]
    );
    const borrowedCount = Number(borrowedRows[0].count || 0);

    // Get average rating
    const [reviewRows] = await pool.execute(
      `SELECT ROUND(AVG(rating), 1) AS avgRating, COUNT(*) AS reviewCount
       FROM reviews WHERE reviewee_id = ?`,
      [userId]
    );
    const reviewCount = Number(reviewRows[0].reviewCount || 0);
    const rating =
      reviewRows[0].avgRating === null ? 5.0 : Number(reviewRows[0].avgRating);

    // Get the latest reviews (up to 5)
    const [reviews] = await pool.execute(
        `SELECT r.id, r.rating, r.comment, r.created_at,
                u.id AS reviewer_id,
                u.name AS reviewer_name,
                u.avatar_url AS reviewer_avatar,
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
         ORDER BY r.created_at DESC LIMIT 5`,
        [userId]
    );

    res.json({
      id: user.id,
      name: user.name,
      avatar_url: user.avatar_url,
      kyc_status: user.kyc_status,
      stats: {
        itemsLent: itemsLentCount,
        borrowed: borrowedCount,
        itemsBorrowed: borrowedCount,
        transactions: transactionsCount,
        rating: rating,
        reviewCount: reviewCount
      },
      reviews
    });

  } catch (error) {
    console.error('Error fetching user profile:', error);
    res.status(500).json({ message: 'Server error retrieving profile' });
  }
});

module.exports = router;