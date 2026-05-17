const path = require('path');
const mysql = require('mysql2/promise');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

async function run() {
  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });

  try {
    await connection.query("UPDATE users SET kyc_status = 'unverified' WHERE kyc_status IS NULL OR kyc_status = ''");
    await connection.query(
      "ALTER TABLE users MODIFY COLUMN kyc_status ENUM('unverified','pending','verified','rejected') NOT NULL DEFAULT 'unverified'"
    );
    await connection.query("UPDATE users SET kyc_status = 'unverified' WHERE LOWER(name) = 'soon99'");
    console.log('KYC enum and soon99 status updated successfully.');
  } finally {
    await connection.end();
  }
}

run().catch((err) => {
  console.error('Failed to fix KYC enum:', err.message);
  process.exit(1);
});
