const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

const transitions = {
  pending: ['accepted', 'rejected', 'cancelled'],
  accepted: ['handover', 'cancelled'],
  handover: ['in_use'],
  in_use: ['return_pending', 'cancelled'],
  return_pending: ['completed'],
  rejected: [],
  cancelled: [],
  completed: [],
};

const BLOCKED_BOOKING_STATUSES = [
  'accepted',
  'handover',
  'in_use',
  'return_pending',
  'completed',
];

async function settleEligibleTransactionsForUser(userId) {
  await pool.execute(
    `UPDATE transactions t
     JOIN borrow_requests br ON br.id = t.request_id
     SET t.settlement_status = 'settled',
         t.settled_at = COALESCE(t.settled_at, NOW())
     WHERE br.status = 'completed'
       AND br.updated_at <= DATE_SUB(NOW(), INTERVAL 2 DAY)
       AND t.settlement_status = 'pending'
       AND t.payment_status = 'paid'
       AND (br.owner_id = ? OR br.borrower_id = ?)`,
    [userId, userId]
  );
}

async function countEvidence(conn, requestId, type, uploadedBy) {
  const params = [requestId, type];
  let sql = 'SELECT COUNT(*) AS cnt FROM request_evidence WHERE request_id = ? AND evidence_type = ?';
  if (uploadedBy !== undefined) {
    sql += ' AND uploaded_by = ?';
    params.push(uploadedBy);
  }
  const [rows] = await conn.execute(sql, params);
  return Number(rows?.[0]?.cnt || 0);
}

router.post('/', auth, async (req, res) => {
  const { item_id, start_date, end_date, message } = req.body;
  if (!item_id || !start_date || !end_date) {
    return res.status(400).json({ message: 'item_id, start_date, end_date are required' });
  }
  const start = new Date(start_date);
  const end = new Date(end_date);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    return res.status(400).json({ message: 'Invalid date format' });
  }
  if (start > end) {
    return res.status(400).json({ message: 'start_date must be before end_date' });
  }
  try {
    const [items] = await pool.execute(
      'SELECT owner_id, price_per_day, deposit_amount FROM items WHERE id = ?',
      [item_id]
    );
    if (!items.length) return res.status(404).json({ message: 'Item not found' });
    const { owner_id: ownerId, price_per_day: pricePerDay, deposit_amount: depositAmount } = items[0];
    if (ownerId === req.user.id) return res.status(400).json({ message: 'Cannot request your own item' });

    // Prevent overlapping active rentals for this item
    const [conflicts] = await pool.execute(
      `SELECT id FROM borrow_requests
       WHERE item_id = ? AND status IN ('accepted','handover','in_use','return_pending','completed')
       AND NOT (end_date < ? OR start_date > ?)
       LIMIT 1`,
      [item_id, start_date, end_date]
    );
    if (conflicts.length) {
      return res.status(409).json({ message: 'Item has an active booking in this period' });
    }

    const days = Math.max(1, Math.round((end - start) / (1000 * 60 * 60 * 24)) + 1);
    const rentalTotal = Number(pricePerDay || 0) * days;
    const deposit = Number(depositAmount || 0);
    const serviceFee = 0;
    const total = rentalTotal + deposit;

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [result] = await conn.execute(
        `INSERT INTO borrow_requests (item_id, borrower_id, owner_id, start_date, end_date, status, message)
         VALUES (?, ?, ?, ?, ?, 'pending', ?)` ,
        [item_id, req.user.id, ownerId, start_date, end_date, message || null]
      );

      await conn.execute(
        `INSERT INTO transactions (
           request_id,
           total_amount,
           rental_amount,
           deposit_amount,
           service_fee_amount,
           payment_status,
           settlement_status
         ) VALUES (?, ?, ?, ?, ?, 'unpaid', 'pending')`,
        [result.insertId, total, rentalTotal, deposit, serviceFee]
      );

      await conn.commit();
      return res.status(201).json({ id: result.insertId, status: 'pending', total_amount: total, deposit_amount: deposit });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (err) {
    return res.status(500).json({ message: 'Failed to create request', error: err.message });
  }
});

router.get('/item/:itemId/blocked-dates', auth, async (req, res) => {
  const itemId = Number(req.params.itemId);
  if (!Number.isInteger(itemId) || itemId <= 0) {
    return res.status(400).json({ message: 'Invalid item id' });
  }

  try {
    const [rows] = await pool.execute(
      `SELECT DATE_FORMAT(start_date, '%Y-%m-%d') AS start_date,
              DATE_FORMAT(end_date, '%Y-%m-%d') AS end_date,
              status
       FROM borrow_requests
       WHERE item_id = ?
         AND status IN ('accepted','handover','in_use','return_pending','completed')
       ORDER BY start_date ASC, end_date ASC`,
      [itemId]
    );

    return res.json({
      item_id: itemId,
      statuses: BLOCKED_BOOKING_STATUSES,
      ranges: rows.map((r) => ({
        start_date: r.start_date,
        end_date: r.end_date,
        status: r.status,
      })),
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch blocked dates', error: err.message });
  }
});

router.get('/', auth, async (req, res) => {
  const { role } = req.query; // role=owner|borrower (optional). Omitted => all related to current user.
  try {
    await settleEligibleTransactionsForUser(req.user.id);

    let sql =
      `SELECT br.*, i.title AS item_title, i.price_per_day, i.image_url AS item_image_url,
              u.name AS borrower_name, ou.name AS owner_name,
              t.id AS transaction_id,
              t.total_amount,
              t.rental_amount,
              t.deposit_amount,
              t.service_fee_amount,
              t.payment_status,
              t.settlement_status,
              t.owner_payout_amount,
              t.deposit_refund_amount,
              t.deposit_confiscated,
              t.confiscation_reason,
              t.damage_compensation_amount,
              t.confiscated_at,
              t.paid_at,
              t.settled_at,
              t.updated_at AS transaction_updated_at,
              (
                SELECT COUNT(*)
                FROM request_evidence re
                WHERE re.request_id = br.id AND re.evidence_type = 'handover'
              ) AS handover_evidence_count,
              (
                SELECT COUNT(*)
                FROM request_evidence re
                WHERE re.request_id = br.id AND re.evidence_type = 'return'
              ) AS return_evidence_count,
              (
                SELECT COUNT(*)
                FROM request_evidence re
                WHERE re.request_id = br.id AND re.evidence_type = 'handover' AND re.uploaded_by = br.owner_id
              ) AS handover_owner_evidence_count,
              (
                SELECT COUNT(*)
                FROM request_evidence re
                WHERE re.request_id = br.id AND re.evidence_type = 'handover' AND re.uploaded_by = br.borrower_id
              ) AS handover_borrower_evidence_count,
              (
                SELECT COUNT(*)
                FROM request_evidence re
                WHERE re.request_id = br.id AND re.evidence_type = 'return' AND re.uploaded_by = br.owner_id
              ) AS return_owner_evidence_count,
              (
                SELECT COUNT(*)
                FROM request_evidence re
                WHERE re.request_id = br.id AND re.evidence_type = 'return' AND re.uploaded_by = br.borrower_id
              ) AS return_borrower_evidence_count
       FROM borrow_requests br
       JOIN items i ON br.item_id = i.id
       JOIN users u ON br.borrower_id = u.id
       JOIN users ou ON br.owner_id = ou.id
       LEFT JOIN transactions t ON t.request_id = br.id`;
    const params = [];

    if (role === 'owner') {
      sql += ' WHERE br.owner_id = ?';
      params.push(req.user.id);
    } else if (role === 'borrower') {
      sql += ' WHERE br.borrower_id = ?';
      params.push(req.user.id);
    } else {
      sql += ' WHERE br.owner_id = ? OR br.borrower_id = ?';
      params.push(req.user.id, req.user.id);
    }

    sql += ' ORDER BY br.created_at DESC';

    const [rows] = await pool.execute(sql, params);
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch requests', error: err.message });
  }
});

router.patch('/:id/status', auth, async (req, res) => {
  const { id } = req.params;
  const { next_status } = req.body;
  if (!next_status) return res.status(400).json({ message: 'next_status is required' });
  try {
    const [rows] = await pool.execute(
      'SELECT status, owner_id, borrower_id, item_id FROM borrow_requests WHERE id = ?',
      [id]
    );
    if (!rows.length) return res.status(404).json({ message: 'Request not found' });
    const request = rows[0];

    const allowed = transitions[request.status] || [];
    if (!allowed.includes(next_status)) {
      return res.status(400).json({ message: `Invalid transition from ${request.status} to ${next_status}` });
    }

    const isOwnerAction = ['accepted', 'rejected', 'handover', 'completed'].includes(next_status);
    if (isOwnerAction && request.owner_id !== req.user.id) {
      return res.status(403).json({ message: 'Only owner can perform this action' });
    }
    const isBorrowerAction = ['in_use', 'return_pending'].includes(next_status);
    if (isBorrowerAction && request.borrower_id !== req.user.id) {
      return res.status(403).json({ message: 'Only borrower can perform this action' });
    }
    if (next_status === 'cancelled' && ![request.borrower_id, request.owner_id].includes(req.user.id)) {
      return res.status(403).json({ message: 'Not allowed' });
    }

    // Handle transaction settlement and availability updates inside a transaction
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      const [txRows] = await conn.execute(
        `SELECT payment_status,
                total_amount, rental_amount, deposit_amount, service_fee_amount
         FROM transactions WHERE request_id = ?
         LIMIT 1`,
        [id]
      );

      let tx = txRows?.[0] || null;
      if (!tx) {
        const canBackfill = ['accepted', 'rejected', 'cancelled'].includes(next_status);
        if (!canBackfill) {
          await conn.rollback();
          return res.status(500).json({ message: 'Transaction record missing' });
        }

        const [[requestMeta]] = await conn.execute(
          `SELECT br.start_date, br.end_date, i.price_per_day, i.deposit_amount
           FROM borrow_requests br
           JOIN items i ON i.id = br.item_id
           WHERE br.id = ?
           LIMIT 1`,
          [id]
        );

        const startDate = requestMeta?.start_date ? new Date(requestMeta.start_date) : null;
        const endDate = requestMeta?.end_date ? new Date(requestMeta.end_date) : null;
        const validRange =
          startDate instanceof Date &&
          endDate instanceof Date &&
          !Number.isNaN(startDate.getTime()) &&
          !Number.isNaN(endDate.getTime());
        const days = validRange
          ? Math.max(1, Math.round((endDate - startDate) / (1000 * 60 * 60 * 24)) + 1)
          : 1;
        const rentalAmount = Number(requestMeta?.price_per_day || 0) * days;
        const depositAmount = Number(requestMeta?.deposit_amount || 0);
        const serviceFeeAmount = 0;
        const totalAmount = rentalAmount + depositAmount;

        await conn.execute(
          `INSERT INTO transactions (
             request_id,
             total_amount,
             rental_amount,
             deposit_amount,
             service_fee_amount,
             payment_status,
             settlement_status
           ) VALUES (?, ?, ?, ?, ?, 'unpaid', 'pending')`,
          [id, totalAmount, rentalAmount, depositAmount, serviceFeeAmount]
        );

        tx = {
          payment_status: 'unpaid',
          total_amount: totalAmount,
          rental_amount: rentalAmount,
          deposit_amount: depositAmount,
          service_fee_amount: serviceFeeAmount,
        };
      }

      if (next_status === 'handover') {
        if (tx.payment_status !== 'paid') {
          await conn.rollback();
          return res.status(400).json({ message: 'Borrower must complete payment before handover' });
        }
        const ownerHandoverEvidenceCount = await countEvidence(conn, id, 'handover', request.owner_id);
        if (ownerHandoverEvidenceCount < 1) {
          await conn.rollback();
          return res.status(400).json({ message: 'Owner must upload at least one handover photo before starting handover' });
        }
      }

      if (next_status === 'in_use') {
        const ownerHandoverEvidenceCount = await countEvidence(conn, id, 'handover', request.owner_id);
        if (ownerHandoverEvidenceCount < 1) {
          await conn.rollback();
          return res.status(400).json({ message: 'Owner must upload handover evidence before pickup confirmation' });
        }
      }

      if (next_status === 'return_pending') {
        const borrowerReturnEvidenceCount = await countEvidence(conn, id, 'return', request.borrower_id);
        if (borrowerReturnEvidenceCount < 1) {
          await conn.rollback();
          return res.status(400).json({ message: 'Borrower must upload return evidence before submitting return' });
        }
      }

      if (next_status === 'completed') {
        const totalAmount = Number(tx.total_amount || 0);
        const depositAmount = Number(tx.deposit_amount || 0);
        const rentalAmount = Number(tx.rental_amount || Math.max(0, totalAmount - depositAmount));
        const serviceFeeAmount = Number(tx.service_fee_amount || 0);
        const ownerPayout = Math.max(0, rentalAmount - serviceFeeAmount);
        const depositRefund = Math.max(0, depositAmount);

        await conn.execute(
          `UPDATE transactions
           SET payment_status = 'paid',
               settlement_status = 'pending',
               owner_payout_amount = ?,
               deposit_refund_amount = ?,
               settled_at = NULL
           WHERE request_id = ?`,
          [ownerPayout, depositRefund, id]
        );
      }

      if (['cancelled', 'rejected'].includes(next_status) && tx.payment_status === 'paid') {
        await conn.execute(
          `UPDATE transactions
           SET payment_status = 'refunded',
               settlement_status = 'refunded',
               owner_payout_amount = 0,
               deposit_refund_amount = COALESCE(deposit_amount, 0),
               settled_at = NOW()
           WHERE request_id = ?`,
          [id]
        );
      }

      await conn.execute(
        'UPDATE borrow_requests SET status = ?, updated_at = NOW() WHERE id = ?',
        [next_status, id]
      );

      await conn.commit();

      const [[updatedTx]] = await conn.execute(
        'SELECT payment_status, settlement_status, owner_payout_amount, deposit_refund_amount FROM transactions WHERE request_id = ? LIMIT 1',
        [id]
      );

      const response = {
        id,
        status: next_status,
        payment_status: updatedTx?.payment_status || tx.payment_status,
        settlement_status: updatedTx?.settlement_status,
        owner_payout_amount: updatedTx?.owner_payout_amount,
        deposit_refund_amount: updatedTx?.deposit_refund_amount,
      };
      return res.json(response);
    } catch (err) {
      await conn.rollback();
      return res.status(500).json({ message: 'Failed to update status', error: err.message });
    } finally {
      conn.release();
    }
  } catch (err) {
    return res.status(500).json({ message: 'Failed to update status', error: err.message });
  }
});

router.get('/:id/evidence', auth, async (req, res) => {
  const { id } = req.params;
  try {
    const [requestRows] = await pool.execute(
      'SELECT borrower_id, owner_id FROM borrow_requests WHERE id = ? LIMIT 1',
      [id]
    );
    if (!requestRows.length) return res.status(404).json({ message: 'Request not found' });

    const requestRow = requestRows[0];
    if (![requestRow.borrower_id, requestRow.owner_id].includes(req.user.id)) {
      return res.status(403).json({ message: 'Not allowed' });
    }

    const [rows] = await pool.execute(
      `SELECT id, evidence_type, url, uploaded_by, created_at
       FROM request_evidence
       WHERE request_id = ?
       ORDER BY created_at DESC, id DESC`,
      [id]
    );

    const handover = rows.filter((r) => r.evidence_type === 'handover');
    const returned = rows.filter((r) => r.evidence_type === 'return');

    return res.json({
      request_id: Number(id),
      handover,
      return: returned,
      handover_count: handover.length,
      return_count: returned.length,
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch evidence', error: err.message });
  }
});

// Upload evidence URLs (e.g., handover / return photos) and attach to a request
router.post('/:id/evidence', auth, async (req, res) => {
  const { id } = req.params;
  const { type, urls } = req.body;
  if (!['handover', 'return'].includes(type)) {
    return res.status(400).json({ message: 'type must be handover or return' });
  }
  if (!Array.isArray(urls) || !urls.length) {
    return res.status(400).json({ message: 'urls is required and must be a non-empty array' });
  }
  try {
    const [rows] = await pool.execute(
      'SELECT borrower_id, owner_id, status FROM borrow_requests WHERE id = ? LIMIT 1',
      [id]
    );
    if (!rows.length) return res.status(404).json({ message: 'Request not found' });
    const reqRow = rows[0];
    if (![reqRow.borrower_id, reqRow.owner_id].includes(req.user.id)) {
      return res.status(403).json({ message: 'Not allowed' });
    }

    if (type === 'handover' && !['accepted', 'handover', 'in_use'].includes(reqRow.status)) {
      return res.status(400).json({ message: 'Handover evidence can only be uploaded during accepted/handover stage' });
    }
    if (type === 'return' && !['in_use', 'return_pending'].includes(reqRow.status)) {
      return res.status(400).json({ message: 'Return evidence can only be uploaded during return stage' });
    }

    const normalizedUrls = Array.from(
      new Set(
        urls
          .map((u) => (u ?? '').toString().trim())
          .filter((u) => u.length > 0)
      )
    );
    if (!normalizedUrls.length) {
      return res.status(400).json({ message: 'No valid evidence URLs provided' });
    }

    const values = normalizedUrls.map((u) => [id, type, u, req.user.id]);
    await pool.query(
      'INSERT INTO request_evidence (request_id, evidence_type, url, uploaded_by) VALUES ?',
      [values]
    );
    return res.status(201).json({ request_id: Number(id), type, count: normalizedUrls.length });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to save evidence', error: err.message });
  }
});

module.exports = router;
