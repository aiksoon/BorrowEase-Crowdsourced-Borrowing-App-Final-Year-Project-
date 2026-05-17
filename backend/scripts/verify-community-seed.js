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
    const [img] = await c.query(
      "SELECT COUNT(*) AS with_image FROM community_posts WHERE image_url IS NOT NULL AND TRIM(image_url) <> ''"
    );
    const [sample] = await c.query(
      'SELECT u.name, u.location, cp.content FROM community_posts cp JOIN users u ON u.id = cp.user_id ORDER BY cp.id LIMIT 6'
    );
    const [loc] = await c.query(
      'SELECT LOWER(TRIM(u.location)) AS loc, COUNT(cp.id) AS post_count FROM users u JOIN community_posts cp ON cp.user_id = u.id GROUP BY LOWER(TRIM(u.location)) ORDER BY loc'
    );

    console.log('withImage=', img[0].with_image);
    console.log('samplePosts=', sample);
    console.log('locationCount=', loc.length);
    console.log('allLocationCounts=', loc);
  } finally {
    await c.end();
  }
}

run().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
