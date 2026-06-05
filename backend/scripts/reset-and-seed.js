const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

async function run() {
  const requiredEnv = ['DB_HOST', 'DB_USER', 'DB_PASSWORD', 'DB_NAME'];
  const missing = requiredEnv.filter((key) => !process.env[key]);
  if (missing.length) {
    console.error(`Missing DB env vars: ${missing.join(', ')}`);
    process.exit(1);
  }

  const sqlPath = path.join(__dirname, '..', '..', 'scripts', 'reset-and-seed.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');

  console.log('[Seed] Connecting to DB', {
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    database: process.env.DB_NAME,
  });

  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    multipleStatements: true,
  });

  try {
    await connection.query(sql);
    console.log('Reset and seed completed successfully.');
  } finally {
    await connection.end();
  }
}

run().catch((err) => {
  console.error('Reset and seed failed:', err);
  process.exit(1);
});
