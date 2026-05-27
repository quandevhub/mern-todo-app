# Spec: Tạo VPS trên DigitalOcean bằng Terraform

## Tổng quan

Dùng Terraform để tự động tạo một Droplet (VPS) trên DigitalOcean tại region Singapore, chạy Ubuntu 24.04, cấu hình 1 vCPU / 1GB RAM.

---

## Yêu cầu

### Tài khoản & thông tin cần có trước

| Thứ cần có | Cách lấy |
|---|---|
| DigitalOcean API Token | DO Dashboard → API → Generate New Token (Read + Write) |
| SSH Key fingerprint | DO Dashboard → Settings → Security → SSH Keys |

### Cài Terraform (bắt buộc dùng bản 64-bit)

> **Quan trọng**: Phải dùng bản `linux_amd64`. Bản `linux_386` (32-bit) sẽ gây lỗi overflow khi xử lý action ID trả về từ DigitalOcean API.

```bash
# Tải bản 64-bit
wget https://releases.hashicorp.com/terraform/1.15.4/terraform_1.15.4_linux_amd64.zip
unzip terraform_1.15.4_linux_amd64.zip
sudo mv terraform /usr/local/bin/terraform

# Xác nhận — phải thấy "on linux_amd64"
terraform version
```

---

## Cấu trúc file

```
root/terraform/
├── main.tf           # Cấu hình chính
├── terraform.tfvars  # Giá trị biến (chứa secret, KHÔNG commit git)
└── SPEC.md           # File này
```

---

## Cấu hình (`main.tf`)

```hcl
variable "do_token" {
  description = "DigitalOcean API Token"
}

variable "ssh_key" {
  description = "Your SSH key fingerprint in DigitalOcean"
}

terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.67.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_droplet" "setup" {
  name     = "terraform-vps"
  region   = "sgp1"           # Singapore
  size     = "s-1vcpu-1gb"    # 1 vCPU, 1GB RAM — $6/tháng
  image    = "ubuntu-24-04-x64"
  ssh_keys = [var.ssh_key]
}

output "droplet_ip" {
  value = { id : digitalocean_droplet.setup.ipv4_address }
}
```

### Thông số Droplet

| Thuộc tính | Giá trị |
|---|---|
| Region | `sgp1` (Singapore) |
| Size | `s-1vcpu-1gb` |
| OS | Ubuntu 24.04 LTS |
| Giá | ~$6/tháng (~$0.009/giờ) |
| Disk | 25GB SSD |

---

## File biến (`terraform.tfvars`)

Tạo file này trong cùng thư mục, **không commit lên git**:

```hcl
do_token = "dop_v1_<your_api_token_here>"
ssh_key  = "<your_ssh_key_fingerprint>"   # dạng: ab:cd:ef:...
```

Thêm vào `.gitignore`:

```
terraform.tfvars
.terraform/
terraform.tfstate
terraform.tfstate.backup
```

---

## Các bước chạy

### 1. Khởi tạo

```bash
terraform init
```

Tải provider `digitalocean/digitalocean v2.67.0` về thư mục `.terraform/`.

### 2. Xem trước thay đổi

```bash
terraform plan
```

Kiểm tra Terraform sẽ tạo/thay đổi/xóa gì trước khi apply.

### 3. Tạo VPS

```bash
terraform apply
```

Nhập `yes` khi được hỏi. Sau khi xong, IP của Droplet được in ra ở output `droplet_ip`.

### 4. Xem IP sau khi tạo

```bash
terraform output
```

### 5. Xóa VPS

```bash
terraform destroy
```

Nhập `yes` để xác nhận. Droplet bị xóa hoàn toàn trên DigitalOcean.

---

## Lỗi thường gặp

### Lỗi: `cannot unmarshal number ... into Go struct field ... of type int`

**Nguyên nhân**: Terraform binary đang chạy ở chế độ 32-bit (`linux_386`). Action ID trả về từ DigitalOcean API vượt giới hạn int32.

**Kiểm tra**:
```bash
terraform version
# Nếu thấy "on linux_386" → cần cài lại bản 64-bit
```

**Fix**: Cài lại Terraform bản `linux_amd64` (xem phần Cài Terraform ở trên).

---

### Lỗi: Lock file không khớp version

```
locked provider ... does not match configured version constraint
```

**Fix**:
```bash
terraform init -upgrade
```

---

### Droplet tạo thành công trên DO nhưng Terraform báo lỗi (state drift)

Droplet tồn tại trên DigitalOcean nhưng không có trong `terraform.tfstate`.

**Fix — Lựa chọn A** (xóa và tạo lại):
1. Vào DigitalOcean Dashboard → xóa droplet mồ côi
2. Chạy lại `terraform apply`

**Fix — Lựa chọn B** (import vào state):
```bash
# Lấy Droplet ID từ DO Dashboard
terraform import digitalocean_droplet.setup <DROPLET_ID>
```
