# Grafana + Prometheus Monitoring Stack — Implementation Plan

**Goal:** Triển khai monitoring stack gồm Prometheus + Grafana + Node Exporter + Blackbox Exporter để theo dõi CPU, RAM, domain HTTP và SSL certificate của ứng dụng MERN todo app.

**Architecture:** Tất cả container monitoring chạy trong cùng Docker network `app-network` (đã định nghĩa trong `docker-compose.yml`). Prometheus thu thập metrics từ Node Exporter (CPU/RAM) và Blackbox Exporter (HTTP/SSL). Grafana kết nối Prometheus làm datasource và hiển thị dashboard.

**Tech Stack:** Docker, Prometheus 2.x, Grafana 12.1, prom/node-exporter, prom/blackbox-exporter

---

## Sơ đồ kiến trúc

```
┌─────────────────────────────────────────────────────┐
│                   app-network                       │
│                                                     │
│  ┌──────────────┐    scrape    ┌─────────────────┐  │
│  │  Prometheus  │◄────────────│  node-exporter  │  │
│  │   :9090      │             │    :9100        │  │
│  │              │◄────────────│  blackbox-exp.  │  │
│  └──────┬───────┘    probe    │    :9115        │  │
│         │                    └─────────────────┘  │
│         │ datasource                               │
│         ▼                                         │
│  ┌──────────────┐                                 │
│  │   Grafana    │  ← browser                      │
│  │   :3001      │                                 │
│  └──────────────┘                                 │
└─────────────────────────────────────────────────────┘
```

> **Lưu ý port:** Frontend dev đang dùng port `3000`, nên Grafana được map sang `3001:3000` để tránh conflict.

---

## File Structure

```
mern-todo-app/
├── monitoring/
│   ├── docker-compose.monitoring.yml   # Tất cả monitoring services
│   └── prometheus.yml                  # Prometheus scrape config
├── docker-compose.yml                  # Base (đã có app-network)
└── docs/superpowers/plans/
    └── 2026-05-27-grafana-prometheus-monitoring.md
```

---

## Task 1: Tạo cấu hình Prometheus

**Files:**
- Create: `monitoring/prometheus.yml`

- [ ] **Step 1: Tạo thư mục monitoring**

```powershell
New-Item -ItemType Directory -Force monitoring
```

- [ ] **Step 2: Tạo file prometheus.yml**

Tạo file `monitoring/prometheus.yml` với nội dung sau:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Prometheus tự monitor chính nó
  - job_name: 'prometheus'
    scrape_interval: 1m
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter: CPU, RAM, Disk, Network của host
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['host-node-exporter:9100']

  # Blackbox: kiểm tra HTTP/HTTPS endpoint và SSL cert
  - job_name: 'blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://www.google.com        # thay bằng domain thực của bạn
          - https://www.youtube.com
          - http://localhost:8000/api      # endpoint backend app (nếu expose)
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: host-blackbox:9115

  # Blackbox Exporter self-monitor
  - job_name: 'blackbox_exporter'
    static_configs:
      - targets: ['host-blackbox:9115']
```

> **Để thêm domain cần theo dõi:** thêm URL vào phần `targets` của job `blackbox`.

- [ ] **Step 3: Verify file tồn tại**

```powershell
Get-Content monitoring/prometheus.yml
```

Expected: nội dung yaml hiển thị đầy đủ, không lỗi parse.

---

## Task 2: Tạo Docker Compose cho monitoring stack

**Files:**
- Create: `monitoring/docker-compose.monitoring.yml`

- [ ] **Step 1: Tạo docker-compose.monitoring.yml**

```yaml
version: '3.8'

services:

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    networks:
      - app-network
    restart: unless-stopped

  grafana:
    image: grafana/grafana:12.1
    container_name: grafana
    ports:
      - "3001:3000"           # 3001 host → 3000 container (tránh conflict với frontend dev:3000)
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin123   # đổi password này trước khi lên production
    networks:
      - app-network
    restart: unless-stopped
    depends_on:
      - prometheus

  node-exporter:
    image: prom/node-exporter:latest
    container_name: host-node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - app-network
    restart: unless-stopped

  blackbox-exporter:
    image: prom/blackbox-exporter:latest
    container_name: host-blackbox
    ports:
      - "9115:9115"
    networks:
      - app-network
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:

networks:
  app-network:
    external: true    # dùng network đã tạo bởi docker-compose.yml chính
```

- [ ] **Step 2: Verify file syntax**

```powershell
docker compose -f monitoring/docker-compose.monitoring.yml config
```

Expected: output hiển thị full config đã được parse thành công, không có error.

---

## Task 3: Khởi động monitoring stack

- [ ] **Step 1: Đảm bảo app-network đã tồn tại**

Network `app-network` được tạo bởi `docker-compose.yml` chính. Nếu chưa chạy app:

```powershell
docker network ls | Select-String "app-network"
```

Nếu không thấy, tạo network thủ công:

```powershell
docker network create app-network
```

- [ ] **Step 2: Khởi động tất cả monitoring containers**

```powershell
docker compose -f monitoring/docker-compose.monitoring.yml up -d
```

Expected output:
```
[+] Running 5/5
 ✔ Network app-network          Created (hoặc "Found" nếu đã tồn tại)
 ✔ Container prometheus         Started
 ✔ Container host-node-exporter Started
 ✔ Container host-blackbox      Started
 ✔ Container grafana            Started
```

- [ ] **Step 3: Kiểm tra tất cả containers đang chạy**

```powershell
docker ps --filter "name=prometheus" --filter "name=grafana" --filter "name=host-node-exporter" --filter "name=host-blackbox" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected: 4 containers hiển thị status `Up`.

- [ ] **Step 4: Kiểm tra logs nếu có container không start**

```powershell
docker logs prometheus --tail 20
docker logs grafana --tail 20
docker logs host-node-exporter --tail 20
docker logs host-blackbox --tail 20
```

---

## Task 4: Xác nhận Prometheus nhận đủ targets

- [ ] **Step 1: Mở Prometheus UI**

Truy cập: `http://localhost:9090`

- [ ] **Step 2: Kiểm tra tất cả targets UP**

Vào menu: **Status → Targets** (`http://localhost:9090/targets`)

Expected — tất cả targets phải ở trạng thái `UP`:
| Job | Target | State |
|-----|--------|-------|
| prometheus | localhost:9090 | UP |
| node-exporter | host-node-exporter:9100 | UP |
| blackbox | https://www.google.com | UP |
| blackbox | https://www.youtube.com | UP |
| blackbox_exporter | host-blackbox:9115 | UP |

> Nếu `blackbox` targets trả về lỗi connection: kiểm tra container `host-blackbox` đã join đúng network chưa bằng `docker inspect host-blackbox`.

- [ ] **Step 3: Test query CPU trên Prometheus**

Vào **Graph**, chạy query:

```promql
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)
```

Expected: ra số thập phân thể hiện % CPU usage.

- [ ] **Step 4: Test query RAM trên Prometheus**

```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

Expected: ra % RAM đang dùng.

- [ ] **Step 5: Test query SSL cert expiry**

```promql
probe_ssl_earliest_cert_expiry - time()
```

Expected: ra số giây còn lại trước khi cert hết hạn (số dương = còn hạn).

---

## Task 5: Cấu hình Grafana datasource

- [ ] **Step 1: Đăng nhập Grafana**

Truy cập: `http://localhost:3001`
- Username: `admin`
- Password: `admin123`

Grafana sẽ yêu cầu đổi password lần đầu — có thể bỏ qua hoặc đổi.

- [ ] **Step 2: Thêm Prometheus datasource**

1. Vào **Connections → Data sources** (menu trái)
2. Click **Add new data source**
3. Chọn **Prometheus**
4. Điền:
   - **Name:** `Prometheus`
   - **URL:** `http://prometheus:9090`   ← dùng container name, không phải localhost
5. Click **Save & test**

Expected: hiện thông báo `"Successfully queried the Prometheus API."` màu xanh lá.

---

## Task 6: Import dashboard CPU/RAM (Node Exporter Full)

- [ ] **Step 1: Import dashboard**

1. Vào **Dashboards → Import** (menu trái hoặc `+` → Import)
2. Nhập Dashboard ID: **`1860`** (Node Exporter Full)
3. Click **Load**
4. Tại **Prometheus**, chọn datasource `Prometheus` vừa tạo
5. Click **Import**

- [ ] **Step 2: Verify dashboard hoạt động**

Truy cập dashboard vừa import. Kiểm tra:
- **CPU Usage** panel: hiển thị % CPU theo thời gian
- **Memory Usage** panel: hiển thị RAM used/total
- **Disk I/O** panel: hiển thị read/write speed
- **Network Traffic** panel: hiển thị bytes in/out

Nếu panel hiển thị "No data": kiểm tra biến `$node` (dropdown phía trên) đã chọn đúng instance `host-node-exporter:9100` chưa.

---

## Task 7: Import dashboard Domain/SSL (Blackbox Exporter)

- [ ] **Step 1: Import dashboard SSL + HTTP probe**

1. Vào **Dashboards → Import**
2. Nhập Dashboard ID: **`13659`** (Blackbox Exporter)
3. Click **Load**
4. Chọn datasource `Prometheus`
5. Click **Import**

- [ ] **Step 2: Verify SSL monitoring**

Trong dashboard, kiểm tra:
- **Probe Success** panel: `1` = OK, `0` = domain không reachable
- **SSL Cert Expiry** panel: số ngày còn lại trước khi cert hết hạn
- **HTTP Status Code** panel: 200, 301, v.v.

> Nếu muốn dùng dashboard khác: tìm kiếm tại https://grafana.com/grafana/dashboards với keyword "blackbox" hoặc "ssl".

---

## Task 8: Thêm domain mới để theo dõi

- [ ] **Step 1: Sửa prometheus.yml để thêm domain**

Trong `monitoring/prometheus.yml`, thêm URL vào `targets` của job `blackbox`:

```yaml
    static_configs:
      - targets:
          - https://www.google.com
          - https://www.youtube.com
          - https://your-domain.com        # ← thêm dòng này
          - https://api.your-domain.com    # ← hoặc subdomain
```

- [ ] **Step 2: Reload Prometheus config (không cần restart)**

```powershell
docker exec prometheus kill -HUP 1
```

Hoặc gọi API:

```powershell
Invoke-WebRequest -Uri "http://localhost:9090/-/reload" -Method POST
```

- [ ] **Step 3: Verify target mới hiển thị**

Vào `http://localhost:9090/targets` — target mới phải xuất hiện trong job `blackbox`.

---

## Task 9: Dừng và quản lý stack

- [ ] **Dừng stack (giữ data):**

```powershell
docker compose -f monitoring/docker-compose.monitoring.yml down
```

- [ ] **Dừng stack và xóa data volumes:**

```powershell
docker compose -f monitoring/docker-compose.monitoring.yml down -v
```

- [ ] **Khởi động lại:**

```powershell
docker compose -f monitoring/docker-compose.monitoring.yml up -d
```

---

## Tổng hợp ports

| Service | Host Port | Container Port | URL |
|---------|-----------|----------------|-----|
| Grafana | 3001 | 3000 | http://localhost:3001 |
| Prometheus | 9090 | 9090 | http://localhost:9090 |
| Node Exporter | 9100 | 9100 | http://localhost:9100/metrics |
| Blackbox Exporter | 9115 | 9115 | http://localhost:9115 |

## Dashboard IDs hữu ích

| Dashboard | ID | Mô tả |
|-----------|----|-------|
| Node Exporter Full | 1860 | CPU, RAM, Disk, Network chi tiết |
| Blackbox Exporter | 13659 | HTTP probe + SSL cert expiry |
| Node Exporter Quickstart | 13978 | CPU/RAM đơn giản hơn |
| Prometheus Stats | 3662 | Prometheus self-monitoring |

---

## Checklist triển khai

- [ ] `monitoring/prometheus.yml` đã tạo với đúng target names
- [ ] `monitoring/docker-compose.monitoring.yml` đã tạo
- [ ] Network `app-network` tồn tại
- [ ] 4 containers đang chạy và status `Up`
- [ ] Prometheus targets tất cả `UP` tại `/targets`
- [ ] Grafana datasource kết nối thành công
- [ ] Dashboard 1860 (Node Exporter) import và có data
- [ ] Dashboard 13659 (Blackbox) import và hiển thị SSL days remaining
