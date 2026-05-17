const jwt = require('jsonwebtoken');
const pool = require('../config/db');

async function authMiddleware(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ message: 'Unauthorized' });
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    const [rows] = await pool.execute(
      'SELECT id, email, is_banned FROM users WHERE id = ? LIMIT 1',
      [payload.id]
    );
    if (!rows.length) {
      return res.status(401).json({ message: 'Invalid token' });
    }
    const user = rows[0];
    if (Number(user.is_banned || 0) === 1) {
      return res.status(403).json({ message: 'Account is banned' });
    }
    req.user = { id: user.id, email: user.email || payload.email };
    return next();
  } catch (err) {
    return res.status(401).json({ message: 'Invalid token' });
  }
}

module.exports = authMiddleware;
