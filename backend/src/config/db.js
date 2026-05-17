const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
});

const DEFAULT_ADMIN_EMAIL = 'admin@crowdborrow.local';
const DEFAULT_ADMIN_USERNAME = 'admin';
const DEFAULT_ADMIN_PASSWORD = 'Admin@123';

function getConfiguredAdminEmails() {
  const configured = (process.env.ADMIN_EMAILS || '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const defaultEmail = (process.env.DEFAULT_ADMIN_EMAIL || DEFAULT_ADMIN_EMAIL).trim().toLowerCase();
  if (defaultEmail && !configured.includes(defaultEmail)) {
    configured.push(defaultEmail);
  }
  return configured;
}

function getDefaultAdminConfig() {
  return {
    email: (process.env.DEFAULT_ADMIN_EMAIL || DEFAULT_ADMIN_EMAIL).trim().toLowerCase(),
    username: (process.env.DEFAULT_ADMIN_USERNAME || DEFAULT_ADMIN_USERNAME).trim(),
    password: process.env.DEFAULT_ADMIN_PASSWORD || DEFAULT_ADMIN_PASSWORD,
  };
}

function strongPassword(pwd) {
  return (
    typeof pwd === 'string' &&
    pwd.length >= 8 &&
    /[A-Z]/.test(pwd) &&
    /[a-z]/.test(pwd) &&
    /[0-9]/.test(pwd) &&
    /[!@#$%^&*]/.test(pwd)
  );
}

async function ensureDefaultAdminUser() {
  const admin = getDefaultAdminConfig();
  if (!admin.email || !admin.username || !admin.password) {
    throw new Error('DEFAULT_ADMIN_EMAIL, DEFAULT_ADMIN_USERNAME, and DEFAULT_ADMIN_PASSWORD must be set');
  }
  if (!strongPassword(admin.password)) {
    throw new Error('DEFAULT_ADMIN_PASSWORD must be 8+ chars with A-Z, a-z, 0-9, and !@#$%^&*');
  }

  const passwordHash = await bcrypt.hash(admin.password, 10);
  const [rows] = await pool.query(
    'SELECT id FROM users WHERE LOWER(email) = ? OR LOWER(name) = ? LIMIT 1',
    [admin.email.toLowerCase(), admin.username.toLowerCase()]
  );

  if (rows.length) {
    await pool.query(
      'UPDATE users SET email = ?, name = ?, password_hash = ?, kyc_status = ? WHERE id = ?',
      [admin.email, admin.username, passwordHash, 'verified', rows[0].id]
    );
    console.log(`[DB] Refreshed system admin credentials for user id=${rows[0].id}`);
    return;
  }

  const [result] = await pool.query(
    'INSERT INTO users (email, password_hash, name, phone, location, kyc_status) VALUES (?, ?, ?, ?, ?, ?)',
    [admin.email, passwordHash, admin.username, null, null, 'verified']
  );
  console.log(`[DB] Created system admin user id=${result.insertId}`);
}

async function ensureUsersLocationColumn() {
  const sql = `
    SELECT COUNT(*) AS cnt
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND COLUMN_NAME = 'location'
  `;
  const [rows] = await pool.query(sql);
  const hasColumn = Number(rows?.[0]?.cnt || 0) > 0;
  if (!hasColumn) {
    await pool.query("ALTER TABLE users ADD COLUMN location VARCHAR(120) NULL AFTER phone");
    // Keep startup logs explicit so schema changes are visible in dev terminals.
    console.log("[DB] Added column users.location");
  }
}

async function ensureUsersBanColumn() {
  const [rows] = await pool.query(`
    SELECT COUNT(*) AS cnt
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND COLUMN_NAME = 'is_banned'
  `);

  const hasColumn = Number(rows?.[0]?.cnt || 0) > 0;
  if (!hasColumn) {
    await pool.query('ALTER TABLE users ADD COLUMN is_banned TINYINT(1) NOT NULL DEFAULT 0 AFTER avatar_url');
    console.log('[DB] Added column users.is_banned');
  }
}

async function ensureUsersPayoutColumns() {
  const [cols] = await pool.query(`
    SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND COLUMN_NAME IN (
        'payout_bank_name',
        'payout_account_holder',
        'payout_account_number'
      )
  `);

  const colSet = new Set(cols.map((r) => r.COLUMN_NAME));
  if (!colSet.has('payout_bank_name')) {
    await pool.query('ALTER TABLE users ADD COLUMN payout_bank_name VARCHAR(120) NULL AFTER avatar_url');
    console.log('[DB] Added column users.payout_bank_name');
  }
  if (!colSet.has('payout_account_holder')) {
    await pool.query('ALTER TABLE users ADD COLUMN payout_account_holder VARCHAR(120) NULL AFTER payout_bank_name');
    console.log('[DB] Added column users.payout_account_holder');
  }
  if (!colSet.has('payout_account_number')) {
    await pool.query('ALTER TABLE users ADD COLUMN payout_account_number VARCHAR(40) NULL AFTER payout_account_holder');
    console.log('[DB] Added column users.payout_account_number');
  }
}

async function ensureUsersKycStatusEnum() {
  const [rows] = await pool.query(`
    SELECT COLUMN_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND COLUMN_NAME = 'kyc_status'
    LIMIT 1
  `);

  const columnType = rows?.[0]?.COLUMN_TYPE?.toString() ?? '';
  if (!columnType) return;

  if (!columnType.includes("'unverified'")) {
    await pool.query("UPDATE users SET kyc_status = 'unverified' WHERE kyc_status IS NULL OR kyc_status = ''");
    await pool.query(`
      ALTER TABLE users
      MODIFY COLUMN kyc_status ENUM('unverified','pending','verified','rejected')
      NOT NULL DEFAULT 'unverified'
    `);
    console.log('[DB] Expanded users.kyc_status enum to include unverified');
  }
}

async function ensureItemsMediaColumns() {
  const sql = `
    SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'items'
      AND COLUMN_NAME IN ('image_url', 'video_url')
  `;
  const [rows] = await pool.query(sql);
  const cols = new Set(rows.map((r) => r.COLUMN_NAME));

  if (!cols.has('image_url')) {
    await pool.query("ALTER TABLE items ADD COLUMN image_url VARCHAR(500) NULL AFTER location_text");
    console.log('[DB] Added column items.image_url');
  }
  if (!cols.has('video_url')) {
    await pool.query("ALTER TABLE items ADD COLUMN video_url VARCHAR(500) NULL AFTER image_url");
    console.log('[DB] Added column items.video_url');
  }
}

async function ensureChatsDirectColumns() {
  const [chatCols] = await pool.query(`
    SELECT COLUMN_NAME, IS_NULLABLE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'chats'
      AND COLUMN_NAME IN ('request_id', 'user_a_id', 'user_b_id', 'item_id')
  `);

  const colMap = new Map(chatCols.map((r) => [r.COLUMN_NAME, r]));

  const requestIdCol = colMap.get('request_id');
  if (requestIdCol && requestIdCol.IS_NULLABLE !== 'YES') {
    await pool.query('ALTER TABLE chats MODIFY COLUMN request_id BIGINT NULL');
    console.log('[DB] Altered chats.request_id to nullable');
  }

  if (!colMap.has('user_a_id')) {
    await pool.query('ALTER TABLE chats ADD COLUMN user_a_id BIGINT NULL AFTER request_id');
    console.log('[DB] Added column chats.user_a_id');
  }
  if (!colMap.has('user_b_id')) {
    await pool.query('ALTER TABLE chats ADD COLUMN user_b_id BIGINT NULL AFTER user_a_id');
    console.log('[DB] Added column chats.user_b_id');
  }
  if (!colMap.has('item_id')) {
    await pool.query('ALTER TABLE chats ADD COLUMN item_id BIGINT NULL AFTER user_b_id');
    console.log('[DB] Added column chats.item_id');
  }
}

async function ensureChatMessagesColumns() {
  const [cols] = await pool.query(`
    SELECT COLUMN_NAME, COLUMN_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'chat_messages'
      AND COLUMN_NAME IN ('message_type', 'is_read', 'read_at')
  `);

  const colMap = new Map(cols.map((r) => [r.COLUMN_NAME, r]));

  const messageTypeCol = colMap.get('message_type');
  if (messageTypeCol && !String(messageTypeCol.COLUMN_TYPE || '').includes("'video'")) {
    await pool.query("ALTER TABLE chat_messages MODIFY COLUMN message_type ENUM('text','image','video') DEFAULT 'text'");
    console.log('[DB] Expanded chat_messages.message_type to include video');
  }

  if (!colMap.has('is_read')) {
    await pool.query('ALTER TABLE chat_messages ADD COLUMN is_read TINYINT(1) NOT NULL DEFAULT 0 AFTER content');
    console.log('[DB] Added column chat_messages.is_read');
  }

  if (!colMap.has('read_at')) {
    await pool.query('ALTER TABLE chat_messages ADD COLUMN read_at DATETIME NULL AFTER is_read');
    console.log('[DB] Added column chat_messages.read_at');
  }
}

async function ensureFavouritesTable() {
  const [tables] = await pool.query(`
    SELECT COUNT(*) AS cnt
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'favourites'
  `);

  const hasTable = Number(tables?.[0]?.cnt || 0) > 0;
  if (!hasTable) {
    await pool.query(`
      CREATE TABLE favourites (
        user_id BIGINT NOT NULL,
        item_id BIGINT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id, item_id),
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (item_id) REFERENCES items(id)
      ) ENGINE=InnoDB
    `);
    console.log('[DB] Created table favourites');
  }

  const [indexes] = await pool.query(`
    SELECT INDEX_NAME
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'favourites'
      AND INDEX_NAME IN ('idx_favourites_user', 'idx_favourites_item')
  `);

  const indexSet = new Set(indexes.map((r) => r.INDEX_NAME));
  if (!indexSet.has('idx_favourites_user')) {
    await pool.query('CREATE INDEX idx_favourites_user ON favourites(user_id)');
    console.log('[DB] Added index idx_favourites_user');
  }
  if (!indexSet.has('idx_favourites_item')) {
    await pool.query('CREATE INDEX idx_favourites_item ON favourites(item_id)');
    console.log('[DB] Added index idx_favourites_item');
  }
}

async function ensureCommunityPostsTable() {
  const [tables] = await pool.query(`
    SELECT COUNT(*) AS cnt
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'community_posts'
  `);

  const hasTable = Number(tables?.[0]?.cnt || 0) > 0;
  if (!hasTable) {
    await pool.query(`
      CREATE TABLE community_posts (
        id BIGINT NOT NULL AUTO_INCREMENT,
        user_id BIGINT NOT NULL,
        content TEXT NOT NULL,
        image_url VARCHAR(500) NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_community_posts_user (user_id),
        KEY idx_community_posts_created (created_at),
        CONSTRAINT fk_community_posts_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      ) ENGINE=InnoDB
    `);
    console.log('[DB] Created table community_posts');
  }

  const [cols] = await pool.query(`
    SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'community_posts'
      AND COLUMN_NAME IN ('image_url')
  `);
  const colSet = new Set(cols.map((r) => r.COLUMN_NAME));

  if (!colSet.has('image_url')) {
    await pool.query('ALTER TABLE community_posts ADD COLUMN image_url VARCHAR(500) NULL AFTER content');
    console.log('[DB] Added column community_posts.image_url');
  }
}

async function ensureUsersKycColumns() {
  const [cols] = await pool.query(`
    SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND COLUMN_NAME IN ('kyc_id_image_url', 'kyc_selfie_image_url', 'kyc_doc_type')
  `);

  const colSet = new Set(cols.map((r) => r.COLUMN_NAME));

  if (!colSet.has('kyc_id_image_url')) {
    await pool.query('ALTER TABLE users ADD COLUMN kyc_id_image_url VARCHAR(500) NULL AFTER kyc_note');
    console.log('[DB] Added column users.kyc_id_image_url');
  }
  if (!colSet.has('kyc_selfie_image_url')) {
    await pool.query('ALTER TABLE users ADD COLUMN kyc_selfie_image_url VARCHAR(500) NULL AFTER kyc_id_image_url');
    console.log('[DB] Added column users.kyc_selfie_image_url');
  }
  if (!colSet.has('kyc_doc_type')) {
    await pool.query('ALTER TABLE users ADD COLUMN kyc_doc_type VARCHAR(50) NULL AFTER kyc_selfie_image_url');
    console.log('[DB] Added column users.kyc_doc_type');
  }
}

async function ensureBorrowRequestsStatusEnum() {
  const [rows] = await pool.query(`
    SELECT COLUMN_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'borrow_requests'
      AND COLUMN_NAME = 'status'
    LIMIT 1
  `);

  const columnType = rows?.[0]?.COLUMN_TYPE?.toString() ?? '';
  if (!columnType) return;

  if (!columnType.includes("'return_pending'")) {
    await pool.query(`
      ALTER TABLE borrow_requests
      MODIFY COLUMN status ENUM(
        'pending',
        'accepted',
        'handover',
        'in_use',
        'return_pending',
        'completed',
        'rejected',
        'cancelled'
      ) NOT NULL DEFAULT 'pending'
    `);
    console.log('[DB] Expanded borrow_requests.status enum to include return_pending');
  }
}

async function ensureTransactionsColumns() {
  const [cols] = await pool.query(`
    SELECT COLUMN_NAME, COLUMN_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'transactions'
      AND COLUMN_NAME IN (
        'rental_amount',
        'service_fee_amount',
        'owner_payout_amount',
        'deposit_refund_amount',
        'deposit_confiscated',
        'confiscation_reason',
        'damage_compensation_amount',
        'confiscated_at',
        'settlement_status',
        'settled_at',
        'paid_at',
        'payment_status'
      )
  `);

  const colMap = new Map(cols.map((r) => [r.COLUMN_NAME, r]));

  if (!colMap.has('rental_amount')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN rental_amount DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER total_amount');
    console.log('[DB] Added column transactions.rental_amount');
  }
  if (!colMap.has('service_fee_amount')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN service_fee_amount DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER deposit_amount');
    console.log('[DB] Added column transactions.service_fee_amount');
  }
  if (!colMap.has('owner_payout_amount')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN owner_payout_amount DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER service_fee_amount');
    console.log('[DB] Added column transactions.owner_payout_amount');
  }
  if (!colMap.has('deposit_refund_amount')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN deposit_refund_amount DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER owner_payout_amount');
    console.log('[DB] Added column transactions.deposit_refund_amount');
  }
  if (!colMap.has('deposit_confiscated')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN deposit_confiscated TINYINT(1) NOT NULL DEFAULT 0 AFTER deposit_refund_amount');
    console.log('[DB] Added column transactions.deposit_confiscated');
  }
  if (!colMap.has('confiscation_reason')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN confiscation_reason VARCHAR(500) NULL AFTER deposit_confiscated');
    console.log('[DB] Added column transactions.confiscation_reason');
  }
  if (!colMap.has('damage_compensation_amount')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN damage_compensation_amount DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER confiscation_reason');
    console.log('[DB] Added column transactions.damage_compensation_amount');
  }
  if (!colMap.has('confiscated_at')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN confiscated_at DATETIME NULL AFTER damage_compensation_amount');
    console.log('[DB] Added column transactions.confiscated_at');
  }
  if (!colMap.has('settlement_status')) {
    await pool.query("ALTER TABLE transactions ADD COLUMN settlement_status ENUM('pending','settled','refunded') NOT NULL DEFAULT 'pending' AFTER payment_status");
    console.log('[DB] Added column transactions.settlement_status');
  }
  if (!colMap.has('paid_at')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN paid_at DATETIME NULL AFTER settlement_status');
    console.log('[DB] Added column transactions.paid_at');
  }
  if (!colMap.has('settled_at')) {
    await pool.query('ALTER TABLE transactions ADD COLUMN settled_at DATETIME NULL AFTER paid_at');
    console.log('[DB] Added column transactions.settled_at');
  }

  const paymentStatusCol = colMap.get('payment_status');
  const paymentStatusType = String(paymentStatusCol?.COLUMN_TYPE || '');
  if (paymentStatusCol && (!paymentStatusType.includes("'settled'") || !paymentStatusType.includes("'partial_refund'"))) {
    await pool.query("ALTER TABLE transactions MODIFY COLUMN payment_status ENUM('unpaid','paid','refunded','partial_refund','settled') NOT NULL DEFAULT 'unpaid'");
    console.log('[DB] Expanded transactions.payment_status enum');
  }
}

async function ensureReportsColumns() {
  const [tables] = await pool.query(`
    SELECT COUNT(*) AS cnt
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'reports'
  `);
  const hasTable = Number(tables?.[0]?.cnt || 0) > 0;
  if (!hasTable) return;

  const [cols] = await pool.query(`
    SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'reports'
      AND COLUMN_NAME IN (
        'request_id',
        'reason_category',
        'description',
        'media_urls',
        'resolution_note',
        'resolved_by',
        'resolved_at'
      )
  `);
  const colSet = new Set(cols.map((r) => r.COLUMN_NAME));

  if (!colSet.has('request_id')) {
    await pool.query('ALTER TABLE reports ADD COLUMN request_id BIGINT NULL AFTER target_id');
    await pool.query('CREATE INDEX idx_reports_request_id ON reports(request_id)');
    console.log('[DB] Added column reports.request_id');
  }
  if (!colSet.has('reason_category')) {
    await pool.query('ALTER TABLE reports ADD COLUMN reason_category VARCHAR(120) NULL AFTER reason');
    console.log('[DB] Added column reports.reason_category');
  }
  if (!colSet.has('description')) {
    await pool.query('ALTER TABLE reports ADD COLUMN description TEXT NULL AFTER reason_category');
    console.log('[DB] Added column reports.description');
  }
  if (!colSet.has('media_urls')) {
    await pool.query('ALTER TABLE reports ADD COLUMN media_urls TEXT NULL AFTER description');
    console.log('[DB] Added column reports.media_urls');
  }
  if (!colSet.has('resolution_note')) {
    await pool.query('ALTER TABLE reports ADD COLUMN resolution_note VARCHAR(500) NULL AFTER status');
    console.log('[DB] Added column reports.resolution_note');
  }
  if (!colSet.has('resolved_by')) {
    await pool.query('ALTER TABLE reports ADD COLUMN resolved_by BIGINT NULL AFTER resolution_note');
    console.log('[DB] Added column reports.resolved_by');
  }
  if (!colSet.has('resolved_at')) {
    await pool.query('ALTER TABLE reports ADD COLUMN resolved_at DATETIME NULL AFTER resolved_by');
    console.log('[DB] Added column reports.resolved_at');
  }
}

async function ensureRequestEvidenceTable() {
  const [tables] = await pool.query(`
    SELECT COUNT(*) AS cnt
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'request_evidence'
  `);

  const hasTable = Number(tables?.[0]?.cnt || 0) > 0;
  if (!hasTable) {
    await pool.query(`
      CREATE TABLE request_evidence (
        id BIGINT NOT NULL AUTO_INCREMENT,
        request_id BIGINT NOT NULL,
        evidence_type ENUM('handover','return') NOT NULL,
        url VARCHAR(500) NOT NULL,
        uploaded_by BIGINT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_request_evidence_request (request_id),
        KEY idx_request_evidence_type (evidence_type),
        KEY idx_request_evidence_uploaded_by (uploaded_by),
        CONSTRAINT fk_request_evidence_request FOREIGN KEY (request_id) REFERENCES borrow_requests(id) ON DELETE CASCADE,
        CONSTRAINT fk_request_evidence_uploaded_by FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE CASCADE
      ) ENGINE=InnoDB
    `);
    console.log('[DB] Created table request_evidence');
    return;
  }

  const [indexes] = await pool.query(`
    SELECT INDEX_NAME
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'request_evidence'
      AND INDEX_NAME IN (
        'idx_request_evidence_request',
        'idx_request_evidence_type',
        'idx_request_evidence_uploaded_by'
      )
  `);
  const indexSet = new Set(indexes.map((r) => r.INDEX_NAME));
  if (!indexSet.has('idx_request_evidence_request')) {
    await pool.query('CREATE INDEX idx_request_evidence_request ON request_evidence(request_id)');
    console.log('[DB] Added index idx_request_evidence_request');
  }
  if (!indexSet.has('idx_request_evidence_type')) {
    await pool.query('CREATE INDEX idx_request_evidence_type ON request_evidence(evidence_type)');
    console.log('[DB] Added index idx_request_evidence_type');
  }
  if (!indexSet.has('idx_request_evidence_uploaded_by')) {
    await pool.query('CREATE INDEX idx_request_evidence_uploaded_by ON request_evidence(uploaded_by)');
    console.log('[DB] Added index idx_request_evidence_uploaded_by');
  }
}

async function ensureSystemNotificationsTable() {
  const [tables] = await pool.query(`
    SELECT COUNT(*) AS cnt
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'system_notifications'
  `);

  const hasTable = Number(tables?.[0]?.cnt || 0) > 0;
  if (!hasTable) {
    await pool.query(`
      CREATE TABLE system_notifications (
        id BIGINT NOT NULL AUTO_INCREMENT,
        user_id BIGINT NOT NULL,
        category VARCHAR(40) NOT NULL DEFAULT 'system',
        title VARCHAR(160) NOT NULL,
        message VARCHAR(500) NOT NULL,
        action VARCHAR(40) NOT NULL DEFAULT 'none',
        payload_json TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_system_notifications_user_created (user_id, created_at),
        CONSTRAINT fk_system_notifications_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      ) ENGINE=InnoDB
    `);
    console.log('[DB] Created table system_notifications');
    return;
  }

  const [indexes] = await pool.query(`
    SELECT INDEX_NAME
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'system_notifications'
      AND INDEX_NAME IN ('idx_system_notifications_user_created')
  `);
  const indexSet = new Set(indexes.map((r) => r.INDEX_NAME));

  if (!indexSet.has('idx_system_notifications_user_created')) {
    await pool.query('CREATE INDEX idx_system_notifications_user_created ON system_notifications(user_id, created_at)');
    console.log('[DB] Added index idx_system_notifications_user_created');
  }
}

async function ensureSchema() {
  await ensureUsersLocationColumn();
  await ensureUsersBanColumn();
  await ensureUsersPayoutColumns();
  await ensureUsersKycStatusEnum();
  await ensureUsersKycColumns();
  await ensureBorrowRequestsStatusEnum();
  await ensureTransactionsColumns();
  await ensureReportsColumns();
  await ensureRequestEvidenceTable();
  await ensureSystemNotificationsTable();
  await ensureItemsMediaColumns();
  await ensureChatsDirectColumns();
  await ensureChatMessagesColumns();
  await ensureFavouritesTable();
  await ensureCommunityPostsTable();
  await ensureDefaultAdminUser();
}

// Backward compatible exports:
// - old routes: const pool = require('../config/db')
// - new usage: const { pool, ensureUsersLocationColumn } = require('../config/db')
module.exports = pool;
module.exports.ensureUsersLocationColumn = ensureUsersLocationColumn;
module.exports.ensureUsersBanColumn = ensureUsersBanColumn;
module.exports.ensureUsersPayoutColumns = ensureUsersPayoutColumns;
module.exports.ensureUsersKycStatusEnum = ensureUsersKycStatusEnum;
module.exports.ensureItemsMediaColumns = ensureItemsMediaColumns;
module.exports.ensureChatsDirectColumns = ensureChatsDirectColumns;
module.exports.ensureChatMessagesColumns = ensureChatMessagesColumns;
module.exports.ensureFavouritesTable = ensureFavouritesTable;
module.exports.ensureCommunityPostsTable = ensureCommunityPostsTable;
module.exports.ensureUsersKycColumns = ensureUsersKycColumns;
module.exports.ensureBorrowRequestsStatusEnum = ensureBorrowRequestsStatusEnum;
module.exports.ensureTransactionsColumns = ensureTransactionsColumns;
module.exports.ensureReportsColumns = ensureReportsColumns;
module.exports.ensureRequestEvidenceTable = ensureRequestEvidenceTable;
module.exports.ensureSystemNotificationsTable = ensureSystemNotificationsTable;
module.exports.getConfiguredAdminEmails = getConfiguredAdminEmails;
module.exports.ensureDefaultAdminUser = ensureDefaultAdminUser;
module.exports.ensureSchema = ensureSchema;
