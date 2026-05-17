const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

router.get('/posts', auth, async (req, res) => {
  const nearby = String(req.query.nearby || '').toLowerCase() === 'true';

  try {
    let viewerLocation = null;
    if (nearby) {
      const [viewerRows] = await pool.execute(
        'SELECT location FROM users WHERE id = ? LIMIT 1',
        [req.user.id]
      );
      viewerLocation = (viewerRows[0]?.location || '').toString().trim();
      if (!viewerLocation) {
        return res.json([]);
      }
    }

    const sql = `
      SELECT
        cp.id,
        cp.user_id,
        cp.content,
        cp.image_url,
        cp.created_at,
        cp.updated_at,
        u.name AS owner_name,
        u.avatar_url AS owner_avatar_url,
        u.location AS owner_location
      FROM community_posts cp
      JOIN users u ON cp.user_id = u.id
      ${nearby ? 'WHERE LOWER(TRIM(u.location)) = LOWER(TRIM(?))' : ''}
      ORDER BY cp.created_at DESC
      LIMIT 200
    `;

    const params = nearby ? [viewerLocation] : [];
    const [rows] = await pool.execute(sql, params);
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to load posts', error: err.message });
  }
});

router.post('/posts', auth, async (req, res) => {
  const content = (req.body.content || '').toString().trim();
  const imageUrlRaw = (req.body.image_url ?? '').toString().trim();
  const imageUrl = imageUrlRaw.isEmpty ? null : imageUrlRaw;

  if (!content) {
    return res.status(400).json({ message: 'content is required' });
  }
  if (content.length > 2000) {
    return res.status(400).json({ message: 'content must be at most 2000 characters' });
  }

  try {
    const [result] = await pool.execute(
      'INSERT INTO community_posts (user_id, content, image_url) VALUES (?, ?, ?)',
      [req.user.id, content, imageUrl]
    );
    return res.status(201).json({ id: result.insertId });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to create post', error: err.message });
  }
});

router.patch('/posts/:id', auth, async (req, res) => {
  const postId = Number(req.params.id);
  const content = (req.body.content || '').toString().trim();
  const hasImageUrl = Object.prototype.hasOwnProperty.call(req.body || {}, 'image_url');
  const imageUrlRaw = (req.body.image_url ?? '').toString().trim();
  const imageUrl = imageUrlRaw.isEmpty ? null : imageUrlRaw;

  if (!Number.isInteger(postId) || postId <= 0) {
    return res.status(400).json({ message: 'Invalid post id' });
  }
  if (!content) {
    return res.status(400).json({ message: 'content is required' });
  }
  if (content.length > 2000) {
    return res.status(400).json({ message: 'content must be at most 2000 characters' });
  }

  try {
    const [existing] = await pool.execute(
      'SELECT user_id FROM community_posts WHERE id = ? LIMIT 1',
      [postId]
    );
    if (!existing.length) {
      return res.status(404).json({ message: 'Post not found' });
    }
    if (Number(existing[0].user_id) !== req.user.id) {
      return res.status(403).json({ message: 'You can only edit your own post' });
    }

    if (hasImageUrl) {
      await pool.execute('UPDATE community_posts SET content = ?, image_url = ? WHERE id = ?', [
        content,
        imageUrl,
        postId,
      ]);
    } else {
      await pool.execute('UPDATE community_posts SET content = ? WHERE id = ?', [content, postId]);
    }
    return res.json({ id: postId, updated: true });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to update post', error: err.message });
  }
});

router.delete('/posts/:id', auth, async (req, res) => {
  const postId = Number(req.params.id);

  if (!Number.isInteger(postId) || postId <= 0) {
    return res.status(400).json({ message: 'Invalid post id' });
  }

  try {
    const [existing] = await pool.execute(
      'SELECT user_id FROM community_posts WHERE id = ? LIMIT 1',
      [postId]
    );
    if (!existing.length) {
      return res.status(404).json({ message: 'Post not found' });
    }
    if (Number(existing[0].user_id) !== req.user.id) {
      return res.status(403).json({ message: 'You can only delete your own post' });
    }

    await pool.execute('DELETE FROM community_posts WHERE id = ?', [postId]);
    return res.json({ id: postId, deleted: true });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to delete post', error: err.message });
  }
});

module.exports = router;
