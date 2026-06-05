const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const cloudinary = require('cloudinary').v2;
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const SEED_PREFIX = '/uploads/seed/';

const REQUIRED_ENV = [
  'DB_HOST',
  'DB_USER',
  'DB_PASSWORD',
  'DB_NAME',
  'CLOUDINARY_CLOUD_NAME',
  'CLOUDINARY_API_KEY',
  'CLOUDINARY_API_SECRET',
];

function requireEnv() {
  const missing = REQUIRED_ENV.filter((key) => !process.env[key]);
  if (missing.length) {
    console.error(`Missing env vars: ${missing.join(', ')}`);
    process.exit(1);
  }
}

function resolveSeedDir() {
  if (process.env.SEED_UPLOADS_DIR) {
    const custom = path.resolve(process.env.SEED_UPLOADS_DIR);
    if (fs.existsSync(custom)) return custom;
  }

  const candidates = [
    path.join(__dirname, '..', 'uploads', 'seed'),
    path.join(__dirname, '..', '..', 'uploads', 'seed'),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }

  return null;
}

async function uploadSeedAsset(seedDir, seedPath, folder) {
  const filename = path.basename(seedPath);
  const localPath = path.join(seedDir, filename);
  if (!fs.existsSync(localPath)) {
    console.warn(`[SeedMigration] Missing file: ${localPath}`);
    return null;
  }

  const result = await cloudinary.uploader.upload(localPath, {
    folder,
    resource_type: 'image',
    use_filename: true,
    unique_filename: true,
  });

  return result?.secure_url || result?.url || null;
}

async function migrateTable(connection, seedDir, cache, table, idColumn, columns, folder) {
  const like = `${SEED_PREFIX}%`;
  const where = columns.map((col) => `${col} LIKE ?`).join(' OR ');
  const params = columns.map(() => like);

  const [rows] = await connection.execute(
    `SELECT ${idColumn}, ${columns.join(', ')} FROM ${table} WHERE ${where}`,
    params
  );

  let updated = 0;
  for (const row of rows) {
    const updates = [];
    const values = [];

    for (const column of columns) {
      const raw = row[column];
      if (typeof raw !== 'string' || !raw.startsWith(SEED_PREFIX)) continue;

      if (!cache.has(raw)) {
        const uploadedUrl = await uploadSeedAsset(seedDir, raw, folder);
        if (!uploadedUrl) continue;
        cache.set(raw, uploadedUrl);
      }

      updates.push(`${column} = ?`);
      values.push(cache.get(raw));
    }

    if (!updates.length) continue;
    values.push(row[idColumn]);
    await connection.execute(
      `UPDATE ${table} SET ${updates.join(', ')} WHERE ${idColumn} = ?`,
      values
    );
    updated += 1;
  }

  console.log(`[SeedMigration] ${table}: updated ${updated} row(s)`);
}

async function run() {
  requireEnv();

  const seedDir = resolveSeedDir();
  if (!seedDir) {
    console.error('Seed uploads folder not found. Set SEED_UPLOADS_DIR if needed.');
    process.exit(1);
  }

  const folder = (process.env.CLOUDINARY_SEED_FOLDER || 'borrowease/seed').trim();

  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
    secure: true,
  });

  console.log('[SeedMigration] Using seed dir:', seedDir);
  console.log('[SeedMigration] Cloudinary folder:', folder);

  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });

  const cache = new Map();

  try {
    await migrateTable(connection, seedDir, cache, 'items', 'id', ['image_url', 'video_url'], folder);
    await migrateTable(connection, seedDir, cache, 'community_posts', 'id', ['image_url'], folder);
    await migrateTable(connection, seedDir, cache, 'users', 'id', ['avatar_url'], folder);
    await migrateTable(connection, seedDir, cache, 'request_evidence', 'id', ['url'], folder);
  } finally {
    await connection.end();
  }

  console.log('[SeedMigration] Done.');
}

run().catch((err) => {
  console.error('[SeedMigration] Failed:', err);
  process.exit(1);
});
