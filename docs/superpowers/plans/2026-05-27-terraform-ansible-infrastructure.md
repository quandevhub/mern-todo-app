# Terraform + Ansible Infrastructure — Implementation Plan

**Goal:** Dùng Terraform tạo VPS trên DigitalOcean, sau đó dùng Ansible tự động cài Docker và deploy ứng dụng MERN todo app lên VPS vừa tạo.

**Architecture:** Chạy Terraform và Ansible bên trong container Ubuntu 24.04 (`ubuntu-ansible`) với volume mount thư mục `root/` từ host. Terraform tạo Droplet (DigitalOcean Singapore), Ansible SSH vào Droplet đó để cài phần mềm và deploy app.

**Tech Stack:** Docker, Ubuntu 24.04, Terraform 1.15.4 (linux_amd64), Ansible, DigitalOcean provider v2.67.0

---

## Sơ đồ workflow tổng thể

```
┌──────────────────────────────────────────────────────────────┐
│  Host machine (Windows)                                      │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  Container: ubuntu-ansible                          │     │
│  │  Volume: ./root → /root (trong container)           │     │
│  │                                                     │     │
│  │  [Terraform]          [Ansible]                     │     │
│  │  terraform apply  →   update hosts.ini              │     │
│  │  → IP: x.x.x.x       ansible-playbook ...          │     │
│  └─────────────────────────────────────────────────────┘     │
│                          │                                   │
│                          │ SSH (port 22)                     │
│                          ▼                                   │
│              ┌───────────────────────┐                       │
│              │  DigitalOcean Droplet │                       │
│              │  sgp1 / Ubuntu 24.04  │                       │
│              │  1vCPU / 1GB RAM      │                       │
│              │  → Docker + App       │                       │
│              └───────────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
```

---

## Yêu cầu trước khi bắt đầu

| Thứ cần có | Cách lấy |
|---|---|
| DigitalOcean API Token | DO Dashboard → API → Generate New Token (Read + Write) |
| SSH Key fingerprint | DO Dashboard → Settings → Security → SSH Keys |
| SSH private key file | File `root/ansible/ssh-key-demo` (đã có trong repo) |

---

## File Structure

```
root/
├── terraform/
│   ├── main.tf                     # Cấu hình Droplet (đã có)
│   ├── terraform.tfvars            # Token + SSH key (KHÔNG commit git)
│   └── terraform_1.15.4_linux_amd64.zip  # Binary (đã có)
└── ansible/
    ├── ansible.cfg                 # Config (đã có)
    ├── hosts.ini                   # Danh sách host → cập nhật IP sau terraform apply
    ├── install_vps.yml             # Playbook deploy app (đã có)
    └── ssh-key-demo                # SSH private key để kết nối VPS
```

---

## PHẦN 1: TERRAFORM

## Task 1: Khởi động container Ubuntu làm môi trường làm việc

- [ ] **Step 1: Khởi động container ubuntu-ansible**

Chạy lệnh này từ thư mục gốc project (nơi chứa thư mục `root/`):

```bash
docker run -d -it --name ubuntu-ansible \
  -v ./root:/root \
  ubuntu:24.04
```

> **Giải thích volume:** `./root` trên host → `/root` bên trong container.  
> Toàn bộ file terraform và ansible nằm trong `/root/terraform/` và `/root/ansible/` bên trong container.

- [ ] **Step 2: Verify container đang chạy**

```bash
docker ps --filter "name=ubuntu-ansible"
```

Expected: container hiển thị status `Up`.

- [ ] **Step 3: Vào shell của container**

```bash
docker exec -it ubuntu-ansible bash
```

Từ đây trở đi, tất cả lệnh chạy **bên trong container** (trừ khi có ghi chú khác).

---

## Task 2: Cài đặt Terraform bên trong container

- [ ] **Step 1: Cập nhật apt và cài các tool cần thiết**

```bash
apt update && apt install -y unzip wget
```

Expected: không có lỗi, `unzip` và `wget` đã cài.

- [ ] **Step 2: Kiểm tra file zip đã có trong volume**

```bash
ls /root/terraform/
```

Expected: thấy `terraform_1.15.4_linux_amd64.zip` trong danh sách.

Nếu **không có** file zip, tải về:

```bash
wget https://releases.hashicorp.com/terraform/1.15.4/terraform_1.15.4_linux_amd64.zip \
  -O /root/terraform/terraform_1.15.4_linux_amd64.zip
```

- [ ] **Step 3: Giải nén và cài Terraform**

```bash
cd /root/terraform
unzip terraform_1.15.4_linux_amd64.zip
mv terraform /usr/local/bin/terraform
chmod +x /usr/local/bin/terraform
```

- [ ] **Step 4: Verify cài đặt — bắt buộc kiểm tra linux_amd64**

```bash
terraform version
```

Expected output:
```
Terraform v1.15.4
on linux_amd64
```

> **QUAN TRỌNG:** Phải thấy `on linux_amd64`. Nếu thấy `linux_386` (32-bit) sẽ gặp lỗi overflow khi gọi DigitalOcean API. Xem phần Troubleshooting cuối plan.

---

## Task 3: Cấu hình credentials và tạo VPS

- [ ] **Step 1: Điền API token và SSH fingerprint vào terraform.tfvars**

```bash
cat /root/terraform/terraform.tfvars
```

File hiện có dạng:
```hcl
do_token="xxxxxxxxxxxxxxxxxx"
ssh_key="xxxxxxxxxxxxxxxxxx"
```

Cập nhật giá trị thực:
```bash
cat > /root/terraform/terraform.tfvars << 'EOF'
do_token="dop_v1_<your_actual_api_token>"
ssh_key="<your_ssh_key_fingerprint>"
EOF
```

> **Lấy SSH fingerprint:** DigitalOcean Dashboard → Settings → Security → SSH Keys → copy fingerprint dạng `ab:cd:ef:12:...`

- [ ] **Step 2: Khởi tạo Terraform (tải provider)**

```bash
cd /root/terraform
terraform init
```

Expected output kết thúc bằng:
```
Terraform has been successfully initialized!
```

Lệnh này tải provider `digitalocean/digitalocean v2.67.0` vào thư mục `.terraform/`.

- [ ] **Step 3: Kiểm tra cú pháp cấu hình**

```bash
terraform validate
```

Expected:
```
Success! The configuration is valid.
```

- [ ] **Step 4: Xem trước thay đổi trước khi apply**

```bash
terraform plan
```

Expected: thấy plan tạo 1 resource `digitalocean_droplet.setup` với:
- `name = "terraform-vps"`
- `region = "sgp1"`
- `size = "s-1vcpu-1gb"`
- `image = "ubuntu-24-04-x64"`

Không được thấy dòng `destroy`.

- [ ] **Step 5: Tạo VPS**

```bash
terraform apply
```

Khi được hỏi `Do you want to perform these actions?`, nhập:
```
yes
```

Expected sau khi hoàn thành (~30-60 giây):
```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

droplet_ip = {
  "id" = "xxx.xxx.xxx.xxx"
}
```

- [ ] **Step 6: Ghi lại IP của VPS vừa tạo**

```bash
terraform output
```

Expected:
```
droplet_ip = {
  "id" = "165.22.xx.xx"
}
```

> **Lưu IP này lại** — cần dùng cho phần Ansible bên dưới.

---

## Task 4: Kiểm tra kết nối SSH vào VPS

- [ ] **Step 1: Phân quyền SSH key**

```bash
chmod 600 /root/ansible/ssh-key-demo
```

- [ ] **Step 2: SSH thử vào VPS**

Thay `<VPS_IP>` bằng IP lấy được ở Task 3 Step 6:

```bash
ssh -i /root/ansible/ssh-key-demo -o StrictHostKeyChecking=no root@<VPS_IP> "echo 'SSH OK'"
```

Expected:
```
SSH OK
```

Nếu bị timeout: VPS chưa boot xong, đợi 30 giây rồi thử lại.

---

## PHẦN 2: ANSIBLE

## Task 5: Cài đặt Ansible bên trong container

> Vẫn đang ở shell của container `ubuntu-ansible` từ Task 1.

- [ ] **Step 1: Cài Ansible**

```bash
apt install -y ansible
```

- [ ] **Step 2: Verify Ansible đã cài**

```bash
ansible --version
```

Expected (phần quan trọng):
```
ansible [core 2.x.x]
  ...
  python version = 3.x.x
```

---

## Task 6: Cấu hình inventory (hosts.ini) với IP từ Terraform

- [ ] **Step 1: Xem cấu trúc hosts.ini hiện tại**

```bash
cat /root/ansible/hosts.ini
```

Output hiện tại:
```ini
[danh_sach_host]
165.22.51.10 ansible_user=root ansible_ssh_private_key_file=./ssh-key-demo
```

- [ ] **Step 2: Cập nhật IP với IP mới từ terraform output**

Thay `<VPS_IP>` bằng IP thực lấy từ Task 3:

```bash
cat > /root/ansible/hosts.ini << EOF
[danh_sach_host]
<VPS_IP> ansible_user=root ansible_ssh_private_key_file=./ssh-key-demo
EOF
```

Ví dụ nếu IP là `167.71.22.100`:
```bash
cat > /root/ansible/hosts.ini << EOF
[danh_sach_host]
167.71.22.100 ansible_user=root ansible_ssh_private_key_file=./ssh-key-demo
EOF
```

- [ ] **Step 3: Verify hosts.ini đã cập nhật đúng**

```bash
cat /root/ansible/hosts.ini
```

Expected: IP hiển thị đúng với IP từ terraform output.

---

## Task 7: Test kết nối Ansible đến VPS

- [ ] **Step 1: Chạy ansible ping test**

```bash
cd /root/ansible
ansible -i hosts.ini danh_sach_host -m ping
```

Expected:
```json
<VPS_IP> | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

Nếu bị lỗi `UNREACHABLE`: kiểm tra lại IP trong hosts.ini và SSH key permission (`chmod 600 ssh-key-demo`).

---

## Task 8: Chạy Ansible Playbook để deploy app

- [ ] **Step 1: Xem nội dung playbook trước khi chạy**

```bash
cat /root/ansible/install_vps.yml
```

Playbook sẽ thực hiện theo thứ tự:
1. Cài `docker.io`
2. Tải và cài `docker-compose` binary mới nhất
3. Phân quyền `chmod +x /usr/bin/docker-compose`
4. Clone repo `https://github.com/quandevhub/mern-todo-app.git` vào `/root/mern-todo-app`
5. Tạo file `.env` cho backend
6. Chạy `docker-compose up --build -d`

- [ ] **Step 2: Chạy playbook**

```bash
cd /root/ansible
ansible-playbook -i hosts.ini install_vps.yml
```

Expected output — mỗi task hiển thị trạng thái:
```
PLAY [Tên của playbook] **********************************************

TASK [Gathering Facts] ***********************************************
ok: [<VPS_IP>]

TASK [Cài docker] ****************************************************
changed: [<VPS_IP>]

TASK [Cài docker-compose] ********************************************
changed: [<VPS_IP>]

TASK [phân quyền docker-compose] *************************************
changed: [<VPS_IP>]

TASK [clone source] **************************************************
changed: [<VPS_IP>]

TASK [tạo file .env cho backend] *************************************
changed: [<VPS_IP>]

TASK [deploy web] ****************************************************
changed: [<VPS_IP>]

PLAY RECAP ***********************************************************
<VPS_IP> : ok=7   changed=6   unreachable=0   failed=0
```

> **Lưu ý:** Bước `deploy web` có thể mất 3-5 phút do pull Docker images và build.

- [ ] **Step 3: Verify app đã chạy trên VPS**

SSH vào VPS và kiểm tra:

```bash
ssh -i /root/ansible/ssh-key-demo root@<VPS_IP> "docker ps"
```

Expected: thấy các containers `mongodb`, `backend`, `frontend` đang `Up`.

- [ ] **Step 4: Kiểm tra app accessible từ browser**

Truy cập `http://<VPS_IP>` từ browser. Expected: frontend của MERN todo app hiển thị.

---

## PHẦN 3: TỔNG HỢP — Workflow end-to-end

## Task 9: Lần chạy hoàn chỉnh từ đầu

Tóm tắt toàn bộ flow khi cần tạo mới từ đầu:

- [ ] **Bước 1:** Khởi động container
```bash
docker start ubuntu-ansible && docker exec -it ubuntu-ansible bash
```

- [ ] **Bước 2:** Tạo VPS với Terraform
```bash
cd /root/terraform
terraform apply
# Ghi lại IP từ output
```

- [ ] **Bước 3:** Đợi VPS boot xong (~30s), test SSH
```bash
ssh -i /root/ansible/ssh-key-demo root@<IP> "echo ok"
```

- [ ] **Bước 4:** Cập nhật IP vào hosts.ini
```bash
sed -i "s/^[0-9.]* /<IP> /" /root/ansible/hosts.ini
```

- [ ] **Bước 5:** Deploy app với Ansible
```bash
cd /root/ansible
ansible-playbook -i hosts.ini install_vps.yml
```

- [ ] **Bước 6:** Xác nhận app chạy tại `http://<IP>`

---

## Task 10: Dọn dẹp — Xóa VPS

> Thực hiện khi không cần VPS nữa để tránh tốn phí DigitalOcean (~$6/tháng).

- [ ] **Step 1: Xóa toàn bộ hạ tầng**

```bash
cd /root/terraform
terraform destroy
```

Khi được hỏi `Do you really want to destroy all resources?`, nhập:
```
yes
```

Expected:
```
Destroy complete! Resources: 1 destroyed.
```

- [ ] **Step 2: Verify Droplet đã xóa trên DigitalOcean**

Vào DigitalOcean Dashboard → Droplets → xác nhận `terraform-vps` không còn trong danh sách.

---

## Troubleshooting

### Lỗi: `cannot unmarshal number into Go struct field of type int`

**Nguyên nhân:** Terraform đang chạy bản 32-bit (`linux_386`).  
**Fix:** Xem lại Task 2 — bắt buộc dùng bản `linux_amd64`.

```bash
terraform version  # Phải thấy "on linux_amd64"
```

---

### Lỗi: `locked provider does not match configured version constraint`

**Fix:**
```bash
terraform init -upgrade
```

---

### Lỗi: Droplet tồn tại trên DO nhưng terraform không biết (state drift)

**Option A** — Xóa droplet thủ công trên DO Dashboard, rồi `terraform apply` lại.

**Option B** — Import vào state:
```bash
terraform import digitalocean_droplet.setup <DROPLET_ID>
# DROPLET_ID lấy từ DO Dashboard hoặc: doctl compute droplet list
```

---

### Lỗi Ansible: `UNREACHABLE — SSH timeout`

**Kiểm tra:**
1. VPS còn đang boot? Đợi thêm 30-60 giây rồi thử lại
2. SSH key đúng chưa? `chmod 600 /root/ansible/ssh-key-demo`
3. IP trong `hosts.ini` đúng chưa? So với `terraform output`
4. Firewall DigitalOcean có block port 22 không?

---

### Lỗi Ansible: `docker: command not found` khi chạy playbook lần 2

**Nguyên nhân:** Task `Cài docker` đã chạy lần trước (`ok`), nhưng `docker-compose` task dùng `shell` module không idempotent.  
**Fix:** Không phải lỗi — playbook chạy lại hoàn toàn bình thường, task nào đã `ok` sẽ không chạy lại.

---

## Checklist hoàn thành

- [ ] Container `ubuntu-ansible` đã tạo và chạy được
- [ ] Terraform `v1.15.4 on linux_amd64` đã cài
- [ ] `terraform.tfvars` có token và SSH fingerprint thực
- [ ] `terraform apply` tạo thành công Droplet, lấy được IP
- [ ] SSH vào VPS bằng `ssh-key-demo` thành công
- [ ] Ansible ping test trả về `pong`
- [ ] Playbook chạy xong, `failed=0`
- [ ] App accessible tại `http://<VPS_IP>`
- [ ] `terraform destroy` dọn sạch khi xong
