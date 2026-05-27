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
  token = var.do_token # Thay bằng token của bạn
}


resource "digitalocean_droplet" "setup" {
  name   = "terraform-vps"
  region = "sgp1"                 # Chọn region (nyc1 là New York)
  size   = "s-1vcpu-1gb"          # VPS với 1 vCPU và 1GB RAM
  image  = "ubuntu-24-04-x64"     # Sử dụng Ubuntu 20.04
  ssh_keys = [var.ssh_key]        # Thêm SSH Key nếu cần, nếu chưa có có thể bỏ qua
}

output "droplet_ip" {
  value = { id : digitalocean_droplet.setup.ipv4_address }
}