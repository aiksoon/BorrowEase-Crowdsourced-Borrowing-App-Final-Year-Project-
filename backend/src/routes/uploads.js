const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const cloudinary = require('cloudinary').v2;
const auth = require('../middleware/auth');

const router = express.Router();

const cloudinaryEnabled =
  Boolean(process.env.CLOUDINARY_CLOUD_NAME) &&
  Boolean(process.env.CLOUDINARY_API_KEY) &&
  Boolean(process.env.CLOUDINARY_API_SECRET);

if (cloudinaryEnabled) {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
    secure: true,
  });
}

const uploadDir = path.join(__dirname, '..', '..', 'uploads');
if (!cloudinaryEnabled) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = cloudinaryEnabled
  ? multer.memoryStorage()
  : multer.diskStorage({
      destination: (_req, _file, cb) => cb(null, uploadDir),
      filename: (_req, file, cb) => {
        const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
        const ext = path.extname(file.originalname || '').toLowerCase();
        cb(null, `${unique}${ext}`);
      },
    });

const upload = multer({ storage });

const uploadToCloudinary = (file) =>
  new Promise((resolve, reject) => {
    const folder = (process.env.CLOUDINARY_FOLDER || 'borrowease/uploads').trim();
    const stream = cloudinary.uploader.upload_stream(
      {
        folder,
        resource_type: 'auto',
      },
      (err, result) => {
        if (err) return reject(err);
        const url = result?.secure_url || result?.url;
        if (!url) return reject(new Error('Upload returned no URL'));
        return resolve(url);
      }
    );
    stream.end(file.buffer);
  });

router.post('/', auth, upload.array('files', 5), async (req, res) => {
  const files = req.files || [];
  if (!files.length) {
    return res.status(400).json({ message: 'No files uploaded' });
  }

  try {
    if (cloudinaryEnabled) {
      const urls = await Promise.all(files.map((file) => uploadToCloudinary(file)));
      return res.status(201).json({ urls });
    }

    const urls = files.map((f) => `/uploads/${path.basename(f.path)}`);
    return res.status(201).json({ urls });
  } catch (err) {
    return res.status(500).json({ message: 'Failed to upload files', error: err.message });
  }
});

module.exports = router;
