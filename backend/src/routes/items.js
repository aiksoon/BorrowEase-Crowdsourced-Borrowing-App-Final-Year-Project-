const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const { q, category, owner_id, available_only, limit = 50, offset = 0 } = req.query;
    const clauses = [];
    const params = [];
    if (q) {
      clauses.push('(items.title LIKE ? OR items.description LIKE ? OR items.location_text LIKE ?)');
      const like = `%${q}%`;
      params.push(like, like, like);
    }
    if (category) {
      clauses.push('items.category = ?');
      params.push(category);
    }
    if (owner_id) {
      clauses.push('items.owner_id = ?');
      params.push(owner_id);
    }
    if (available_only === 'true') {
      clauses.push("items.availability = 'available'");
    } else if (available_only !== 'false') {
      // Default behavior for public browsing: only show available items.
      // Owner dashboards can opt out by sending available_only=false.
      clauses.push("items.availability = 'available'");
    }

    const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
    const sql = `SELECT items.*, users.name AS owner_name, users.avatar_url AS owner_avatar_url,
                   (SELECT COALESCE(ROUND(AVG(rating), 1), 5.0) FROM reviews WHERE reviewee_id = items.owner_id) AS rating
                 FROM items JOIN users ON items.owner_id = users.id
                 ${where}
                 ORDER BY items.created_at DESC
                 LIMIT ? OFFSET ?`;
    params.push(Number(limit), Number(offset));
    const [rows] = await pool.execute(sql, params);
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to list items', error: err.message });
  }
});

router.post('/', auth, async (req, res) => {
  const {
    title,
    description,
    category,
    price_per_day,
    deposit_amount,
    location_text,
    image_url,
    video_url,
    latitude,
    longitude,
  } = req.body;
  if (!title || price_per_day === undefined) {
    return res.status(400).json({ message: 'title and price_per_day are required' });
  }
  if (!image_url || !String(image_url).trim()) {
    return res.status(400).json({ message: 'image_url is required' });
  }
  try {
    const [result] = await pool.execute(
      `INSERT INTO items (owner_id, title, description, category, price_per_day, deposit_amount, location_text, image_url, video_url, latitude, longitude)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)` ,
      [
        req.user.id,
        title,
        description || null,
        category || null,
        price_per_day,
        deposit_amount || 0,
        location_text || null,
        String(image_url).trim(),
        video_url ? String(video_url).trim() : null,
        latitude || null,
        longitude || null,
      ]
    );
    return res.status(201).json({ id: result.insertId });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to create item', error: err.message });
  }
});

router.get('/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await pool.execute(
      `SELECT items.*, users.name AS owner_name, users.avatar_url AS owner_avatar_url,
         (SELECT COALESCE(ROUND(AVG(rating), 1), 5.0) FROM reviews WHERE reviewee_id = items.owner_id) AS rating
       FROM items JOIN users ON items.owner_id = users.id WHERE items.id = ? LIMIT 1`,
      [id]
    );
    if (!rows.length) return res.status(404).json({ message: 'Item not found' });
    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to get item', error: err.message });
  }
});

router.patch('/:id', auth, async (req, res) => {
  const { id } = req.params;
  const {
    title,
    description,
    category,
    price_per_day,
    deposit_amount,
    location_text,
    image_url,
    video_url,
    latitude,
    longitude,
    availability,
  } = req.body;
  try {
    const [rows] = await pool.execute('SELECT owner_id FROM items WHERE id = ?', [id]);
    if (!rows.length) return res.status(404).json({ message: 'Item not found' });
    if (rows[0].owner_id !== req.user.id) return res.status(403).json({ message: 'Not item owner' });

    const fields = [];
    const params = [];
    if (title !== undefined) { fields.push('title = ?'); params.push(title); }
    if (description !== undefined) { fields.push('description = ?'); params.push(description); }
    if (category !== undefined) { fields.push('category = ?'); params.push(category); }
    if (price_per_day !== undefined) { fields.push('price_per_day = ?'); params.push(price_per_day); }
    if (deposit_amount !== undefined) { fields.push('deposit_amount = ?'); params.push(deposit_amount); }
    if (location_text !== undefined) { fields.push('location_text = ?'); params.push(location_text); }
    if (image_url !== undefined) { fields.push('image_url = ?'); params.push(image_url); }
    if (video_url !== undefined) { fields.push('video_url = ?'); params.push(video_url); }
    if (latitude !== undefined) { fields.push('latitude = ?'); params.push(latitude); }
    if (longitude !== undefined) { fields.push('longitude = ?'); params.push(longitude); }
    if (availability !== undefined) { fields.push('availability = ?'); params.push(availability); }

    if (!fields.length) return res.status(400).json({ message: 'No fields to update' });

    params.push(id);
    await pool.execute(`UPDATE items SET ${fields.join(', ')} WHERE id = ?`, params);
    return res.json({ id, updated: true });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to update item', error: err.message });
  }
});

router.delete('/:id', auth, async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await pool.execute('SELECT owner_id FROM items WHERE id = ?', [id]);
    if (!rows.length) return res.status(404).json({ message: 'Item not found' });
    if (rows[0].owner_id !== req.user.id) return res.status(403).json({ message: 'Not item owner' });

    await pool.execute('DELETE FROM items WHERE id = ?', [id]);
    return res.json({ id, deleted: true });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to delete item', error: err.message });
  }
});

module.exports = router;
