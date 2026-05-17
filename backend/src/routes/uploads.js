const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const auth = require('../middleware/auth');

const router = express.Router();

const uploadDir = path.join(__dirname, '..', '..', 'uploads');
fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadDir),
  filename: (_req, file, cb) => {
    const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    const ext = path.extname(file.originalname || '').toLowerCase();
    cb(null, `${unique}${ext}`);
  },
});

const upload = multer({ storage });

router.post('/', auth, upload.array('files', 5), (req, res) => {
  const files = req.files || [];
  if (!files.length) {
    return res.status(400).json({ message: 'No files uploaded' });
  }
  const urls = files.map((f) => `/uploads/${path.basename(f.path)}`);
  return res.status(201).json({ urls });
});

module.exports = router;
