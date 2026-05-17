const path = require('path');
const mysql = require('mysql2/promise');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

async function run() {
  const c = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT || 3306,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });

  try {
    const [requestStatus] = await c.query(
      'SELECT status, COUNT(*) AS total FROM borrow_requests GROUP BY status ORDER BY status'
    );
    const [txStatus] = await c.query(
      'SELECT payment_status, COUNT(*) AS total FROM transactions GROUP BY payment_status ORDER BY payment_status'
    );
    const [reviewStats] = await c.query(
      'SELECT reviewee_id, ROUND(AVG(rating), 2) AS avg_rating, COUNT(*) AS total_reviews FROM reviews GROUP BY reviewee_id ORDER BY reviewee_id'
    );
    const [recentHistory] = await c.query(`
      SELECT
        br.id AS request_id,
        br.status,
        i.title AS item_title,
        uo.name AS owner_name,
        ub.name AS borrower_name,
        t.payment_status,
        t.total_amount
      FROM borrow_requests br
      JOIN items i ON i.id = br.item_id
      JOIN users uo ON uo.id = br.owner_id
      JOIN users ub ON ub.id = br.borrower_id
      LEFT JOIN transactions t ON t.request_id = br.id
      ORDER BY br.id DESC
      LIMIT 8
    `);

    console.log('requestStatus=', requestStatus);
    console.log('transactionStatus=', txStatus);
    console.log('reviewStats=', reviewStats);
    console.log('recentHistory=', recentHistory);
  } finally {
    await c.end();
  }
}

run().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
