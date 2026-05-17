BorrowEase / Crowdsourced Borrowing App

Project Overview
- BorrowEase is a peer-to-peer item borrowing and short-term rental mobile application with an admin backend. It supports listing items, search and favourites, borrow requests, payment/deposit handling, handover evidence, in-app chat, reviews, reporting, KYC verification, and admin moderation.

Tech Stack
- Frontend: Flutter (Dart)
- Backend: Node.js + Express
- Database: MySQL
- Auth & Security: JWT (jsonwebtoken), bcryptjs
- File uploads: Multer
- Frontend HTTP client: Dio
- Email: Nodemailer

Key Features (Summary)
- User registration, login, password reset via OTP email
- JWT-based authentication with protected routes; frontend persists tokens in SharedPreferences
- Create, edit and remove item listings with image/video uploads, categories and location data
- Full borrow request lifecycle: pending → accepted/rejected → handover → in_use → return_pending → completed
- Transactions and deposit tracking, delayed settlement policy, handover/return codes and photo evidence
- In-app chat, ratings & reviews, favourites, and reporting system
- KYC submission and admin approval, admin dashboards and moderation tools
- Community posts with nearby filtering

Project Structure (brief)
- backend/: Express API implementation; server entry point is backend/src/server.js
- frontend/: Flutter mobile app; entry point is frontend/lib/main.dart
- schema.sql: MySQL schema and migration scripts

Quick Start (short guide)
1) Prepare MySQL and run `schema.sql` to create the database schema.
2) Backend
   - cd into `backend/`, copy `.env.example` to `.env` and fill in DB credentials, `JWT_SECRET`, and email settings.
   - Install dependencies:

```bash
cd backend
npm install
```

   - Start the API server:

```bash
npm run dev
# or
npm start
```

   - Seed/reset sample data (optional):

```bash
npm run seed:reset
```

3) Frontend
   - cd into `frontend/` and ensure the Flutter SDK is installed.
   - Run the app:

```bash
cd frontend
flutter run
```

Important Environment Variables (examples)
- `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
- `JWT_SECRET`
- `ADMIN_EMAILS`, `DEFAULT_ADMIN_EMAIL`, `DEFAULT_ADMIN_USERNAME`
- Email provider settings (used for OTP email sending)

Implementation Notes
- The backend issues JWTs in `backend/src/routes/auth.js` via `jwt.sign()` and validates them in `backend/src/middleware/auth.js` using `jwt.verify()`.
- The frontend API client (`frontend/lib/services/api_client.dart`) persists the token in SharedPreferences and attaches it as `Authorization: Bearer <token>` on outgoing requests.
- Password reset uses an email OTP flow (not JWT). Tokens issued at registration/login expire after 7 days by default.

Next Suggestions (optional)
- Add screenshots or a demo video under the root `pictures/` folder and link them in this README.
- Include example API requests and a short FAQ section.

See the backend and frontend entry points for details: [backend/src/server.js](backend/src/server.js#L1) and [frontend/lib/main.dart](frontend/lib/main.dart#L1).