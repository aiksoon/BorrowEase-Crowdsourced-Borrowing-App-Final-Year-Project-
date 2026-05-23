require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const { ensureSchema } = require('./config/db');

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const itemRoutes = require('./routes/items');
const requestRoutes = require('./routes/requests');
const transactionRoutes = require('./routes/transactions');
const chatRoutes = require('./routes/chats');
const reviewRoutes = require('./routes/reviews');
const reportRoutes = require('./routes/reports');
const kycRoutes = require('./routes/kyc');
const favoriteRoutes = require('./routes/favorites');
const uploadRoutes = require('./routes/uploads');
const communityRoutes = require('./routes/community');
const adminRoutes = require('./routes/admin');

const app = express();
app.use(cors());
app.use(express.json());
// Serve uploads from both repo root and backend folder to cover legacy paths.
app.use('/uploads', express.static(path.join(__dirname, '..', '..', 'uploads')));
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

app.get('/health', (_req, res) => res.json({ status: 'ok' }));
app.use('/auth', authRoutes);
app.use('/users', userRoutes);
app.use('/items', itemRoutes);
app.use('/requests', requestRoutes);
app.use('/transactions', transactionRoutes);
app.use('/chats', chatRoutes);
app.use('/reviews', reviewRoutes);
app.use('/reports', reportRoutes);
app.use('/kyc', kycRoutes);
app.use('/favorites', favoriteRoutes);
app.use('/uploads', uploadRoutes);
app.use('/community', communityRoutes);
app.use('/admin', adminRoutes);

app.use((err, _req, res, _next) => {
  return res.status(500).json({ message: 'Unexpected error', error: err.message });
});

const port = process.env.PORT || 4000;

async function startServer() {
  try {
    await ensureSchema();
    app.listen(port, () => {
      console.log(`API listening on port ${port}`);
    });
  } catch (err) {
    console.error('Failed to start server:', err.message);
    process.exit(1);
  }
}

startServer();
