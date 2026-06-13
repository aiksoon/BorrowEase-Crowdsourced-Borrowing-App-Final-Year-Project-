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

## 🌐 API Architecture

BorrowEase follows a RESTful client-server architecture where the Flutter mobile application communicates with the Express.js backend through secured JWT-protected APIs.

```text
Flutter App
      │
      ▼
 REST API (Dio)
      │
      ▼
Node.js + Express Backend
      │
      ▼
     MySQL
```
---

## 🔌 Core Backend API Modules

| Module           | Purpose                         | Main Endpoints                                                                         |
| ---------------- | ------------------------------- | -------------------------------------------------------------------------------------- |
| Authentication   | User registration and login     | `POST /auth/register`, `POST /auth/login`, `POST /auth/reset-password`, `GET /auth/me` |
| User Management  | User profile operations         | `GET /users/profile`, `POST /users/update`                                             |
| Item Management  | Marketplace listings            | `GET /items`, `POST /items/create`, `PUT /items/:id`, `DELETE /items/:id`              |
| Borrow Requests  | Borrowing workflow              | `GET /requests`, `POST /requests/create`, `PUT /requests/:id/status`                   |
| Transactions     | Rental transaction records      | `GET /transactions`, `POST /transactions/record`                                       |
| Chats            | User messaging                  | `GET /chats`, `POST /chats/message`                                                    |
| Reviews          | User feedback and ratings       | `GET /reviews`, `POST /reviews/create`                                                 |
| Reports          | Content and user reporting      | `GET /reports`, `POST /reports/create`                                                 |
| KYC Verification | Identity verification           | `GET /kyc/status`, `POST /kyc/verify`                                                  |
| Favorites        | Saved items management          | `GET /favorites`, `POST /favorites/add`, `DELETE /favorites/:id`                       |
| Uploads          | File and media uploads          | `POST /uploads`                                                                        |
| Community        | Community discussions and posts | `GET /community/posts`, `POST /community/posts`                                        |
| Admin Dashboard  | Administrative operations       | `GET /admin/dashboard`, `GET /admin/users`, `GET /admin/reports`                       |

---

## 📧 External Service Integration

### Gmail SMTP Service

BorrowEase integrates Gmail SMTP through Nodemailer to support account-related email communications.

#### Usage

* OTP verification emails
* Password reset requests
* Account recovery notifications

#### Features

* Automated OTP generation and delivery
* Secure email communication
* Password recovery workflow support

---

## 🔐 Security Features

* JWT-based authentication and authorization
* Secure password hashing using Bcrypt
* Protected API routes through authentication middleware
* OTP-based password reset mechanism
* KYC identity verification workflow
* Role-based administrative access control
* Secure token persistence via SharedPreferences

---

## 📊 System Modules Overview

```text
Authentication
├── Register
├── Login
├── JWT Validation
└── Password Reset

Marketplace
├── Item Listings
├── Borrow Requests
├── Transactions
└── Favorites

Social Features
├── Chats
├── Reviews
├── Reports
└── Community Posts

Trust & Safety
├── KYC Verification
├── Admin Moderation
└── User Reporting
```


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
