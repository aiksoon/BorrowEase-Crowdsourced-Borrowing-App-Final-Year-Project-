# 🔄 BorrowEase — Crowdsourced P2P Borrowing App

[![Flutter](https://img.shields.io/badge/Frontend-Flutter%20%7C%20Dart-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Backend-Node.js%20%7C%20Express-339933?logo=node.js&logoColor=white)](https://nodejs.org)
[![MySQL](https://img.shields.io/badge/Database-MySQL-4479A1?logo=mysql&logoColor=white)](https://www.mysql.com)
[![License](https://img.shields.io/badge/Academic%20Project-FYP-orange)](#)

> **BorrowEase** is a peer-to-peer (P2P) item borrowing and short-term rental mobile application designed to encourage sharing and reduce over-buying in local communities. The platform connects lenders holding idle items with borrowers who need temporary access, managed seamlessly via an intelligent workflow and an admin moderation backend.

---

## 🚀 Key Features

### 📱 Mobile Frontend (Borrowers & Lenders)
* **Secure Authentication:** JWT-based login/register with secure client-side storage (`SharedPreferences`) and OTP-based password reset via email.
* **Smart Marketplace:** Create, edit, and remove item listings with media uploads (images/videos), category tagging, and location-based filtering.
* **Full Rental Lifecycle:** End-to-end transaction flow tracking:
  $$\text{Pending} \rightarrow \text{Accepted} \rightarrow \text{Handover} \rightarrow \text{In Use} \rightarrow \text{Return Pending} \rightarrow \text{Completed}$$
* **Trust & Security:** Identity verification via **KYC submission**, digital escrow deposit tracking with delayed settlement policies, and mandatory handover/return photo evidence.
* **Social & Discovery:** Real-time in-app chat, user ratings & reviews, item favoriting, and location-aware community posts.

### 💻 Web Admin Backend
* **User & Content Moderation:** Review and approve/reject pending KYC submissions.
* **Platform Oversight:** Monitor transactions, manage system reports, and moderate marketplace listings.

---

## 🛠️ Tech Stack

| Layer | Technology | Key Libraries / Usage |
| :--- | :--- | :--- |
| **Frontend** | Flutter (Dart) | `Dio` (HTTP client), `SharedPreferences` (Token persistence) |
| **Backend** | Node.js (Express) | `Multer` (File uploads), `Nodemailer` (OTP emails) |
| **Database** | MySQL | `schema.sql` (Relational schema & indices) |
| **Security** | JWT & Bcrypt | `jsonwebtoken` (Protected routes), `bcryptjs` (Password hashing) |

---

## 📁 Project Structure

```text
BorrowEase/
├── backend/               # Node.js + Express API Implementation
│   └── src/
│       ├── middleware/    # Auth & validation guards (e.g., auth.js)
│       ├── routes/        # API Endpoints (auth, items, chats, etc.)
│       └── server.js      # Backend entry point
├── frontend/              # Flutter Mobile Application
│   └── lib/
│       ├── services/      # api_client.dart (Attached Bearer Tokens)
│       └── main.dart      # Flutter entry point
└── schema.sql             # Database schema & initial migration scripts
