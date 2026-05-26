# Docker Setup Implementation Plan

**Goal:** Đóng gói toàn bộ MERN Todo App (MongoDB + Express backend + React frontend) bằng Docker với docker-compose override pattern hỗ trợ cả môi trường Dev và Prod.

**Architecture:** Base `docker-compose.yml` định nghĩa MongoDB và shared network/volumes. `docker-compose.dev.yml` override thêm hot-reload và source mounts. `docker-compose.prod.yml` override build optimized images với Nginx serve frontend và proxy API.

**Tech Stack:** Docker, docker-compose v3.8, Node 22 Alpine, Nginx Alpine, MongoDB 7.0

---

## File Map

| File | Action | Mục đích |
|------|--------|---------|
| `backend/Dockerfile` | Create | Multi-stage: development (node --watch) + production (node) |
| `backend/.dockerignore` | Create | Loại trừ node_modules, .env khỏi build context |
| `frontend/Dockerfile` | Create | Multi-stage: development (npm start) + build + production (nginx) |
| `frontend/nginx.conf` | Create | Serve React SPA + proxy /api → backend:8000 |
| `frontend/.dockerignore` | Create | Loại trừ node_modules, build khỏi build context |
| `docker-compose.yml` | Create | Base: mongodb service, volume, network |
| `docker-compose.dev.yml` | Create | Dev: backend + frontend với hot-reload |
| `docker-compose.prod.yml` | Create | Prod: backend + frontend optimized |
| `.env.example` | Create | Template biến môi trường |
| `frontend/src/Axios/axios.js` | Modify | Dùng REACT_APP_API_URL env var |

---

### Task 1: backend/.dockerignore và backend/Dockerfile

**Files:**
- Create: `backend/.dockerignore`
- Create: `backend/Dockerfile`

- [ ] **Step 1: Tạo backend/.dockerignore**

```
node_modules
.env
npm-debug.log
```

- [ ] **Step 2: Tạo backend/Dockerfile**

```dockerfile
FROM node:22-alpine AS base
WORKDIR /app
COPY package.json .

FROM base AS development
RUN npm install
COPY . .
CMD ["node", "--watch", "server.js"]

FROM base AS production
RUN npm install --omit=dev
COPY . .
CMD ["node", "server.js"]
```

- [ ] **Step 3: Verify cấu trúc**

Kiểm tra file tồn tại:
```powershell
Test-Path "backend/Dockerfile"
Test-Path "backend/.dockerignore"
```
Expected: True, True

---

### Task 2: frontend/.dockerignore, frontend/nginx.conf, frontend/Dockerfile

**Files:**
- Create: `frontend/.dockerignore`
- Create: `frontend/nginx.conf`
- Create: `frontend/Dockerfile`

- [ ] **Step 1: Tạo frontend/.dockerignore**

```
node_modules
build
.env
npm-debug.log
```

- [ ] **Step 2: Tạo frontend/nginx.conf**

```nginx
server {
    listen 80;

    location / {
        root   /usr/share/nginx/html;
        index  index.html;
        try_files $uri $uri/ /index.html;
    }

    location /api {
        proxy_pass         http://backend:8000/api;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
}
```

- [ ] **Step 3: Tạo frontend/Dockerfile**

```dockerfile
FROM node:22-alpine AS development
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
ENV CHOKIDAR_USEPOLLING=true
ENV WATCHPACK_POLLING=true
CMD ["npm", "start"]

FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* yarn.lock* ./
RUN npm install
COPY . .
ARG REACT_APP_API_URL=/api
ENV REACT_APP_API_URL=$REACT_APP_API_URL
RUN npm run build

FROM nginx:alpine AS production
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

- [ ] **Step 4: Verify cấu trúc**

```powershell
Test-Path "frontend/Dockerfile"
Test-Path "frontend/nginx.conf"
Test-Path "frontend/.dockerignore"
```
Expected: True, True, True

---

### Task 3: docker-compose.yml (base)

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Tạo docker-compose.yml**

```yaml
version: '3.8'

services:
  mongodb:
    image: mongo:7.0
    restart: unless-stopped
    volumes:
      - mongodb_data:/data/db
    networks:
      - app-network

volumes:
  mongodb_data:

networks:
  app-network:
    driver: bridge
```

---

### Task 4: docker-compose.dev.yml

**Files:**
- Create: `docker-compose.dev.yml`

- [ ] **Step 1: Tạo docker-compose.dev.yml**

```yaml
services:
  mongodb:
    ports:
      - "27018:27017"

  backend:
    build:
      context: ./backend
      target: development
    ports:
      - "8000:8000"
    volumes:
      - ./backend:/app
      - /app/node_modules
    env_file:
      - ./backend/.env
    environment:
      - MONGO_URI=mongodb://mongodb:27017/todo
    depends_on:
      - mongodb
    networks:
      - app-network
    restart: unless-stopped

  frontend:
    build:
      context: ./frontend
      target: development
    ports:
      - "3000:3000"
    volumes:
      - ./frontend/src:/app/src
      - ./frontend/public:/app/public
    environment:
      - REACT_APP_API_URL=http://localhost:8000/api
    depends_on:
      - backend
    networks:
      - app-network
    stdin_open: true
    tty: true
```

---

### Task 5: docker-compose.prod.yml

**Files:**
- Create: `docker-compose.prod.yml`

- [ ] **Step 1: Tạo docker-compose.prod.yml**

```yaml
services:
  mongodb:
    restart: always

  backend:
    build:
      context: ./backend
      target: production
    ports:
      - "8000:8000"
    env_file:
      - ./backend/.env
    environment:
      - MONGO_URI=mongodb://mongodb:27017/todo
    depends_on:
      - mongodb
    networks:
      - app-network
    restart: always

  frontend:
    build:
      context: ./frontend
      target: production
      args:
        - REACT_APP_API_URL=/api
    ports:
      - "80:80"
    depends_on:
      - backend
    networks:
      - app-network
    restart: always
```

---

### Task 6: .env.example

**Files:**
- Create: `.env.example`

- [ ] **Step 1: Tạo .env.example**

```env
# MongoDB
MONGO_URI=mongodb://mongodb:27017/todo

# JWT
JWT_SECRET=change_me_in_production

# Gmail (dùng cho chức năng quên mật khẩu)
GMAIL_USERNAME=your_email@gmail.com
GMAIL_PASSWORD=your_app_password

# Port backend
PORT=8000
```

- [ ] **Step 2: Copy thành .env thực tế (nếu chưa có ở root)**

```powershell
if (-not (Test-Path ".env")) { Copy-Item ".env.example" ".env" }
```

---

### Task 7: Sửa frontend/src/Axios/axios.js

**Files:**
- Modify: `frontend/src/Axios/axios.js`

- [ ] **Step 1: Sửa baseURL dùng env var**

Nội dung mới của file:
```js
import axios from "axios"
const instance = axios.create({
    baseURL: process.env.REACT_APP_API_URL || "http://localhost:8000/api"
})
export default instance
```

---

### Task 8: Kiểm tra toàn bộ — chạy Dev

- [ ] **Step 1: Đảm bảo Docker Desktop đang chạy**

```powershell
docker info
```
Expected: Server info không có lỗi

- [ ] **Step 2: Build và chạy Dev**

```powershell
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

Expected output (theo thứ tự):
```
mongodb    | "msg":"Waiting for connections"
backend    | DB Connected
backend    | Listening on localhost:8000
frontend   | Compiled successfully!
```

- [ ] **Step 3: Kiểm tra app hoạt động**

Mở trình duyệt: http://localhost:3000  
Kết quả mong đợi: Trang Login hiển thị, đăng ký/đăng nhập được

- [ ] **Step 4: Kiểm tra hot-reload**

Sửa bất kỳ text nào trong `frontend/src/components/Login.jsx`, lưu file.  
Expected: Trình duyệt tự reload, thấy thay đổi ngay lập tức.

- [ ] **Step 5: Dừng**

```powershell
docker-compose -f docker-compose.yml -f docker-compose.dev.yml down
```

---

### Task 9: Kiểm tra toàn bộ — chạy Prod

- [ ] **Step 1: Build và chạy Prod**

```powershell
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d
```

- [ ] **Step 2: Kiểm tra containers đang chạy**

```powershell
docker-compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

Expected: 3 services (mongodb, backend, frontend) đều `running`

- [ ] **Step 3: Kiểm tra app**

Mở trình duyệt: http://localhost  
Kết quả mong đợi: Trang Login hiển thị, API hoạt động qua Nginx proxy

- [ ] **Step 4: Dừng**

```powershell
docker-compose -f docker-compose.yml -f docker-compose.prod.yml down
```
