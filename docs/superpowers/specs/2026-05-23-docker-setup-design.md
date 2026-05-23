# Docker Setup Design — MERN Todo App

**Date:** 2026-05-23  
**Status:** Approved

---

## Overview

Đóng gói toàn bộ MERN stack (MongoDB, Express, React, Node.js) bằng Docker sử dụng **docker-compose override pattern** — hỗ trợ cả môi trường Development (hot-reload) và Production (optimized build + Nginx).

---

## Architecture

```
                    ┌─────────────────────────────────┐
                    │        Docker Network            │
                    │                                  │
  Browser ──────────┤  frontend (React / Nginx)        │
  :3000 (dev)       │       │                          │
  :80   (prod)      │       │ proxy /api               │
                    │       ▼                          │
                    │  backend (Node/Express :8000)    │
                    │       │                          │
                    │       │ mongoose                 │
                    │       ▼                          │
                    │  mongodb (:27017)                │
                    │       │                          │
                    │       ▼                          │
                    │  volume: mongodb_data            │
                    └─────────────────────────────────┘
```

---

## File Structure

```
mern-todo-app/
├── docker-compose.yml           # Base: MongoDB + shared network/volumes
├── docker-compose.dev.yml       # Dev overrides: hot-reload, src mounts
├── docker-compose.prod.yml      # Prod overrides: optimized builds
├── .env.example                 # Template biến môi trường
│
├── backend/
│   ├── Dockerfile               # Multi-stage: development | production
│   └── .dockerignore
│
└── frontend/
    ├── Dockerfile               # Multi-stage: development | build | production
    ├── nginx.conf               # Nginx: serve SPA + proxy /api → backend
    └── .dockerignore
```

---

## Services

### MongoDB
- Image: `mongo:7.0`
- Volume: `mongodb_data:/data/db` (persist)
- Dev: expose port 27017 ra host (để dùng Compass)
- Prod: không expose ra ngoài

### Backend (Node.js/Express)
- Base image: `node:22-alpine`
- **Dev stage:** `node --watch server.js` (hot-reload built-in Node 22)
- **Prod stage:** `node server.js`
- Port: 8000
- Env: `MONGO_URI=mongodb://mongodb:27017/todo`

### Frontend (React)
- **Dev stage:** `npm start` (React dev server, port 3000), mount `src/` và `public/` cho hot-reload
- **Build stage:** `npm run build` với `REACT_APP_API_URL=/api`
- **Prod stage:** Nginx serve `/app/build`, proxy `/api` → `backend:8000`
- Dev port: 3000 | Prod port: 80

---

## Axios Config Change

File `frontend/src/Axios/axios.js` cần sửa để hỗ trợ env var:

```js
// Trước
baseURL: "http://localhost:8000/api"

// Sau
baseURL: process.env.REACT_APP_API_URL || "http://localhost:8000/api"
```

- Dev: `REACT_APP_API_URL` không set → dùng `http://localhost:8000/api`
- Prod: `REACT_APP_API_URL=/api` → Nginx proxy nội bộ

---

## Commands

```bash
# Development (hot-reload)
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# Production (detached)
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d

# Dừng
docker-compose -f docker-compose.yml -f docker-compose.dev.yml down

# Xóa cả volumes (reset DB)
docker-compose -f docker-compose.yml -f docker-compose.dev.yml down -v
```

---

## Ports Summary

| Service  | Dev  | Prod         |
|----------|------|--------------|
| Frontend | 3000 | 80           |
| Backend  | 8000 | 8000         |
| MongoDB  | 27017| không expose |

---

## Volumes

| Volume        | Mount                       | Mục đích               |
|---------------|-----------------------------|------------------------|
| `mongodb_data`| `/data/db`                  | Persist DB data        |
| `./backend`   | `/app` (dev only)           | Hot-reload source      |
| `./frontend/src` | `/app/src` (dev only)    | Hot-reload source      |
| `./frontend/public` | `/app/public` (dev only) | Hot-reload assets  |
