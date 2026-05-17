# BackendNodejs

Minimal Express + MySQL API for BorrowEase.

## Setup
1) Copy .env.example to .env and fill DB credentials and JWT_SECRET.
2) Install deps: `npm install`
3) Run dev: `npm run dev` (nodemon) or `npm start`.

## Endpoints
- GET /health
- POST /auth/register {email,password,name,phone?,location?}
- POST /auth/login {email,password}  // email 可填邮箱或用户名
- GET /auth/me (auth)
- GET /items (public)
- POST /items (auth)
- POST /requests (auth)
- GET /requests?role=owner|borrower (auth, optional role; omit to get all related to current user)
- PATCH /requests/:id/status {next_status} (auth)

Status flow: pending -> accepted/rejected/cancelled -> handover -> in_use -> completed.
