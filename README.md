# MERN Todo App — DevOps Full Stack

Ứng dụng Todo full-stack (MongoDB + Express + React + Node.js) được đóng gói hoàn chỉnh với Docker, CI/CD tự động qua GitHub Actions, hệ thống monitoring Grafana/Prometheus, và tự động hóa hạ tầng bằng Terraform + Ansible.

---

## Mục lục

1. [Tổng quan kiến trúc](#1-tổng-quan-kiến-trúc)
2. [Tech Stack](#2-tech-stack)
3. [Cấu trúc project](#3-cấu-trúc-project)
4. [Cài đặt biến môi trường](#4-cài-đặt-biến-môi-trường)
5. [Chạy trên Localhost (không Docker)](#5-chạy-trên-localhost-không-docker)
6. [Docker — Môi trường Development](#6-docker--môi-trường-development)
7. [Docker — Môi trường Production](#7-docker--môi-trường-production)
8. [CI/CD — GitHub Actions Auto-Deploy](#8-cicd--github-actions-auto-deploy)
9. [Monitoring — Grafana + Prometheus](#9-monitoring--grafana--prometheus)
10. [Infrastructure — Terraform (Tạo VPS)](#10-infrastructure--terraform-tạo-vps)
11. [Automation — Ansible (Deploy lên VPS)](#11-automation--ansible-deploy-lên-vps)
12. [Flow triển khai tổng thể](#12-flow-triển-khai-tổng-thể)

---

## 1. Tổng quan kiến trúc

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Network: app-network              │
│                                                                 │
│   Browser                                                       │
│   :80 (prod) ──► frontend (React / Nginx) ──► backend :8000    │
│   :3000 (dev)                                     │            │
│                                                   ▼            │
│                                              mongodb :27017     │
└─────────────────────────────────────────────────────────────────┘

CI/CD:  GitHub push → GitHub Actions → SSH → VPS → docker-compose up

Monitoring:  Prometheus → scrape → Node Exporter (CPU/RAM)
                       → probe → Blackbox Exporter (Domain/SSL)
             Grafana   → datasource → Prometheus → Dashboard

IaC:    Terraform → tạo Droplet DigitalOcean
        Ansible   → SSH vào Droplet → cài Docker → deploy app
```

---

## 2. Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React 18, Axios |
| Backend | Node.js, Express, JWT, Mongoose |
| Database | MongoDB 7.0 |
| Container | Docker, Docker Compose v3.8 |
| Web Server | Nginx (production) |
| CI/CD | GitHub Actions (`appleboy/ssh-action`) |
| Monitoring | Prometheus, Grafana 12.1, Node Exporter, Blackbox Exporter |
| IaC | Terraform 1.15.4, DigitalOcean Provider v2.67.0 |
| Automation | Ansible |
| VPS | DigitalOcean sgp1 (Ubuntu 24.04, 1vCPU/1GB RAM) |

---

## 3. Cấu trúc project

```
mern-todo-app/
├── backend/                    # Node.js / Express API
│   ├── Dockerfile              # Multi-stage: dev + prod
│   ├── .env                    # Biến môi trường (KHÔNG commit)
│   └── src/
├── frontend/                   # React app
│   ├── Dockerfile              # Multi-stage: dev + build + prod(nginx)
│   ├── nginx.conf              # Serve SPA + proxy /api → backend
│   └── src/
├── monitoring/                 # Monitoring stack
│   ├── docker-compose.monitoring.yml
│   └── prometheus.yml
├── root/                       # IaC tools (chạy trong Docker container)
│   ├── terraform/
│   │   ├── main.tf             # Tạo Droplet DigitalOcean
│   │   └── terraform.tfvars   # Token + SSH key (KHÔNG commit)
│   └── ansible/
│       ├── hosts.ini           # Danh sách VPS targets
│       ├── install_vps.yml     # Playbook: cài Docker + deploy app
│       └── ssh-key-demo        # SSH private key (KHÔNG commit)
├── .github/workflows/
│   └── deploy.yml              # GitHub Actions auto-deploy
├── docker-compose.yml          # Base: mongodb + network
├── docker-compose.dev.yml      # Override: hot-reload dev
├── docker-compose.prod.yml     # Override: optimized prod build
├── .env.example                # Template biến môi trường
└── docs/superpowers/
    ├── plans/                  # Hướng dẫn chi tiết từng phần
    └── specs/                  # Design documents
```

---

## 4. Cài đặt biến môi trường

```bash
cp .env.example backend/.env
```

Chỉnh sửa `backend/.env`:

```env
MONGO_URI=mongodb://mongodb:27017/todo
JWT_SECRET=your_secret_key_here
GMAIL_USERNAME=your_email@gmail.com
GMAIL_PASSWORD=your_gmail_app_password
PORT=8000
```

> **Gmail App Password:** Google Account → Security → 2-Step Verification → App passwords

---

## 5. Chạy trên Localhost (không Docker)

Yêu cầu: Node.js >= 18, MongoDB đang chạy local.

**Backend:**
```bash
cd backend
npm install
npm run dev        # chạy trên :8000
```

**Frontend:**
```bash
cd frontend
npm install
npm start          # chạy trên :3000
```

Truy cập: `http://localhost:3000`

---

## 6. Docker — Môi trường Development

Hỗ trợ **hot-reload**: thay đổi code → tự động reload, không cần rebuild image.

```bash
# Khởi động
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d

# Xem logs
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f

# Dừng
docker compose -f docker-compose.yml -f docker-compose.dev.yml down
```

| Service | URL |
|---------|-----|
| Frontend (React) | http://localhost:3000 |
| Backend API | http://localhost:8000/api |
| MongoDB | localhost:27018 |

> Hướng dẫn chi tiết: [docs/superpowers/plans/2026-05-23-docker-setup.md](docs/superpowers/plans/2026-05-23-docker-setup.md)

---

## 7. Docker — Môi trường Production

Build optimized: React build tĩnh được serve bởi Nginx, Nginx proxy `/api` → backend.

```bash
# Build và khởi động
docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d

# Kiểm tra containers
docker ps

# Dừng
docker compose -f docker-compose.yml -f docker-compose.prod.yml down
```

| Service | URL |
|---------|-----|
| App (Frontend + API) | http://localhost:80 |
| Backend API (direct) | http://localhost:8000/api |

> Hướng dẫn chi tiết: [docs/superpowers/plans/2026-05-23-docker-setup.md](docs/superpowers/plans/2026-05-23-docker-setup.md)

---

## 8. CI/CD — GitHub Actions Auto-Deploy

Mỗi khi push lên branch `main`, GitHub Actions tự động SSH vào VPS, pull code mới và rebuild containers.

### Cài đặt một lần

**Bước 1:** Thêm secrets vào GitHub repository

Vào `Settings → Secrets and variables → Actions → New repository secret`:

| Secret | Giá trị |
|--------|---------|
| `VPS_HOST` | IP của VPS (vd: `167.71.22.100`) |
| `VPS_SSH_KEY` | Nội dung private key SSH (toàn bộ file, kể cả `-----BEGIN...`) |

**Bước 2:** Đảm bảo VPS đã clone repo

```bash
# SSH vào VPS lần đầu
ssh root@<VPS_IP>

# Clone repo
git clone https://github.com/quandevhub/mern-todo-app.git ~/mern-todo-app

# Tạo .env
cp ~/mern-todo-app/.env.example ~/mern-todo-app/backend/.env
# Chỉnh sửa .env với thông tin thực
```

### Trigger deploy

```bash
git add .
git commit -m "feat: your changes"
git push origin main
# → GitHub Actions tự động deploy lên VPS
```

Xem kết quả: `GitHub repo → Actions → Deploy to VPS`

> Hướng dẫn chi tiết: [docs/superpowers/plans/2026-05-24-github-actions-auto-deploy.md](docs/superpowers/plans/2026-05-24-github-actions-auto-deploy.md)

---

## 9. Monitoring — Grafana + Prometheus

Theo dõi CPU, RAM, disk, network và trạng thái domain/SSL certificate.

### Yêu cầu

Network `app-network` phải tồn tại (tạo khi chạy docker-compose app):
```bash
docker network ls | grep app-network
# Nếu chưa có:
docker network create app-network
```

### Khởi động monitoring stack

```bash
docker compose -f monitoring/docker-compose.monitoring.yml up -d
```

### Kiểm tra

```bash
docker ps --filter "name=prometheus" --filter "name=grafana" \
          --filter "name=host-node-exporter" --filter "name=host-blackbox"
```

### Truy cập

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3001 | admin / admin123 |
| Prometheus | http://localhost:9090 | — |
| Prometheus Targets | http://localhost:9090/targets | — |

### Cấu hình Grafana (lần đầu)

1. Đăng nhập Grafana tại `http://localhost:3001`
2. **Connections → Data sources → Add → Prometheus**
   - URL: `http://prometheus:9090`
   - Save & test
3. **Dashboards → Import** dashboard:
   - `1860` — Node Exporter Full (CPU, RAM, Disk, Network)
   - `13659` — Blackbox Exporter (Domain status, SSL cert expiry)

### Thêm domain cần theo dõi

Sửa `monitoring/prometheus.yml`, phần `targets` của job `blackbox`:
```yaml
static_configs:
  - targets:
      - https://your-domain.com
      - https://api.your-domain.com
```

Reload config (không cần restart):
```bash
curl -X POST http://localhost:9090/-/reload
```

> Hướng dẫn chi tiết: [docs/superpowers/plans/2026-05-27-grafana-prometheus-monitoring.md](docs/superpowers/plans/2026-05-27-grafana-prometheus-monitoring.md)

---

## 10. Infrastructure — Terraform (Tạo VPS)

Tự động tạo Droplet Ubuntu 24.04 trên DigitalOcean (Singapore, 1vCPU/1GB RAM).

### Yêu cầu

| Cần có | Cách lấy |
|--------|----------|
| DigitalOcean API Token | DO Dashboard → API → Generate New Token (Read + Write) |
| SSH Key fingerprint | DO Dashboard → Settings → Security → SSH Keys |

### Khởi động môi trường

```bash
# Chạy container Ubuntu làm môi trường
docker run -d -it --name ubuntu-ansible \
  -v ./root:/root \
  ubuntu:24.04

docker exec -it ubuntu-ansible bash
```

### Cài Terraform (bên trong container)

```bash
apt update && apt install -y unzip wget
cd /root/terraform
unzip terraform_1.15.4_linux_amd64.zip
mv terraform /usr/local/bin/
terraform version   # phải thấy "on linux_amd64"
```

> **Quan trọng:** Bắt buộc dùng bản `linux_amd64`. Bản 32-bit gây lỗi overflow với DigitalOcean API.

### Điền credentials

```bash
# Sửa file /root/terraform/terraform.tfvars
do_token="dop_v1_<your_api_token>"
ssh_key="<your_ssh_key_fingerprint>"
```

### Tạo VPS

```bash
cd /root/terraform
terraform init      # tải provider
terraform validate  # kiểm tra cú pháp
terraform plan      # xem trước thay đổi
terraform apply     # tạo VPS → ghi lại IP từ output
```

### Xóa VPS (khi không cần)

```bash
terraform destroy
```

> Hướng dẫn chi tiết: [docs/superpowers/plans/2026-05-27-terraform-ansible-infrastructure.md](docs/superpowers/plans/2026-05-27-terraform-ansible-infrastructure.md)

---

## 11. Automation — Ansible (Deploy lên VPS)

Tự động SSH vào VPS, cài Docker và deploy ứng dụng.

### Cài Ansible (bên trong container `ubuntu-ansible`)

```bash
apt install -y ansible
ansible --version
```

### Cập nhật IP VPS

Sau khi `terraform apply`, cập nhật IP vào `root/ansible/hosts.ini`:
```ini
[danh_sach_host]
<VPS_IP> ansible_user=root ansible_ssh_private_key_file=./ssh-key-demo
```

### Test kết nối

```bash
chmod 600 /root/ansible/ssh-key-demo
cd /root/ansible
ansible -i hosts.ini danh_sach_host -m ping
# Expected: "ping": "pong"
```

### Chạy playbook deploy

```bash
ansible-playbook -i hosts.ini install_vps.yml
```

Playbook sẽ tự động:
- Cài `docker.io` và `docker-compose`
- Clone repo về `/root/mern-todo-app`
- Tạo file `.env` cho backend
- Chạy `docker-compose up --build -d`

```
PLAY RECAP: ok=7   changed=6   unreachable=0   failed=0
```

> Hướng dẫn chi tiết: [docs/superpowers/plans/2026-05-27-terraform-ansible-infrastructure.md](docs/superpowers/plans/2026-05-27-terraform-ansible-infrastructure.md)

---

## 12. Flow triển khai tổng thể

```
Bước 1 — Localhost
  └─ npm install + npm start (frontend & backend riêng lẻ)

Bước 2 — Docker Desktop (Dev)
  └─ docker compose -f docker-compose.yml -f docker-compose.dev.yml up

Bước 3 — Docker Desktop (Prod, giống VPS)
  └─ docker compose -f docker-compose.yml -f docker-compose.prod.yml up

Bước 4 — Tạo VPS tự động (Terraform)
  └─ docker exec ubuntu-ansible → terraform apply → ghi lại IP

Bước 5 — Deploy lên VPS tự động (Ansible)
  └─ cập nhật hosts.ini → ansible-playbook install_vps.yml

Bước 6 — CI/CD (GitHub Actions)
  └─ git push main → tự động deploy → app cập nhật trên VPS

Bước 7 — Monitoring
  └─ docker compose -f monitoring/docker-compose.monitoring.yml up
  └─ Grafana :3001 → xem CPU/RAM/Domain/SSL
```

---

## Tài liệu tham khảo

| Tài liệu | Mô tả |
|----------|-------|
| [Docker Setup Plan](docs/superpowers/plans/2026-05-23-docker-setup.md) | Hướng dẫn chi tiết Dockerfile + docker-compose |
| [Docker Setup Design](docs/superpowers/specs/2026-05-23-docker-setup-design.md) | Thiết kế kiến trúc Docker |
| [GitHub Actions Plan](docs/superpowers/plans/2026-05-24-github-actions-auto-deploy.md) | Hướng dẫn chi tiết CI/CD |
| [GitHub Actions Design](docs/superpowers/specs/2026-05-24-github-actions-auto-deploy-design.md) | Thiết kế workflow CI/CD |
| [Monitoring Plan](docs/superpowers/plans/2026-05-27-grafana-prometheus-monitoring.md) | Hướng dẫn chi tiết Grafana + Prometheus |
| [Terraform + Ansible Plan](docs/superpowers/plans/2026-05-27-terraform-ansible-infrastructure.md) | Hướng dẫn chi tiết IaC + Automation |
| [Terraform SPEC](root/terraform/SPEC.md) | Spec tạo VPS DigitalOcean |
