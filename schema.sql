-- BorrowEase MySQL schema v2

-- Users
CREATE TABLE users (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  phone VARCHAR(50),
  location VARCHAR(120),
  password_hash VARCHAR(255) NOT NULL,
  name VARCHAR(100) NOT NULL,
  avatar_url VARCHAR(500),
  is_banned TINYINT(1) NOT NULL DEFAULT 0,
  payout_bank_name VARCHAR(120),
  payout_account_holder VARCHAR(120),
  payout_account_number VARCHAR(40),
  kyc_status ENUM('unverified','pending','verified','rejected') DEFAULT 'unverified',
  kyc_note VARCHAR(500),
  reset_otp VARCHAR(6),
  reset_otp_expires DATETIME,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Items
CREATE TABLE items (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  owner_id BIGINT NOT NULL,
  title VARCHAR(200) NOT NULL,
  description TEXT,
  category VARCHAR(100),
  price_per_day DECIMAL(10,2) NOT NULL DEFAULT 0,
  deposit_amount DECIMAL(10,2) DEFAULT 0,
  location_text VARCHAR(255),
  image_url VARCHAR(500),
  video_url VARCHAR(500),
  latitude DECIMAL(10,7),
  longitude DECIMAL(10,7),
  availability ENUM('available','unavailable') DEFAULT 'available',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- Favourites
CREATE TABLE favourites (
  user_id BIGINT NOT NULL,
  item_id BIGINT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, item_id),
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (item_id) REFERENCES items(id)
) ENGINE=InnoDB;

-- Borrow Requests
CREATE TABLE borrow_requests (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  item_id BIGINT NOT NULL,
  borrower_id BIGINT NOT NULL,
  owner_id BIGINT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  status ENUM('pending','accepted','rejected','cancelled','handover','in_use','return_pending','completed') DEFAULT 'pending',
  message VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id) REFERENCES items(id),
  FOREIGN KEY (borrower_id) REFERENCES users(id),
  FOREIGN KEY (owner_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- Transactions
CREATE TABLE transactions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  request_id BIGINT NOT NULL UNIQUE,
  total_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  rental_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  deposit_amount DECIMAL(10,2) DEFAULT 0,
  service_fee_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  owner_payout_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  deposit_refund_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  deposit_confiscated TINYINT(1) NOT NULL DEFAULT 0,
  confiscation_reason VARCHAR(500),
  damage_compensation_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  payment_status ENUM('unpaid','paid','refunded','partial_refund','settled') DEFAULT 'unpaid',
  settlement_status ENUM('pending','settled','refunded') DEFAULT 'pending',
  paid_at DATETIME,
  settled_at DATETIME,
  confiscated_at DATETIME,
  handover_code VARCHAR(20),
  return_code VARCHAR(20),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (request_id) REFERENCES borrow_requests(id)
) ENGINE=InnoDB;

-- Request evidence (handover / return photos)
CREATE TABLE request_evidence (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  request_id BIGINT NOT NULL,
  evidence_type ENUM('handover','return') NOT NULL,
  url VARCHAR(500) NOT NULL,
  uploaded_by BIGINT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (request_id) REFERENCES borrow_requests(id),
  FOREIGN KEY (uploaded_by) REFERENCES users(id)
) ENGINE=InnoDB;

-- Chats
CREATE TABLE chats (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  request_id BIGINT NULL,
  user_a_id BIGINT,
  user_b_id BIGINT,
  item_id BIGINT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (request_id) REFERENCES borrow_requests(id)
) ENGINE=InnoDB;

CREATE TABLE chat_messages (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  chat_id BIGINT NOT NULL,
  sender_id BIGINT NOT NULL,
  message_type ENUM('text','image','video') DEFAULT 'text',
  content TEXT NOT NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  read_at DATETIME NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (chat_id) REFERENCES chats(id),
  FOREIGN KEY (sender_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- Reviews
CREATE TABLE reviews (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  request_id BIGINT NOT NULL,
  reviewer_id BIGINT NOT NULL,
  reviewee_id BIGINT NOT NULL,
  rating TINYINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_request_reviewer (request_id, reviewer_id),
  FOREIGN KEY (request_id) REFERENCES borrow_requests(id),
  FOREIGN KEY (reviewer_id) REFERENCES users(id),
  FOREIGN KEY (reviewee_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- Reports
CREATE TABLE reports (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  reporter_id BIGINT NOT NULL,
  target_type ENUM('user','item','request','transaction') NOT NULL,
  target_id BIGINT NOT NULL,
  request_id BIGINT,
  reason VARCHAR(500) NOT NULL,
  reason_category VARCHAR(120),
  description TEXT,
  media_urls TEXT,
  status ENUM('open','reviewing','resolved','rejected') DEFAULT 'open',
  resolution_note VARCHAR(500),
  resolved_by BIGINT,
  resolved_at DATETIME,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (reporter_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- System notifications
CREATE TABLE system_notifications (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  category VARCHAR(40) NOT NULL DEFAULT 'system',
  title VARCHAR(160) NOT NULL,
  message VARCHAR(500) NOT NULL,
  action VARCHAR(40) NOT NULL DEFAULT 'none',
  payload_json TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- Indexes
CREATE INDEX idx_items_owner ON items(owner_id);
CREATE INDEX idx_requests_item ON borrow_requests(item_id);
CREATE INDEX idx_requests_status ON borrow_requests(status);
CREATE INDEX idx_requests_borrower ON borrow_requests(borrower_id);
CREATE INDEX idx_transactions_request ON transactions(request_id);
CREATE INDEX idx_reviews_reviewee ON reviews(reviewee_id);
CREATE INDEX idx_chats_request ON chats(request_id);
CREATE INDEX idx_chats_direct_users ON chats(user_a_id, user_b_id);
CREATE INDEX idx_favourites_user ON favourites(user_id);
CREATE INDEX idx_request_evidence_request ON request_evidence(request_id);
CREATE INDEX idx_reports_request_id ON reports(request_id);
CREATE INDEX idx_system_notifications_user_created ON system_notifications(user_id, created_at);

-- Migration for existing databases (safe on MySQL 8+)
ALTER TABLE users ADD COLUMN IF NOT EXISTS location VARCHAR(120) NULL AFTER phone;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_banned TINYINT(1) NOT NULL DEFAULT 0 AFTER avatar_url;
ALTER TABLE users ADD COLUMN IF NOT EXISTS payout_bank_name VARCHAR(120) NULL AFTER avatar_url;
ALTER TABLE users ADD COLUMN IF NOT EXISTS payout_account_holder VARCHAR(120) NULL AFTER payout_bank_name;
ALTER TABLE users ADD COLUMN IF NOT EXISTS payout_account_number VARCHAR(40) NULL AFTER payout_account_holder;
ALTER TABLE items ADD COLUMN IF NOT EXISTS image_url VARCHAR(500) NULL AFTER location_text;
ALTER TABLE items ADD COLUMN IF NOT EXISTS video_url VARCHAR(500) NULL AFTER image_url;
CREATE TABLE IF NOT EXISTS favourites (
  user_id BIGINT NOT NULL,
  item_id BIGINT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, item_id),
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (item_id) REFERENCES items(id)
) ENGINE=InnoDB;
ALTER TABLE chats MODIFY COLUMN request_id BIGINT NULL;
ALTER TABLE chats ADD COLUMN IF NOT EXISTS user_a_id BIGINT NULL AFTER request_id;
ALTER TABLE chats ADD COLUMN IF NOT EXISTS user_b_id BIGINT NULL AFTER user_a_id;
ALTER TABLE chats ADD COLUMN IF NOT EXISTS item_id BIGINT NULL AFTER user_b_id;
CREATE TABLE IF NOT EXISTS system_notifications (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  category VARCHAR(40) NOT NULL DEFAULT 'system',
  title VARCHAR(160) NOT NULL,
  message VARCHAR(500) NOT NULL,
  action VARCHAR(40) NOT NULL DEFAULT 'none',
  payload_json TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB;
