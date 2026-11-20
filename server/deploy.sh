#!/usr/bin/env bash
# Deploys the Teamgram server for "telegram i" on a fresh Ubuntu 24.04 VM (x86_64 or arm64).
# Run as the default sudo user:  bash deploy.sh
# Public ports: 10443 (MTProto TCP), 5222 (TCP), 11443 (WebSocket). Everything else stays on localhost.
set -euo pipefail

TEAMGRAM_COMMIT="${TEAMGRAM_COMMIT:-8adf26bc071159c12a62c22ad49625a73e922e79}"
DIR=/opt/teamgram-server
PUBLIC_PORTS=(10443 5222 11443)

log() { printf '\n== %s\n' "$*"; }

log "Packages"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl iptables-persistent >/dev/null

if ! command -v docker >/dev/null; then
  log "Docker"
  curl -fsSL https://get.docker.com | sudo sh >/dev/null
fi
sudo docker version --format 'docker {{.Server.Version}} ({{.Server.Arch}})'
sudo docker compose version

log "Firewall (iptables on the VM; the cloud security list must allow the same ports)"
for p in "${PUBLIC_PORTS[@]}"; do
  sudo iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null \
    || sudo iptables -I INPUT -p tcp --dport "$p" -j ACCEPT
done
sudo netfilter-persistent save >/dev/null

log "Teamgram sources @ ${TEAMGRAM_COMMIT}"
if [ ! -d "$DIR/.git" ]; then
  sudo git clone -q https://github.com/teamgram/teamgram-server.git "$DIR"
fi
cd "$DIR"
sudo git fetch -q origin
sudo git checkout -q "$TEAMGRAM_COMMIT"
git log -1 --format='%h %s'

log "Compose overrides: infrastructure only on localhost, no monitoring stack"
sudo tee "$DIR/env-local.yaml" >/dev/null <<'YAML'
services:
  kafka:
    ports: !override
      - "127.0.0.1:9092:9092"
      - "127.0.0.1:9094:9094"
  etcd:
    ports: !override
      - "127.0.0.1:2379:2379"
      - "127.0.0.1:2380:2380"
  redis:
    ports: !override
      - "127.0.0.1:6379:6379"
  mysql:
    ports: !override
      - "127.0.0.1:3306:3306"
  minio:
    ports: !override
      - "127.0.0.1:9000:9000"
      - "127.0.0.1:9001:9001"
YAML

sudo tee "$DIR/docker-compose.override.yaml" >/dev/null <<'YAML'
services:
  teamgram:
    ports: !override
      - "10443:10443"
      - "5222:5222"
      - "11443:11443"
      - "127.0.0.1:8801:8801"
YAML

log "Infrastructure: kafka, etcd, redis, mysql, minio"
sudo docker compose -f docker-compose-env.yaml -f env-local.yaml up -d kafka etcd redis mysql minio minio-mc

log "Waiting for MySQL"
for i in $(seq 1 60); do
  if sudo docker inspect -f '{{.State.Health.Status}}' mysql 2>/dev/null | grep -q healthy; then echo "mysql healthy"; break; fi
  sleep 5
done

log "Teamgram (build from source, takes a while on a small VM)"
sudo docker compose up -d --build

log "Status"
sudo docker compose -f docker-compose-env.yaml -f env-local.yaml ps --format 'table {{.Name}}\t{{.State}}\t{{.Ports}}'
sudo docker compose ps --format 'table {{.Name}}\t{{.State}}\t{{.Ports}}'
sleep 20
sudo ss -ltnp | grep -E ':(10443|5222|11443)\b' || echo "WARNING: public ports are not listening yet, check: sudo docker compose logs teamgram"
echo
echo "Done. Server address for the app: $(curl -fsS https://api.ipify.org || echo '<public IP>'):10443"
