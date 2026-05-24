# GitHub Actions Auto-Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tự động deploy lên VPS mỗi khi push code lên branch `main` — git pull + rebuild Docker containers qua SSH.

**Architecture:** GitHub Actions lắng nghe event `push` trên `main`, dùng `appleboy/ssh-action@v1` SSH vào VPS, chạy `git pull` và `docker compose up --build -d`. Không có bước test hay build trên runner — toàn bộ build xảy ra trên server.

**Tech Stack:** GitHub Actions, appleboy/ssh-action@v1, Docker Compose, SSH

---

### Task 1: Tạo GitHub Actions workflow file

**Files:**
- Create: `.github/workflows/deploy.yml`

- [ ] **Step 1: Tạo thư mục và file workflow**

```bash
mkdir -p .github/workflows
```

Tạo file `.github/workflows/deploy.yml` với nội dung sau:

```yaml
name: Deploy to VPS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VPS_HOST }}
          username: root
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd ~/mern-todo-app
            git pull origin main
            docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d
```

- [ ] **Step 2: Commit workflow file**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: add GitHub Actions auto-deploy workflow"
```

---

### Task 2: Thêm GitHub Secrets

**Thực hiện thủ công trên GitHub UI — không có file nào thay đổi.**

- [ ] **Step 1: Mở trang Secrets của repo**

Truy cập:
```
https://github.com/quandevhub/mern-todo-app/settings/secrets/actions
```

- [ ] **Step 2: Tạo secret `VPS_HOST`**

Nhấn **New repository secret**:
- Name: `VPS_HOST`
- Value: `152.42.243.18`

Nhấn **Add secret**.

- [ ] **Step 3: Tạo secret `VPS_SSH_KEY`**

Nhấn **New repository secret**:
- Name: `VPS_SSH_KEY`
- Value: Toàn bộ nội dung file `ssh-key-demo` (private key), bao gồm cả dòng header và footer:

```
-----BEGIN OPENSSH PRIVATE KEY-----
...nội dung key...
-----END OPENSSH PRIVATE KEY-----
```

Cách đọc nội dung key trên máy local:
```bash
cat /d/Devops/ssh/ssh-key-demo
```

Copy toàn bộ output và paste vào ô Value. Nhấn **Add secret**.

- [ ] **Step 4: Xác nhận 2 secrets đã tồn tại**

Trang Secrets phải hiện:
```
VPS_HOST     Updated just now
VPS_SSH_KEY  Updated just now
```

---

### Task 3: Xác nhận VPS sẵn sàng nhận deploy

**Thực hiện thủ công trên VPS.**

- [ ] **Step 1: Kiểm tra SSH key đã có trong authorized_keys**

SSH vào server:
```bash
ssh -i /d/Devops/ssh/ssh-key-demo root@152.42.243.18
```

Trên server:
```bash
cat ~/.ssh/authorized_keys
```

Expected: phải có đúng 1 dòng chứa public key (bắt đầu bằng `ssh-rsa` hoặc `ecdsa-sha2-nistp256` hoặc `ssh-ed25519`).

- [ ] **Step 2: Kiểm tra repo đã clone và đúng remote**

```bash
cd ~/mern-todo-app
git remote -v
```

Expected:
```
origin  https://github.com/quandevhub/mern-todo-app.git (fetch)
origin  https://github.com/quandevhub/mern-todo-app.git (push)
```

- [ ] **Step 3: Kiểm tra docker compose hoạt động**

```bash
docker-compose version
# hoặc
docker compose version
```

Expected: in ra version (v2.x.x). Nếu lỗi, cài lại theo hướng dẫn trong conversation.

---

### Task 4: Trigger thử và verify pipeline

- [ ] **Step 1: Push workflow file lên GitHub**

Trên máy local:
```bash
git push origin main
```

- [ ] **Step 2: Mở GitHub Actions để theo dõi**

Truy cập:
```
https://github.com/quandevhub/mern-todo-app/actions
```

Phải thấy 1 workflow run tên **Deploy to VPS** đang chạy (màu vàng = đang chạy).

- [ ] **Step 3: Xem log chi tiết**

Nhấn vào workflow run → nhấn job **deploy** → nhấn step **Deploy via SSH**.

Log phải chứa các dòng tương tự:
```
Already up to date.
[+] Running 3/3
 ✔ Container mern-todo-app-mongodb-1  Started
 ✔ Container mern-todo-app-backend-1  Started
 ✔ Container mern-todo-app-frontend-1 Started
```

- [ ] **Step 4: Xác nhận workflow PASS (màu xanh)**

Nếu workflow có dấu ✅ xanh → deploy thành công.

Nếu ❌ đỏ → xem log lỗi ở Step 3 để debug. Lỗi thường gặp:
- `Permission denied (publickey)` → `VPS_SSH_KEY` paste thiếu hoặc sai
- `Host key verification failed` → thêm `known_hosts` (xem phần debug bên dưới)

- [ ] **Step 5: Verify app vẫn chạy bình thường trên VPS**

Mở browser:
```
http://152.42.243.18
```

App phải load bình thường.

---

## Debug: Host key verification failed

Nếu gặp lỗi `Host key verification failed`, thêm option `known_hosts` vào workflow:

```yaml
- name: Deploy via SSH
  uses: appleboy/ssh-action@v1
  with:
    host: ${{ secrets.VPS_HOST }}
    username: root
    key: ${{ secrets.VPS_SSH_KEY }}
    known_hosts: ${{ secrets.VPS_KNOWN_HOSTS }}
    script: |
      cd ~/mern-todo-app
      git pull origin main
      docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d
```

Lấy giá trị cho secret `VPS_KNOWN_HOSTS` bằng lệnh trên máy local:
```bash
ssh-keyscan 152.42.243.18
```

Copy toàn bộ output, tạo thêm secret `VPS_KNOWN_HOSTS` trên GitHub với giá trị đó.
