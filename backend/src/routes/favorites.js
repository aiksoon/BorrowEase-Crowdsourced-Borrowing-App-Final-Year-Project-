const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

// List current user's favourites with item details
router.get('/', auth, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT f.item_id AS id,
              i.title,
              i.description,
              i.category,
              i.price_per_day,
              i.location_text,
              i.image_url,
              i.video_url,
              i.owner_id,
              u.name AS owner_name,
              COALESCE(rr.rating, 5.0) AS rating,
              COALESCE(rr.review_count, 0) AS review_count,
              i.availability,
              i.updated_at,
              i.created_at
       FROM favourites f
       JOIN items i ON f.item_id = i.id
       JOIN users u ON i.owner_id = u.id
       LEFT JOIN (
         SELECT
           reviewee_id,
           ROUND(AVG(rating), 1) AS rating,
           COUNT(*) AS review_count
         FROM reviews
         GROUP BY reviewee_id
       ) rr ON rr.reviewee_id = i.owner_id
       WHERE f.user_id = ?
         AND (i.availability = 'available' OR i.owner_id = ?)
       ORDER BY f.created_at DESC`,
      [req.user.id, req.user.id]
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to load favourites', error: err.message });
  }
});

// Add to favourites
router.post('/', auth, async (req, res) => {
  const { item_id } = req.body;
  if (!item_id) return res.status(400).json({ message: 'item_id is required' });
  try {
    const [items] = await pool.execute('SELECT id FROM items WHERE id = ? LIMIT 1', [item_id]);
    if (!items.length) return res.status(404).json({ message: 'Item not found' });

    await pool.execute(
      'INSERT IGNORE INTO favourites (user_id, item_id) VALUES (?, ?)',
      [req.user.id, item_id]
    );
    return res.status(201).json({ item_id });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to add favourite', error: err.message });
  }
});

// Remove from favourites
router.delete('/:itemId', auth, async (req, res) => {
  const { itemId } = req.params;
  try {
    await pool.execute('DELETE FROM favourites WHERE user_id = ? AND item_id = ? LIMIT 1', [req.user.id, itemId]);
    return res.json({ item_id: Number(itemId), removed: true });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to remove favourite', error: err.message });
  }
});

module.exports = router;
