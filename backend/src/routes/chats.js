const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

async function ensureRequestAccess(requestId, userId) {
  const [rows] = await pool.execute(
    'SELECT id, owner_id, borrower_id FROM borrow_requests WHERE id = ? LIMIT 1',
    [requestId]
  );
  if (!rows.length) return { error: { status: 404, message: 'Request not found' } };
  const row = rows[0];
  if (![row.owner_id, row.borrower_id].includes(userId)) {
    return { error: { status: 403, message: 'Not allowed' } };
  }
  return { request: row };
}

async function ensureDirectPeerAccess(peerUserId, userId) {
  const peerId = Number(peerUserId);
  if (!Number.isInteger(peerId) || peerId <= 0) {
    return { error: { status: 400, message: 'peer_user_id must be a valid integer' } };
  }
  if (peerId === userId) {
    return { error: { status: 400, message: 'Cannot create direct chat with yourself' } };
  }
  const [users] = await pool.execute('SELECT id FROM users WHERE id = ? LIMIT 1', [peerId]);
  if (!users.length) {
    return { error: { status: 404, message: 'Peer user not found' } };
  }
  return { peerId };
}

async function ensureChatAccess(chatId, userId) {
  const [chatRows] = await pool.execute(
    'SELECT id, request_id, user_a_id, user_b_id FROM chats WHERE id = ? LIMIT 1',
    [chatId]
  );
  if (!chatRows.length) {
    return { error: { status: 404, message: 'Chat not found' } };
  }

  const chat = chatRows[0];
  if (chat.request_id) {
    const { error, request } = await ensureRequestAccess(chat.request_id, userId);
    if (error) return { error };
    return { chat, request };
  }

  if (![chat.user_a_id, chat.user_b_id].includes(userId)) {
    return { error: { status: 403, message: 'Not allowed' } };
  }
  return { chat };
}

router.post('/', auth, async (req, res) => {
  const { request_id } = req.body;
  if (!request_id) return res.status(400).json({ message: 'request_id is required' });
  try {
    const { error } = await ensureRequestAccess(request_id, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [existing] = await conn.execute('SELECT id FROM chats WHERE request_id = ? LIMIT 1', [request_id]);
      if (existing.length) {
        await conn.commit();
        return res.json({ id: existing[0].id, request_id: Number(request_id) });
      }
      const [result] = await conn.execute('INSERT INTO chats (request_id) VALUES (?)', [request_id]);
      await conn.commit();
      return res.status(201).json({ id: result.insertId, request_id: Number(request_id) });
    } catch (err) {
      await conn.rollback();
      return res.status(500).json({ message: 'Failed to create chat', error: err.message });
    } finally {
      conn.release();
    }
  } catch (err) {
    return res.status(500).json({ message: 'Failed to create chat', error: err.message });
  }
});

router.post('/direct', auth, async (req, res) => {
  const { peer_user_id, item_id } = req.body;
  try {
    const { error, peerId } = await ensureDirectPeerAccess(peer_user_id, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });

    const userA = Math.min(req.user.id, peerId);
    const userB = Math.max(req.user.id, peerId);
    const itemId = item_id === undefined || item_id === null || item_id === '' ? null : Number(item_id);
    if (itemId !== null && (!Number.isInteger(itemId) || itemId <= 0)) {
      return res.status(400).json({ message: 'item_id must be a valid integer when provided' });
    }

    const [existing] = itemId === null
      ? await pool.execute(
          `SELECT id, request_id, user_a_id, user_b_id, item_id, created_at
           FROM chats
           WHERE request_id IS NULL
             AND user_a_id = ?
             AND user_b_id = ?
           ORDER BY id DESC
           LIMIT 1`,
          [userA, userB]
        )
      : await pool.execute(
          `SELECT id, request_id, user_a_id, user_b_id, item_id, created_at
           FROM chats
           WHERE request_id IS NULL
             AND user_a_id = ?
             AND user_b_id = ?
             AND (item_id <=> ?)
           LIMIT 1`,
          [userA, userB, itemId]
        );
    if (existing.length) {
      return res.json(existing[0]);
    }

    const [result] = await pool.execute(
      'INSERT INTO chats (request_id, user_a_id, user_b_id, item_id) VALUES (NULL, ?, ?, ?)',
      [userA, userB, itemId]
    );

    return res.status(201).json({
      id: result.insertId,
      request_id: null,
      user_a_id: userA,
      user_b_id: userB,
      item_id: itemId,
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to create direct chat', error: err.message });
  }
});

router.get('/', auth, async (req, res) => {
  const { request_id } = req.query;

  if (!request_id) {
    try {
      const userId = req.user.id;

      const [requestChats] = await pool.execute(
        `SELECT
           c.id,
           c.request_id,
           br.item_id,
           i.title AS item_title,
           i.image_url,
           br.status AS request_status,
           CASE WHEN br.owner_id = ? THEN br.borrower_id ELSE br.owner_id END AS peer_user_id,
           CASE WHEN br.owner_id = ? THEN ub.name ELSE uo.name END AS peer_name,
           CASE WHEN br.owner_id = ? THEN ub.avatar_url ELSE uo.avatar_url END AS peer_avatar_url,
           lm.content AS last_message,
           lm.message_type AS last_message_type,
           lm.created_at AS last_message_at,
           (
             SELECT COUNT(*)
             FROM chat_messages cm3
             WHERE cm3.chat_id = c.id
               AND cm3.sender_id <> ?
               AND cm3.is_read = 0
           ) AS unread_count,
           c.created_at
         FROM chats c
         JOIN borrow_requests br ON br.id = c.request_id
         JOIN users uo ON uo.id = br.owner_id
         JOIN users ub ON ub.id = br.borrower_id
         LEFT JOIN items i ON i.id = br.item_id
         LEFT JOIN chat_messages lm ON lm.id = (
           SELECT cm2.id
           FROM chat_messages cm2
           WHERE cm2.chat_id = c.id
           ORDER BY cm2.created_at DESC, cm2.id DESC
           LIMIT 1
         )
         WHERE br.owner_id = ? OR br.borrower_id = ?`,
        [userId, userId, userId, userId, userId, userId]
      );

      const [directChats] = await pool.execute(
        `SELECT
           c.id,
           c.request_id,
           c.item_id,
           i.title AS item_title,
           i.image_url,
           NULL AS request_status,
           CASE WHEN c.user_a_id = ? THEN c.user_b_id ELSE c.user_a_id END AS peer_user_id,
           u.name AS peer_name,
           u.avatar_url AS peer_avatar_url,
           lm.content AS last_message,
           lm.message_type AS last_message_type,
           lm.created_at AS last_message_at,
           (
             SELECT COUNT(*)
             FROM chat_messages cm3
             WHERE cm3.chat_id = c.id
               AND cm3.sender_id <> ?
               AND cm3.is_read = 0
           ) AS unread_count,
           c.created_at
         FROM chats c
         JOIN users u ON u.id = CASE WHEN c.user_a_id = ? THEN c.user_b_id ELSE c.user_a_id END
         LEFT JOIN items i ON i.id = c.item_id
         LEFT JOIN chat_messages lm ON lm.id = (
           SELECT cm2.id
           FROM chat_messages cm2
           WHERE cm2.chat_id = c.id
           ORDER BY cm2.created_at DESC, cm2.id DESC
           LIMIT 1
         )
         WHERE c.request_id IS NULL
           AND (c.user_a_id = ? OR c.user_b_id = ?)`,
        [userId, userId, userId, userId, userId]
      );

      const chats = [...requestChats, ...directChats].sort((a, b) => {
        const ta = new Date(a.last_message_at || a.created_at).getTime();
        const tb = new Date(b.last_message_at || b.created_at).getTime();
        return tb - ta;
      });

      return res.json(chats);
    } catch (err) {
      return res.status(500).json({ message: 'Failed to list chats', error: err.message });
    }
  }

  try {
    const { error } = await ensureRequestAccess(request_id, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });

    const [rows] = await pool.execute('SELECT id, request_id, created_at FROM chats WHERE request_id = ? LIMIT 1', [request_id]);
    if (!rows.length) return res.status(404).json({ message: 'Chat not found' });
    return res.json(rows[0]);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch chat', error: err.message });
  }
});

router.get('/:id/messages', auth, async (req, res) => {
  const { id } = req.params;
  try {
    const { error } = await ensureChatAccess(id, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });

    await pool.execute(
      `UPDATE chat_messages
       SET is_read = 1,
           read_at = COALESCE(read_at, CURRENT_TIMESTAMP)
       WHERE chat_id = ?
         AND sender_id <> ?
         AND is_read = 0`,
      [id, req.user.id]
    );

    const [messages] = await pool.execute(
      `SELECT cm.*, u.name AS sender_name
       FROM chat_messages cm
       JOIN users u ON cm.sender_id = u.id
       WHERE cm.chat_id = ?
       ORDER BY cm.created_at ASC`,
      [id]
    );
    return res.json(messages);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch messages', error: err.message });
  }
});

router.post('/:id/messages', auth, async (req, res) => {
  const { id } = req.params;
  const { content, message_type = 'text' } = req.body;
  const normalizedContent = (content || '').toString().trim();
  const normalizedType = (message_type || 'text').toString().trim().toLowerCase();
  const allowedTypes = new Set(['text', 'image', 'video']);

  if (!normalizedContent) {
    return res.status(400).json({ message: 'content is required' });
  }
  if (!allowedTypes.has(normalizedType)) {
    return res.status(400).json({ message: 'message_type must be text, image, or video' });
  }

  try {
    const { error } = await ensureChatAccess(id, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });

    const [result] = await pool.execute(
      'INSERT INTO chat_messages (chat_id, sender_id, message_type, content) VALUES (?, ?, ?, ?)',
      [id, req.user.id, normalizedType, normalizedContent]
    );
    return res.status(201).json({ id: result.insertId, chat_id: Number(id), sender_id: req.user.id });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to send message', error: err.message });
  }
});

router.delete('/:id', auth, async (req, res) => {
  const { id } = req.params;
  try {
    const { error } = await ensureChatAccess(id, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      await conn.execute('DELETE FROM chat_messages WHERE chat_id = ?', [id]);
      await conn.execute('DELETE FROM chats WHERE id = ? LIMIT 1', [id]);
      await conn.commit();
      return res.json({ ok: true, id: Number(id) });
    } catch (err) {
      await conn.rollback();
      return res.status(500).json({ message: 'Failed to delete chat', error: err.message });
    } finally {
      conn.release();
    }
  } catch (err) {
    return res.status(500).json({ message: 'Failed to delete chat', error: err.message });
  }
});

module.exports = router;
