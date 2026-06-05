SET NAMES utf8mb4;
START TRANSACTION;

SET @admin_hash = '$2a$10$CBtwKTj0D1NLrTDhDXeqSe9B7m9a2zzTu8xGuPNwzWG7uBKJj4GlO';
SET @soon_hash = '$2a$10$XjGmsI/QMsIkpmFdUrBBn.Ro.vawq/NisMeRiPYfmhn9df98tpTem';
SET @aik_hash = '$2a$10$9C5qv.j9SHVdf3Zb5rslmOcWi/WGRjEMekbzUKV6ywqBHMtiM8x/W';
SET @community_hash = @soon_hash;

-- Ensure required users exist.
INSERT INTO users (email, password_hash, name, phone, location, kyc_status)
SELECT 'admin@crowdborrow.local', @admin_hash, 'admin', '01100000000', 'Kuala Lumpur', 'verified'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE LOWER(name) = 'admin');

INSERT INTO users (email, password_hash, name, phone, location, kyc_status)
SELECT 'aiksoon99@borrowease.local', @aik_hash, 'aiksoon99', '01111111111', 'Johor', 'verified'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE LOWER(name) = 'aiksoon99');

INSERT INTO users (email, password_hash, name, phone, location, kyc_status)
SELECT 'soon99@borrowease.local', @soon_hash, 'soon99', '01222222222', 'Johor', 'unverified'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE LOWER(name) = 'soon99');

SELECT id INTO @admin_id FROM users WHERE LOWER(name) = 'admin' ORDER BY id LIMIT 1;
SELECT id INTO @aik_id FROM users WHERE LOWER(name) = 'aiksoon99' ORDER BY id LIMIT 1;
SELECT id INTO @soon_id FROM users WHERE LOWER(name) = 'soon99' ORDER BY id LIMIT 1;

-- Remove dependent data first.
DELETE FROM system_notifications;
DELETE FROM chat_messages;
DELETE FROM chats;
DELETE FROM request_evidence;
DELETE FROM reviews;
DELETE FROM transactions;
DELETE FROM reports;
DELETE FROM favourites;
DELETE FROM community_posts;
DELETE FROM borrow_requests;
DELETE FROM items;

-- Keep only admin, aiksoon99, soon99.
DELETE FROM users
WHERE id NOT IN (@admin_id, @aik_id, @soon_id);

-- Normalize retained users.
UPDATE users
SET email = 'admin@crowdborrow.local',
    name = 'admin',
    password_hash = @admin_hash,
    phone = '01100000000',
    location = 'Kuala Lumpur',
    avatar_url = NULL,
    kyc_status = 'verified'
WHERE id = @admin_id;

UPDATE users
SET email = 'aiksoon99@borrowease.local',
    name = 'aiksoon99',
    password_hash = @aik_hash,
    phone = '01111111111',
    location = 'Johor',
    avatar_url = NULL,
    kyc_status = 'verified'
WHERE id = @aik_id;

UPDATE users
SET email = 'soon99@borrowease.local',
    name = 'soon99',
    password_hash = @soon_hash,
    phone = '01222222222',
    location = 'Johor',
    avatar_url = NULL,
  kyc_status = 'unverified'
WHERE id = @soon_id;

-- High-quality catalog seed (2 items per category, realistic pricing/deposit).
INSERT INTO items (
  owner_id, title, description, category,
  price_per_day, deposit_amount, location_text,
  image_url, video_url, availability
) VALUES
  (@aik_id, 'Bosch 550W Hammer Drill', 'Reliable hammer drill for wall mounting and DIY projects. Includes side handle and depth stop.', 'Tools', 18.00, 120.00, 'Johor Bahru', '/uploads/seed/tools-power-drill.jfif', NULL, 'available'),
  (@soon_id, 'Karcher High-Pressure Washer K2', 'Compact pressure washer for car wash and outdoor cleaning. Includes spray gun and hose.', 'Tools', 28.00, 180.00, 'Skudai', '/uploads/seed/tools-high-pressure-washer.jfif', NULL, 'available'),

  (@aik_id, 'Intel i5 Productivity Laptop (16GB RAM)', 'Smooth for assignments, office work, and online meetings. Charger included.', 'Electronics', 45.00, 350.00, 'Johor Bahru', '/uploads/seed/electronics-laptop-intel.webp', NULL, 'available'),
  (@soon_id, 'Rigal RD805A WiFi Projector', 'Portable projector for movie nights or presentations. HDMI and wireless casting supported.', 'Electronics', 40.00, 300.00, 'Kulai', '/uploads/seed/electronics-rigal-rd805a-wifi-projector.png', NULL, 'available'),

  (@aik_id, 'Cambridge IELTS Official Guide', 'Excellent prep material with practice tests and strategy breakdowns.', 'Books', 6.00, 25.00, 'Johor Bahru', '/uploads/seed/books-cambridge-guide-to-ielts.jfif', NULL, 'available'),
  (@soon_id, 'Bauhaus Architecture Photo Book', 'Large-format reference book, suitable for architecture and design students.', 'Books', 5.00, 20.00, 'Johor Bahru', '/uploads/seed/books-bauhaus-architecture.jfif', NULL, 'available'),

  (@aik_id, 'Foldable Picnic Table (4-Seater)', 'Sturdy foldable table suitable for events, balcony dining, or pop-up booth use.', 'Furniture', 20.00, 140.00, 'Iskandar Puteri', '/uploads/seed/furniture-foldable-table.webp', NULL, 'available'),
  (@soon_id, 'Large Bean Bag Chair', 'Comfortable lounging bean bag for movie room or reading corner.', 'Furniture', 12.00, 60.00, 'Johor Bahru', '/uploads/seed/furniture-bean-bag.webp', NULL, 'available'),

  (@aik_id, '4-Person Camping Tent', 'Water-resistant family tent with poles and carry bag. Great for weekend camps.', 'Sports', 26.00, 160.00, 'Muar', '/uploads/seed/sports-camping-tent.jfif', NULL, 'available'),
  (@soon_id, 'City Bicycle (Adult Size)', 'Comfort commuter bike for leisure rides and short-distance travel.', 'Sports', 24.00, 180.00, 'Johor Bahru', '/uploads/seed/sports-bicycle.webp', NULL, 'available'),

  (@aik_id, 'Portable Jump Starter (12V)', 'Emergency jump starter kit for sedans and compact SUVs. Includes clamps and cable.', 'Automotive', 15.00, 100.00, 'Pasir Gudang', '/uploads/seed/automotive-jump-starter.jfif', NULL, 'available'),
  (@soon_id, 'Convertible Child Car Seat', 'Suitable for toddlers, with side-impact protection and adjustable harness.', 'Automotive', 18.00, 120.00, 'Johor Bahru', '/uploads/seed/automotive-child-car-seat.jfif', NULL, 'available'),

  (@aik_id, 'Traditional Baju Kurung Set', 'Elegant baju kurung suitable for festive events and formal gatherings.', 'Fashion', 22.00, 150.00, 'Johor Bahru', '/uploads/seed/fashion-baju-kurung.jfif', NULL, 'available'),
  (@soon_id, 'Classic Cheongsam Dress', 'Beautiful cheongsam with refined detailing. Suitable for dinner and celebration events.', 'Fashion', 25.00, 180.00, 'Johor Bahru', '/uploads/seed/fashion-cheongsam.jfif', NULL, 'available'),

  (@aik_id, 'Marshall Portable Speaker', 'Strong bass Bluetooth speaker for small gatherings and indoor parties.', 'Music', 30.00, 220.00, 'Johor Bahru', '/uploads/seed/music-marshall-speaker.jfif', NULL, 'available'),
  (@soon_id, '88-Key Digital Piano', 'Weighted keys and built-in tones. Ideal for beginner to intermediate practice.', 'Music', 55.00, 450.00, 'Johor Bahru', '/uploads/seed/music-digital-piano.jfif', NULL, 'available');

-- Advanced history seed: realistic requests, transactions, and reviews.
SELECT id INTO @item_drill FROM items WHERE owner_id = @aik_id AND title = 'Bosch 550W Hammer Drill' LIMIT 1;
SELECT id INTO @item_projector FROM items WHERE owner_id = @soon_id AND title = 'Rigal RD805A WiFi Projector' LIMIT 1;
SELECT id INTO @item_tent FROM items WHERE owner_id = @aik_id AND title = '4-Person Camping Tent' LIMIT 1;
SELECT id INTO @item_piano FROM items WHERE owner_id = @soon_id AND title = '88-Key Digital Piano' LIMIT 1;
SELECT id INTO @item_laptop FROM items WHERE owner_id = @aik_id AND title = 'Intel i5 Productivity Laptop (16GB RAM)' LIMIT 1;
SELECT id INTO @item_speaker FROM items WHERE owner_id = @aik_id AND title = 'Marshall Portable Speaker' LIMIT 1;
SELECT id INTO @item_cheongsam FROM items WHERE owner_id = @soon_id AND title = 'Classic Cheongsam Dress' LIMIT 1;

-- Completed request: soon99 borrowed drill from aiksoon99.
INSERT INTO borrow_requests (
  item_id, borrower_id, owner_id, start_date, end_date, status, message, created_at, updated_at
) VALUES (
  @item_drill, @soon_id, @aik_id,
  DATE_SUB(CURDATE(), INTERVAL 21 DAY), DATE_SUB(CURDATE(), INTERVAL 19 DAY),
  'completed',
  'Need this drill to install wall shelves for my study room.',
  DATE_SUB(NOW(), INTERVAL 24 DAY), DATE_SUB(NOW(), INTERVAL 18 DAY)
);
SET @req_completed_1 = LAST_INSERT_ID();

-- Completed request: aiksoon99 borrowed projector from soon99.
INSERT INTO borrow_requests (
  item_id, borrower_id, owner_id, start_date, end_date, status, message, created_at, updated_at
) VALUES (
  @item_projector, @aik_id, @soon_id,
  DATE_SUB(CURDATE(), INTERVAL 16 DAY), DATE_SUB(CURDATE(), INTERVAL 15 DAY),
  'completed',
  'Need projector for class presentation and discussion session.',
  DATE_SUB(NOW(), INTERVAL 18 DAY), DATE_SUB(NOW(), INTERVAL 14 DAY)
);
SET @req_completed_2 = LAST_INSERT_ID();

-- Active request: soon99 currently using camping tent.
INSERT INTO borrow_requests (
  item_id, borrower_id, owner_id, start_date, end_date, status, message, created_at, updated_at
) VALUES (
  @item_tent, @soon_id, @aik_id,
  DATE_SUB(CURDATE(), INTERVAL 1 DAY), DATE_ADD(CURDATE(), INTERVAL 2 DAY),
  'in_use',
  'Weekend island trip with friends, taking good care of the tent.',
  DATE_SUB(NOW(), INTERVAL 4 DAY), DATE_SUB(NOW(), INTERVAL 20 HOUR)
);
SET @req_in_use = LAST_INSERT_ID();

-- Accepted but not yet handover.
INSERT INTO borrow_requests (
  item_id, borrower_id, owner_id, start_date, end_date, status, message, created_at, updated_at
) VALUES (
  @item_piano, @aik_id, @soon_id,
  DATE_ADD(CURDATE(), INTERVAL 3 DAY), DATE_ADD(CURDATE(), INTERVAL 5 DAY),
  'accepted',
  'Need piano for short rehearsal before weekend performance.',
  DATE_SUB(NOW(), INTERVAL 2 DAY), DATE_SUB(NOW(), INTERVAL 6 HOUR)
);
SET @req_accepted = LAST_INSERT_ID();

-- Pending request waiting owner response.
INSERT INTO borrow_requests (
  item_id, borrower_id, owner_id, start_date, end_date, status, message, created_at, updated_at
) VALUES (
  @item_laptop, @soon_id, @aik_id,
  DATE_ADD(CURDATE(), INTERVAL 7 DAY), DATE_ADD(CURDATE(), INTERVAL 10 DAY),
  'pending',
  'Laptop needed for assignment submission week.',
  DATE_SUB(NOW(), INTERVAL 10 HOUR), DATE_SUB(NOW(), INTERVAL 10 HOUR)
);
SET @req_pending = LAST_INSERT_ID();

-- Rejected request history.
INSERT INTO borrow_requests (
  item_id, borrower_id, owner_id, start_date, end_date, status, message, created_at, updated_at
) VALUES (
  @item_cheongsam, @aik_id, @soon_id,
  DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_SUB(CURDATE(), INTERVAL 4 DAY),
  'rejected',
  'Need this outfit for formal dinner event.',
  DATE_SUB(NOW(), INTERVAL 6 DAY), DATE_SUB(NOW(), INTERVAL 5 DAY)
);
SET @req_rejected = LAST_INSERT_ID();

-- Cancelled request history.
INSERT INTO borrow_requests (
  item_id, borrower_id, owner_id, start_date, end_date, status, message, created_at, updated_at
) VALUES (
  @item_speaker, @soon_id, @aik_id,
  DATE_SUB(CURDATE(), INTERVAL 3 DAY), DATE_SUB(CURDATE(), INTERVAL 2 DAY),
  'cancelled',
  'No longer needed because event plan changed.',
  DATE_SUB(NOW(), INTERVAL 4 DAY), DATE_SUB(NOW(), INTERVAL 3 DAY)
);
SET @req_cancelled = LAST_INSERT_ID();

-- Transactions history aligned with request lifecycle.
INSERT INTO transactions (
  request_id,
  total_amount,
  rental_amount,
  deposit_amount,
  service_fee_amount,
  owner_payout_amount,
  deposit_refund_amount,
  payment_status,
  settlement_status,
  handover_code,
  return_code,
  paid_at,
  settled_at,
  created_at,
  updated_at
) VALUES
  (@req_completed_1, 174.00, 54.00, 120.00, 3.00, 51.00, 120.00, 'paid', 'pending', 'HDR-4102', 'RTN-4102', DATE_SUB(NOW(), INTERVAL 23 DAY), NULL, DATE_SUB(NOW(), INTERVAL 23 DAY), DATE_SUB(NOW(), INTERVAL 18 DAY)),
  (@req_completed_2, 380.00, 80.00, 300.00, 5.00, 75.00, 300.00, 'paid', 'pending', 'HDR-5129', 'RTN-5129', DATE_SUB(NOW(), INTERVAL 17 DAY), NULL, DATE_SUB(NOW(), INTERVAL 17 DAY), DATE_SUB(NOW(), INTERVAL 14 DAY)),
  (@req_in_use, 264.00, 104.00, 160.00, 6.00, 98.00, 0.00, 'paid', 'pending', 'HDR-6721', NULL, DATE_SUB(NOW(), INTERVAL 3 DAY), NULL, DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_SUB(NOW(), INTERVAL 20 HOUR)),
  (@req_accepted, 615.00, 165.00, 450.00, 8.00, 157.00, 0.00, 'unpaid', 'pending', NULL, NULL, NULL, NULL, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 6 HOUR));

-- Reviews history (bidirectional feedback for completed requests).
INSERT INTO reviews (request_id, reviewer_id, reviewee_id, rating, comment, created_at) VALUES
  (@req_completed_1, @soon_id, @aik_id, 5, 'Item condition matched listing, smooth handover and return process.', DATE_SUB(NOW(), INTERVAL 18 DAY)),
  (@req_completed_1, @aik_id, @soon_id, 5, 'Borrower communicated clearly and returned on time.', DATE_SUB(NOW(), INTERVAL 18 DAY)),
  (@req_completed_2, @aik_id, @soon_id, 4, 'Projector worked well, pickup was easy and response was fast.', DATE_SUB(NOW(), INTERVAL 14 DAY)),
  (@req_completed_2, @soon_id, @aik_id, 5, 'Very careful borrower, equipment returned in excellent condition.', DATE_SUB(NOW(), INTERVAL 14 DAY));

-- Community seed users (one user per supported location).
INSERT INTO users (email, password_hash, name, phone, location, kyc_status, avatar_url) VALUES
  ('community.johor@borrowease.local', @community_hash, 'Aiman Johor', '01310000001', 'Johor', 'verified', NULL),
  ('community.kedah@borrowease.local', @community_hash, 'Balqis Kedah', '01310000002', 'Kedah', 'verified', NULL),
  ('community.kelantan@borrowease.local', @community_hash, 'Chong Kelantan', '01310000003', 'Kelantan', 'verified', NULL),
  ('community.melaka@borrowease.local', @community_hash, 'Dina Melaka', '01310000004', 'Melaka', 'verified', NULL),
  ('community.negerisembilan@borrowease.local', @community_hash, 'Ehsan Negeri', '01310000005', 'Negeri Sembilan', 'verified', NULL),
  ('community.pahang@borrowease.local', @community_hash, 'Farah Pahang', '01310000006', 'Pahang', 'verified', NULL),
  ('community.penang@borrowease.local', @community_hash, 'Gan Penang', '01310000007', 'Penang', 'verified', NULL),
  ('community.perak@borrowease.local', @community_hash, 'Haziq Perak', '01310000008', 'Perak', 'verified', NULL),
  ('community.perlis@borrowease.local', @community_hash, 'Ivy Perlis', '01310000009', 'Perlis', 'verified', NULL),
  ('community.sabah@borrowease.local', @community_hash, 'Jason Sabah', '01310000010', 'Sabah', 'verified', NULL),
  ('community.sarawak@borrowease.local', @community_hash, 'Kamal Sarawak', '01310000011', 'Sarawak', 'verified', NULL),
  ('community.selangor@borrowease.local', @community_hash, 'Lina Selangor', '01310000012', 'Selangor', 'verified', NULL),
  ('community.terengganu@borrowease.local', @community_hash, 'Mira Terengganu', '01310000013', 'Terengganu', 'verified', NULL),
  ('community.kualalumpur@borrowease.local', @community_hash, 'Nabil KL', '01310000014', 'Kuala Lumpur', 'verified', NULL),
  ('community.putrajaya@borrowease.local', @community_hash, 'Ong Putrajaya', '01310000015', 'Putrajaya', 'verified', NULL),
  ('community.labuan@borrowease.local', @community_hash, 'Pia Labuan', '01310000016', 'Labuan', 'verified', NULL);

-- One community post per location.
INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Johor friends, need a foldable table for campus booth tomorrow. Borrow 1 day only.', NULL
FROM users WHERE email = 'community.johor@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Anyone in Kedah can lend a digital piano for weekend practice?', NULL
FROM users WHERE email = 'community.kedah@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Kelantan area: need pressure washer this Sunday for car wash. Self pickup ok.', NULL
FROM users WHERE email = 'community.kelantan@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Need city bike in Melaka for 2 days. Will return on time.', NULL
FROM users WHERE email = 'community.melaka@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Negeri Sembilan students, can borrow IELTS book for 1 week? Exam soon.', NULL
FROM users WHERE email = 'community.negerisembilan@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Need bean bag in Pahang this Saturday for quick photoshoot setup.', NULL
FROM users WHERE email = 'community.pahang@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Penang friends, looking for portable speaker tonight for birthday gathering.', NULL
FROM users WHERE email = 'community.penang@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Perak students, need laptop for assignment week (about 3 days).', NULL
FROM users WHERE email = 'community.perak@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Perlis parents, can borrow child car seat this weekend for family trip?', NULL
FROM users WHERE email = 'community.perlis@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Sabah campers, need 4-person tent for 2 nights. Pickup and return by schedule.', NULL
FROM users WHERE email = 'community.sabah@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Sarawak area, looking for projector this Friday evening for short presentation.', NULL
FROM users WHERE email = 'community.sarawak@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Selangor: need power drill for shelf installation, one day use only.', NULL
FROM users WHERE email = 'community.selangor@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Terengganu friends, need foldable table for family event this Friday night.', NULL
FROM users WHERE email = 'community.terengganu@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'KL friends, need cheongsam to borrow for dinner function this weekend.', NULL
FROM users WHERE email = 'community.kualalumpur@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Putrajaya drivers, need jump starter for emergency standby this week.', NULL
FROM users WHERE email = 'community.putrajaya@borrowease.local';

INSERT INTO community_posts (user_id, content, image_url)
SELECT id, 'Labuan students, any architecture reference books to borrow this month?', NULL
FROM users WHERE email = 'community.labuan@borrowease.local';

COMMIT;
