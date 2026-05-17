const express = require('express');
const pool = require('../config/db');
const auth = require('../middleware/auth');

const router = express.Router();

async function loadRequestWithAccess(requestId, userId) {
  const [rows] = await pool.execute(
    'SELECT id, owner_id, borrower_id, status FROM borrow_requests WHERE id = ? LIMIT 1',
    [requestId]
  );
  if (!rows.length) return { error: { status: 404, message: 'Request not found' } };
  const reqRow = rows[0];
  if (![reqRow.owner_id, reqRow.borrower_id].includes(userId)) {
    return { error: { status: 403, message: 'Not allowed' } };
  }
  return { request: reqRow };
}

async function settleEligibleTransactionByRequest(requestId) {
  await pool.execute(
    `UPDATE transactions t
     JOIN borrow_requests br ON br.id = t.request_id
     SET t.settlement_status = 'settled',
         t.settled_at = COALESCE(t.settled_at, NOW())
     WHERE t.request_id = ?
       AND br.status = 'completed'
       AND br.updated_at <= DATE_SUB(NOW(), INTERVAL 2 DAY)
       AND t.settlement_status = 'pending'
       AND t.payment_status = 'paid'`,
    [requestId]
  );
}

router.get('/:requestId', auth, async (req, res) => {
  const { requestId } = req.params;
  try {
    const { error, request: reqRow } = await loadRequestWithAccess(requestId, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });

    await settleEligibleTransactionByRequest(requestId);

    const [rows] = await pool.execute(
      'SELECT * FROM transactions WHERE request_id = ? LIMIT 1',
      [requestId]
    );
    if (!rows.length) return res.status(404).json({ message: 'Transaction not found' });
    const tx = rows[0];
    const total = Number(tx.total_amount || 0);
    const deposit = Number(tx.deposit_amount || 0);
    const rental = Number(tx.rental_amount || Math.max(0, total - deposit));

    return res.json({
      ...tx,
      owner_id: reqRow.owner_id,
      borrower_id: reqRow.borrower_id,
      request_status: reqRow.status,
      rental_amount: rental,
      deposit_amount: deposit,
      total_amount: total,
    });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to fetch transaction', error: err.message });
  }
});

router.post('/:requestId/pay', auth, async (req, res) => {
  const { requestId } = req.params;
  try {
    const { error, request: reqRow } = await loadRequestWithAccess(requestId, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });
    if (reqRow.borrower_id !== req.user.id) return res.status(403).json({ message: 'Only borrower can pay' });
    if (reqRow.status !== 'accepted') {
      return res.status(400).json({ message: 'Only accepted requests can be paid' });
    }

    const [result] = await pool.execute(
      `UPDATE transactions
       SET payment_status = 'paid',
           settlement_status = 'pending',
           paid_at = NOW(),
           settled_at = NULL
       WHERE request_id = ? AND payment_status IN ('unpaid', 'refunded')`,
      [requestId]
    );
    if (!result.affectedRows) {
      const [txRows] = await pool.execute(
        'SELECT payment_status FROM transactions WHERE request_id = ? LIMIT 1',
        [requestId]
      );
      const current = txRows?.[0]?.payment_status;
      return res.status(409).json({ message: `Cannot pay in current state (${current || 'unknown'})` });
    }
    return res.json({ request_id: Number(requestId), payment_status: 'paid' });
  } catch (err) {
    return res.status(500).json({ message: 'Payment simulation failed', error: err.message });
  }
});

router.post('/:requestId/refund', auth, async (req, res) => {
  const { requestId } = req.params;
  try {
    const { error, request: reqRow } = await loadRequestWithAccess(requestId, req.user.id);
    if (error) return res.status(error.status).json({ message: error.message });
    if (!['cancelled', 'rejected'].includes(reqRow.status)) {
      return res.status(400).json({ message: 'Refund is only allowed for cancelled/rejected requests' });
    }

    await pool.execute(
      `UPDATE transactions
       SET payment_status = 'refunded',
           settlement_status = 'refunded',
           owner_payout_amount = 0,
           settled_at = NOW()
       WHERE request_id = ?`,
      [requestId]
    );
    return res.json({ request_id: Number(requestId), payment_status: 'refunded' });
  } catch (err) {
    return res.status(500).json({ message: 'Refund simulation failed', error: err.message });
  }
});

module.exports = router;
