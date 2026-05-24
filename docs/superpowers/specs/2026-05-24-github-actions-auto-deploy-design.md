# Design: GitHub Actions Auto-Deploy to VPS

**Date:** 2026-05-24
**Status:** Approved

## Goal

Khi developer push code lên branch `main`, server VPS tự động kéo code mới về và rebuild Docker containers — không cần SSH thủ công vào server.

## Approach

Dùng `appleboy/ssh-action` — GitHub Actions marketplace action phổ biến, cấu hình đơn giản, không cần script SSH thủ công.

## Flow

```
Push to main
     │
     ▼
GitHub Actions Job: deploy (runs-on: ubuntu-latest)
     │
     └─ appleboy/ssh-action@v1
           │
           ├─ SSH vào root@VPS_HOST
           ├─ cd ~/mern-todo-app
           ├─ git pull origin main
           └─ docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d
```

## File tạo mới

### `.github/workflows/deploy.yml`

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

## GitHub Secrets cần tạo

| Secret | Giá trị |
|---|---|
| `VPS_HOST` | IP của VPS (`152.42.243.18`) |
| `VPS_SSH_KEY` | Nội dung file private key (`ssh-key-demo`) |

Tạo tại: **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**

## Setup VPS (một lần)

Public key (`ssh-key-demo.pub`) phải có trong `~/.ssh/authorized_keys` trên server. Vì đang dùng key này để SSH, bước này đã hoàn tất.

Kiểm tra:
```bash
cat ~/.ssh/authorized_keys
```

## Không có trong scope

- Chạy test trước khi deploy
- Rollback tự động khi deploy thất bại
- Notification (Slack, email) khi deploy xong
- Multi-environment (staging, production riêng biệt)
