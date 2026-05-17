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

function parseMediaUrls(raw) {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      return parsed.map((v) => (v ?? '').toString()).filter((v) => v.trim().length > 0);
    }
    return [];
  } catch (_) {
    return [];
  }
}

function toNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function toBoolean(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value === 1;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === 'true' || normalized === '1' || normalized === 'yes';
  }
  return false;
}

router.get('/dashboard-stats', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  try {
    const [[usersRows], [activeRows], [pendingKycRows], [openReportsRows], [totalReportsRows], [unavailableListingsRows], [txRows]] =
      await Promise.all([
        pool.execute('SELECT COUNT(*) AS cnt FROM users'),
        pool.execute("SELECT COUNT(*) AS cnt FROM items WHERE availability = 'available'"),
        pool.execute("SELECT COUNT(*) AS cnt FROM users WHERE kyc_status = 'pending'"),
        pool.execute("SELECT COUNT(*) AS cnt FROM reports WHERE status IN ('open', 'reviewing')"),
        pool.execute('SELECT COUNT(*) AS cnt FROM reports'),
        pool.execute("SELECT COUNT(*) AS cnt FROM items WHERE availability = 'unavailable'"),
        pool.execute('SELECT COUNT(*) AS cnt FROM transactions'),
      ]);

    return res.json({
      total_users: Number(usersRows[0]?.cnt || 0),
      active_listings: Number(activeRows[0]?.cnt || 0),
      pending_kyc: Number(pendingKycRows[0]?.cnt || 0),
      reports: Number(openReportsRows[0]?.cnt || 0),
      total_reports: Number(totalReportsRows[0]?.cnt || 0),
      unavailable_listings: Number(unavailableListingsRows[0]?.cnt || 0),
      pending_listings: Number(unavailableListingsRows[0]?.cnt || 0),
      transactions: Number(txRows[0]?.cnt || 0),
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch dashboard stats', error: err.message });
  }
});

router.get('/users', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  try {
    const q = (req.query?.q || '').toString().trim();
    const where = [];
    const params = [];

    if (q) {
      where.push('(u.name LIKE ? OR u.email LIKE ?)');
      const like = `%${q}%`;
      params.push(like, like);
    }

    const sql = `SELECT u.id, u.name, u.email, u.avatar_url, u.is_banned, u.created_at
                 FROM users u
                 ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
                 ORDER BY u.created_at DESC, u.id DESC
                 LIMIT 300`;

    const [rows] = await pool.execute(sql, params);
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch users', error: err.message });
  }
});

router.patch('/users/:id/ban', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  const userId = Number(req.params.id);
  if (!Number.isInteger(userId) || userId <= 0) {
    return res.status(400).json({ message: 'Invalid user id' });
  }

  const isBanned = toBoolean(req.body?.is_banned);

  try {
    const [rows] = await pool.execute(
      'SELECT id, email, name FROM users WHERE id = ? LIMIT 1',
      [userId]
    );

    if (!rows.length) {
      return res.status(404).json({ message: 'User not found' });
    }

    const targetUser = rows[0];
    if (Number(targetUser.id) === Number(req.user.id)) {
      return res.status(400).json({ message: 'You cannot ban your own account' });
    }

    const adminEmails = typeof pool.getConfiguredAdminEmails === 'function'
      ? pool.getConfiguredAdminEmails()
      : [];
    const targetEmail = (targetUser.email || '').toString().trim().toLowerCase();
    if (isBanned && adminEmails.includes(targetEmail)) {
      return res.status(400).json({ message: 'System admin accounts cannot be banned' });
    }

    await pool.execute(
      'UPDATE users SET is_banned = ? WHERE id = ?',
      [isBanned ? 1 : 0, userId]
    );

    return res.json({
      id: userId,
      name: targetUser.name,
      is_banned: isBanned,
      updated: true,
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to update user ban status', error: err.message });
  }
});

router.get('/listings', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  try {
    const availability = (req.query?.availability || '').toString().trim().toLowerCase();
    const q = (req.query?.q || '').toString().trim();
    const where = [];
    const params = [];

    if (availability === 'available' || availability === 'unavailable') {
      where.push('i.availability = ?');
      params.push(availability);
    }
    if (q) {
      where.push('(i.title LIKE ? OR i.description LIKE ? OR owner.name LIKE ?)');
      const like = `%${q}%`;
      params.push(like, like, like);
    }

    const [rows] = await pool.execute(
      `SELECT i.id, i.title, i.image_url, i.availability, i.updated_at,
              owner.id AS owner_id, owner.name AS owner_name
       FROM items i
       JOIN users owner ON owner.id = i.owner_id
       ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
       ORDER BY i.updated_at DESC, i.id DESC
       LIMIT 400`,
      params
    );

    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch listings', error: err.message });
  }
});

router.delete('/listings/bulk', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  const idsRaw = Array.isArray(req.body?.ids) ? req.body.ids : [];
  const ids = [...new Set(idsRaw.map((v) => Number(v)).filter((n) => Number.isInteger(n) && n > 0))];

  if (!ids.length) {
    return res.status(400).json({ message: 'ids must be a non-empty integer array' });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const placeholders = ids.map(() => '?').join(',');
    const [deletableRows] = await conn.execute(
      `SELECT i.id
       FROM items i
       LEFT JOIN borrow_requests br ON br.item_id = i.id
       WHERE i.id IN (${placeholders})
       GROUP BY i.id
       HAVING COUNT(br.id) = 0`,
      ids
    );

    const deletableIds = deletableRows.map((r) => Number(r.id)).filter((n) => Number.isInteger(n));
    const deletableSet = new Set(deletableIds);
    const skippedIds = ids.filter((id) => !deletableSet.has(id));
    let notificationsSent = 0;

    if (deletableIds.length) {
      const deletablePlaceholders = deletableIds.map(() => '?').join(',');

      const [targetRows] = await conn.execute(
        `SELECT i.id, i.title, i.owner_id
         FROM items i
         WHERE i.id IN (${deletablePlaceholders})`,
        deletableIds
      );

      if (targetRows.length) {
        const values = [];
        const params = [];

        for (const row of targetRows) {
          const itemId = Number(row.id);
          const ownerId = Number(row.owner_id);
          const itemTitle = (row.title || `Item #${itemId}`).toString();
          const title = 'Listing removed by admin';
          const message = `Your listing \"${itemTitle}\" was removed by admin after moderation review.`;
          const payload = JSON.stringify({
            event: 'listing_removed',
            item_id: itemId,
            item_title: itemTitle,
          });

          values.push('(?, ?, ?, ?, ?, ?)');
          params.push(ownerId, 'listing', title, message, 'listing_removed', payload);
        }

        await conn.execute(
          `INSERT INTO system_notifications (user_id, category, title, message, action, payload_json)
           VALUES ${values.join(',')}`,
          params
        );
        notificationsSent = targetRows.length;
      }

      await conn.execute(
        `DELETE FROM favourites WHERE item_id IN (${deletablePlaceholders})`,
        deletableIds
      );
      await conn.execute(
        `DELETE FROM reports WHERE target_type = 'item' AND target_id IN (${deletablePlaceholders})`,
        deletableIds
      );
      await conn.execute(
        `DELETE FROM items WHERE id IN (${deletablePlaceholders})`,
        deletableIds
      );
    }

    await conn.commit();
    return res.json({
      deleted_ids: deletableIds,
      skipped_ids: skippedIds,
      deleted_count: deletableIds.length,
      skipped_count: skippedIds.length,
      notifications_sent: notificationsSent,
    });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: 'Failed to delete listings', error: err.message });
  } finally {
    conn.release();
  }
});

router.get('/reports', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  try {
    const [rows] = await pool.execute(
      `SELECT r.*,
              rep.name AS reporter_name,
              rep.avatar_url AS reporter_avatar,
              br.id AS request_id,
              br.item_id,
              br.borrower_id,
              br.owner_id,
              borrower.name AS borrower_name,
              borrower.avatar_url AS borrower_avatar,
              owner.name AS owner_name,
              owner.avatar_url AS owner_avatar,
              i.title AS item_title,
              IF(r.reporter_id = br.borrower_id, owner.id, borrower.id) AS reported_user_id,
              IF(r.reporter_id = br.borrower_id, owner.name, borrower.name) AS reported_user_name,
              IF(r.reporter_id = br.borrower_id, owner.avatar_url, borrower.avatar_url) AS reported_user_avatar
       FROM reports r
       JOIN users rep ON rep.id = r.reporter_id
       LEFT JOIN borrow_requests br ON br.id = COALESCE(r.request_id, r.target_id)
       LEFT JOIN users borrower ON borrower.id = br.borrower_id
       LEFT JOIN users owner ON owner.id = br.owner_id
       LEFT JOIN items i ON i.id = br.item_id
       ORDER BY FIELD(r.status, 'open', 'reviewing', 'resolved', 'rejected'), r.created_at DESC`
    );

    const mapped = rows.map((row) => ({
      ...row,
      media_urls: parseMediaUrls(row.media_urls),
    }));

    return res.json(mapped);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch reports', error: err.message });
  }
});

router.get('/reports/:id', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  try {
    const reportId = Number(req.params.id);
    if (!Number.isInteger(reportId) || reportId <= 0) {
      return res.status(400).json({ message: 'Invalid report id' });
    }

    const [rows] = await pool.execute(
      `SELECT r.*,
              rep.name AS reporter_name,
              rep.avatar_url AS reporter_avatar,
              br.id AS request_id,
              br.item_id,
              br.borrower_id,
              br.owner_id,
              borrower.name AS borrower_name,
              borrower.avatar_url AS borrower_avatar,
              owner.name AS owner_name,
              owner.avatar_url AS owner_avatar,
              i.title AS item_title,
              t.id AS transaction_id,
              t.total_amount,
              t.rental_amount,
              t.deposit_amount,
              t.owner_payout_amount,
              t.deposit_refund_amount,
              t.deposit_confiscated,
              t.confiscation_reason,
              t.damage_compensation_amount,
              IF(r.reporter_id = br.borrower_id, owner.id, borrower.id) AS reported_user_id,
              IF(r.reporter_id = br.borrower_id, owner.name, borrower.name) AS reported_user_name,
              IF(r.reporter_id = br.borrower_id, owner.avatar_url, borrower.avatar_url) AS reported_user_avatar
       FROM reports r
       JOIN users rep ON rep.id = r.reporter_id
       LEFT JOIN borrow_requests br ON br.id = COALESCE(r.request_id, r.target_id)
       LEFT JOIN users borrower ON borrower.id = br.borrower_id
       LEFT JOIN users owner ON owner.id = br.owner_id
       LEFT JOIN items i ON i.id = br.item_id
       LEFT JOIN transactions t ON t.request_id = br.id
       WHERE r.id = ?
       LIMIT 1`,
      [reportId]
    );

    if (!rows.length) {
      return res.status(404).json({ message: 'Report not found' });
    }

    const report = {
      ...rows[0],
      media_urls: parseMediaUrls(rows[0].media_urls),
    };

    const requestId = Number(report.request_id || 0);
    let evidence = [];
    if (Number.isInteger(requestId) && requestId > 0) {
      const [evidenceRows] = await pool.execute(
        `SELECT id, evidence_type, url, uploaded_by, created_at
         FROM request_evidence
         WHERE request_id = ?
         ORDER BY created_at ASC, id ASC`,
        [requestId]
      );
      evidence = evidenceRows;
    }

    return res.json({
      ...report,
      evidence,
      handover_evidence: evidence.filter((e) => e.evidence_type === 'handover'),
      return_evidence: evidence.filter((e) => e.evidence_type === 'return'),
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch report details', error: err.message });
  }
});

router.patch('/reports/:id/status', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  const reportId = Number(req.params.id);
  const status = (req.body?.status || '').toString().trim().toLowerCase();
  const resolutionNote = (req.body?.resolution_note || '').toString().trim();
  if (!Number.isInteger(reportId) || reportId <= 0) {
    return res.status(400).json({ message: 'Invalid report id' });
  }
  if (!['open', 'reviewing', 'resolved', 'rejected'].includes(status)) {
    return res.status(400).json({ message: 'Invalid status' });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [reportRows] = await conn.execute(
      `SELECT id, reporter_id, request_id, status,
              COALESCE(reason_category, reason, 'Report') AS issue_label
       FROM reports
       WHERE id = ?
       LIMIT 1
       FOR UPDATE`,
      [reportId]
    );

    if (!reportRows.length) {
      await conn.rollback();
      return res.status(404).json({ message: 'Report not found' });
    }

    const report = reportRows[0];
    const [result] = await conn.execute(
      `UPDATE reports
       SET status = ?,
           resolution_note = ?,
           resolved_by = CASE WHEN ? IN ('resolved', 'rejected') THEN ? ELSE NULL END,
           resolved_at = CASE WHEN ? IN ('resolved', 'rejected') THEN NOW() ELSE NULL END,
           updated_at = NOW()
       WHERE id = ?`,
      [status, resolutionNote || null, status, req.user.id, status, reportId]
    );
    if (!result.affectedRows) {
      await conn.rollback();
      return res.status(404).json({ message: 'Report not found' });
    }

    if (status === 'resolved' && report.status !== 'resolved') {
      const noteText = resolutionNote || 'Admin has reviewed your report and marked it as resolved.';
      const title = 'Your report has been resolved';
      const message = `Report #${reportId} (${report.issue_label}) is now resolved. Resolution note: ${noteText}`;
      const payload = JSON.stringify({
        event: 'report_resolved',
        report_id: reportId,
        request_id: report.request_id,
        resolution_note: resolutionNote || null,
      });

      await conn.execute(
        `INSERT INTO system_notifications (user_id, category, title, message, action, payload_json)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [report.reporter_id, 'report', title, message, 'report_resolved', payload]
      );
    }

    await conn.commit();
    return res.json({ id: reportId, status, resolution_note: resolutionNote || null });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: 'Failed to update report', error: err.message });
  } finally {
    conn.release();
  }
});

router.get('/transactions', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  try {
    const [rows] = await pool.execute(
      `SELECT br.id AS request_id,
              br.status AS request_status,
              br.start_date,
              br.end_date,
              br.created_at,
              br.updated_at,
              i.id AS item_id,
              i.title AS item_title,
              borrower.id AS borrower_id,
              borrower.name AS borrower_name,
              borrower.avatar_url AS borrower_avatar,
              owner.id AS owner_id,
              owner.name AS owner_name,
              owner.avatar_url AS owner_avatar,
              t.id AS transaction_id,
              t.total_amount,
              t.rental_amount,
              t.deposit_amount,
              t.payment_status,
              t.settlement_status,
              t.owner_payout_amount,
              t.deposit_refund_amount,
              t.deposit_confiscated,
              t.confiscation_reason,
              t.damage_compensation_amount,
              t.paid_at,
              t.settled_at,
              t.confiscated_at
       FROM borrow_requests br
       JOIN items i ON i.id = br.item_id
       JOIN users borrower ON borrower.id = br.borrower_id
       JOIN users owner ON owner.id = br.owner_id
       LEFT JOIN transactions t ON t.request_id = br.id
       ORDER BY br.updated_at DESC, br.id DESC
       LIMIT 120`
    );
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch transactions', error: err.message });
  }
});

router.get('/transactions/:requestId/evidence', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  const requestId = Number(req.params.requestId);
  if (!Number.isInteger(requestId) || requestId <= 0) {
    return res.status(400).json({ message: 'Invalid request id' });
  }

  try {
    const [rows] = await pool.execute(
      `SELECT br.id AS request_id,
              br.status AS request_status,
              br.start_date,
              br.end_date,
              br.updated_at,
              DATE_ADD(br.updated_at, INTERVAL 2 DAY) AS confiscation_deadline,
              CASE
                WHEN br.status = 'completed' AND br.updated_at <= DATE_SUB(NOW(), INTERVAL 2 DAY)
                THEN 1 ELSE 0
              END AS confiscation_window_closed,
              i.id AS item_id,
              i.title AS item_title,
              borrower.id AS borrower_id,
              borrower.name AS borrower_name,
              owner.id AS owner_id,
              owner.name AS owner_name,
              t.id AS transaction_id,
              t.total_amount,
              t.rental_amount,
              t.deposit_amount,
              t.payment_status,
              t.settlement_status,
              t.owner_payout_amount,
              t.deposit_refund_amount,
              t.deposit_confiscated,
              t.confiscation_reason,
              t.damage_compensation_amount,
              t.paid_at,
              t.settled_at,
              t.confiscated_at
       FROM borrow_requests br
       JOIN items i ON i.id = br.item_id
       JOIN users borrower ON borrower.id = br.borrower_id
       JOIN users owner ON owner.id = br.owner_id
       LEFT JOIN transactions t ON t.request_id = br.id
       WHERE br.id = ?
       LIMIT 1`,
      [requestId]
    );

    if (!rows.length) {
      return res.status(404).json({ message: 'Transaction request not found' });
    }

    const detail = rows[0];
    const [evidenceRows] = await pool.execute(
      `SELECT id, evidence_type, url, uploaded_by, created_at
       FROM request_evidence
       WHERE request_id = ?
       ORDER BY created_at ASC, id ASC`,
      [requestId]
    );

    return res.json({
      ...detail,
      evidence: evidenceRows,
      handover_evidence: evidenceRows.filter((e) => e.evidence_type === 'handover'),
      return_evidence: evidenceRows.filter((e) => e.evidence_type === 'return'),
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch evidence', error: err.message });
  }
});

router.post('/transactions/:requestId/confiscate', auth, async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ message: 'Admin only' });

  const requestId = Number(req.params.requestId);
  const reason = (req.body?.reason || '').toString().trim();
  if (!Number.isInteger(requestId) || requestId <= 0) {
    return res.status(400).json({ message: 'Invalid request id' });
  }
  if (!reason) {
    return res.status(400).json({ message: 'Confiscation reason is required' });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [rows] = await conn.execute(
      `SELECT t.id,
              t.payment_status,
              t.settlement_status,
              t.deposit_amount,
              t.deposit_refund_amount,
              t.owner_payout_amount,
              t.deposit_confiscated,
              br.status AS request_status,
              br.updated_at AS completed_at
       FROM transactions t
       JOIN borrow_requests br ON br.id = t.request_id
       WHERE t.request_id = ?
       LIMIT 1
       FOR UPDATE`,
      [requestId]
    );

    if (!rows.length) {
      await conn.rollback();
      return res.status(404).json({ message: 'Transaction not found' });
    }

    const tx = rows[0];
    if (tx.request_status !== 'completed') {
      await conn.rollback();
      return res.status(400).json({ message: 'Only completed transactions can be confiscated' });
    }

    const completedAt = tx.completed_at ? new Date(tx.completed_at) : null;
    const completedAtTs = completedAt instanceof Date ? completedAt.getTime() : Number.NaN;
    if (!Number.isFinite(completedAtTs)) {
      await conn.rollback();
      return res.status(400).json({ message: 'Invalid completion timestamp for this transaction' });
    }
    const windowMs = 2 * 24 * 60 * 60 * 1000;
    if (Date.now() > completedAtTs + windowMs) {
      await conn.rollback();
      return res.status(400).json({ message: 'Deposit can only be confiscated within 2 days after completion' });
    }

    if (tx.payment_status !== 'paid') {
      await conn.rollback();
      return res.status(400).json({ message: 'Only paid transactions can be confiscated' });
    }
    if (Number(tx.deposit_confiscated || 0) === 1) {
      await conn.rollback();
      return res.status(409).json({ message: 'Deposit already confiscated' });
    }

    const compensation = Math.max(
      0,
      toNumber(tx.deposit_refund_amount, toNumber(tx.deposit_amount, 0))
    );
    const ownerPayout = Math.max(0, toNumber(tx.owner_payout_amount, 0)) + compensation;

    await conn.execute(
      `UPDATE transactions
       SET deposit_confiscated = 1,
           confiscation_reason = ?,
           damage_compensation_amount = ?,
           owner_payout_amount = ?,
           deposit_refund_amount = 0,
           settlement_status = 'settled',
           settled_at = COALESCE(settled_at, NOW()),
           confiscated_at = NOW(),
           updated_at = NOW()
       WHERE request_id = ?`,
      [reason, compensation, ownerPayout, requestId]
    );

    await conn.execute(
      `UPDATE reports
       SET status = 'resolved',
           resolution_note = ?,
           resolved_by = ?,
           resolved_at = NOW(),
           updated_at = NOW()
       WHERE COALESCE(request_id, target_id) = ?
         AND status IN ('open', 'reviewing')`,
      [reason, req.user.id, requestId]
    );

    await conn.commit();
    return res.json({
      request_id: requestId,
      deposit_confiscated: true,
      damage_compensation_amount: compensation,
      confiscation_reason: reason,
      owner_payout_amount: ownerPayout,
      settlement_status: 'settled',
    });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: 'Failed to confiscate deposit', error: err.message });
  } finally {
    conn.release();
  }
});

module.exports = router;
