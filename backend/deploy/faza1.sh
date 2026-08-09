#!/usr/bin/env bash
# FAZA 1 — VPS asosi. Xato chiqsa to'xtaydi (set -e), keyingi qatorga o'tmaydi.
set -e
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

echo ">> vaqt zonasi"
timedatectl set-timezone Asia/Tashkent

echo ">> apt yangilash"
apt update && apt upgrade -y

echo ">> paketlar"
apt install -y ca-certificates curl gnupg nginx ufw certbot python3-certbot-nginx

echo ">> swap"
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
else
  echo "   /swapfile allaqachon bor — o'tkazib yuborildi"
fi

echo ">> Docker repo"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt update

echo ">> Docker o'rnatish"
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo ">> devor"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

mkdir -p /opt/topagon

echo ""
echo "========================================"
echo "NATIJA:"
echo "========================================"
free -h
docker --version
docker compose version
ufw status
echo "----"
nslookup api.telegram.org || echo "OGOHLANTIRISH: api.telegram.org VPS'dan ochilmadi"
echo "========================================"
echo "FAZA 1 TUGADI. 'reboot' buyrug'ini alohida ishlat."
echo "========================================"
