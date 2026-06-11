#!/usr/bin/env bash
#
# Despliegue de un tirón para righttoupdates-api (PocketBase + Traefik).
# Ejecútalo EN EL SERVIDOR, dentro de este repo.
#
#   ./deploy.sh
#
# Idempotente: puedes relanzarlo. Crea docker-compose.yml y .env desde las
# plantillas si no existen (luego revisa el .env y vuelve a lanzar).

set -euo pipefail
cd "$(dirname "$0")"

echo "▶ 1/6  Comprobando requisitos..."
command -v docker >/dev/null || { echo "❌ Falta Docker."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "❌ Falta 'docker compose'."; exit 1; }
docker network inspect traefik >/dev/null 2>&1 || {
  echo "ℹ️  La red 'traefik' no existe; creándola..."; docker network create traefik;
}

echo "▶ 2/6  Preparando ficheros de configuración..."
[ -f docker-compose.yml ] || { cp docker-compose.example.yml docker-compose.yml; echo "   creado docker-compose.yml"; }
if [ ! -f .env ]; then
  cp .env.example .env
  echo "❗ Se ha creado .env desde la plantilla. Edita PB_ADMIN_EMAIL / PB_ADMIN_PASSWORD"
  echo "   y PB_URL=https://data.righttoupdates.eu, luego vuelve a ejecutar ./deploy.sh"
  exit 1
fi

# Carga credenciales del .env
set -a; . ./.env; set +a
: "${PB_ADMIN_EMAIL:?Define PB_ADMIN_EMAIL en .env}"
: "${PB_ADMIN_PASSWORD:?Define PB_ADMIN_PASSWORD en .env}"
PB_URL="${PB_URL:-http://localhost:8090}"

echo "▶ 3/6  Levantando el contenedor PocketBase..."
docker compose up -d --build

echo "▶ 4/6  Esperando a que PocketBase responda..."
ok=0
for i in $(seq 1 40); do
  if curl -sf http://localhost:8090/api/health >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
[ "$ok" = 1 ] || { echo "❌ PocketBase no respondió en localhost:8090. Revisa: docker compose logs pocketbase"; exit 1; }
echo "   ✅ PocketBase arriba."

echo "▶ 5/6  Asegurando superusuario..."
docker compose exec -T pocketbase \
  pocketbase --dir=/pb/pb_data superuser upsert "$PB_ADMIN_EMAIL" "$PB_ADMIN_PASSWORD" \
  && echo "   ✅ superusuario listo."

echo "▶ 6/6  Creando la colección 'supports' (vía localhost)..."
PB_URL="http://localhost:8090" ./init-collection.sh

echo ""
echo "🎉 Backend desplegado."
echo "   Local:        http://localhost:8090/_/"
echo "   Producción:   https://data.righttoupdates.eu/_/  (Traefik emitirá el cert al primer acceso)"
echo ""
echo "Comprobación pública (puede tardar unos segundos por el certificado Let's Encrypt):"
echo "   curl -I https://data.righttoupdates.eu/api/health"
