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
    const [rows] = await c.query(`
      SELECT
        i.title,
        br.status,
        br.start_date,
        br.end_date,
        i.price_per_day,
        t.deposit_amount,
        t.total_amount
      FROM borrow_requests br
      JOIN items i ON i.id = br.item_id
      LEFT JOIN transactions t ON t.request_id = br.id
      WHERE br.status IN ('completed', 'in_use', 'accepted')
      ORDER BY br.id
    `);

    const out = rows.map((r) => {
      const start = new Date(r.start_date);
      const end = new Date(r.end_date);
      const days = Math.max(1, Math.round((end - start) / (1000 * 60 * 60 * 24)) + 1);
      const expected = Number(r.price_per_day) * days + Number(r.deposit_amount || 0);
      return {
        title: r.title,
        status: r.status,
        days,
        price_per_day: Number(r.price_per_day),
        deposit_amount: Number(r.deposit_amount || 0),
        total_amount: Number(r.total_amount || 0),
        expected_total: Number(expected.toFixed(2)),
      };
    });

    console.log(out);
  } finally {
    await c.end();
  }
}

run().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
