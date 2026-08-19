#!/bin/sh
# Sobe o plugin ao lado de /root/chatwoot, sem rebuild da imagem oficial.
# Uso na VPS: /root/chat-nex-protocolos/deploy/vps-up.sh

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f .env ]; then
  echo "Crie $ROOT/.env a partir de .env.example (DATABASE_URL do Chatwoot)."
  exit 1
fi

NETWORK="$(grep '^CHATWOOT_NETWORK=' .env | cut -d= -f2 || true)"
NETWORK="${NETWORK:-chatwoot_default}"

if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  echo "Rede $NETWORK não existe. Ajuste CHATWOOT_NETWORK no .env (docker network ls)."
  exit 1
fi

docker compose up -d --build
echo "Proxy em :${PROTOCOLOS_PROXY_PORT:-8088}. Aponte o Nginx/host para este proxy, não direto no rails."
