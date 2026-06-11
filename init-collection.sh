#!/usr/bin/env bash
#
# Crea la colección `supports` en PocketBase vía API REST tras el primer arranque.
# Idempotente: si la colección ya existe, no falla.
#
# Uso:
#   cp .env.example .env   # rellena PB_URL / PB_ADMIN_EMAIL / PB_ADMIN_PASSWORD
#   ./init-collection.sh
#
# Requiere: bash, curl. (jq opcional, solo para logs más legibles.)
#
# Probado contra PocketBase 0.38.x (API v0.23+: superusuarios en _superusers y
# definición de campos mediante `fields`).

set -euo pipefail

# Carga variables desde .env si existe (sin volcarlas al log).
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

PB_URL="${PB_URL:-http://localhost:8090}"
PB_ADMIN_EMAIL="${PB_ADMIN_EMAIL:?Define PB_ADMIN_EMAIL en .env}"
PB_ADMIN_PASSWORD="${PB_ADMIN_PASSWORD:?Define PB_ADMIN_PASSWORD en .env}"

echo "🔑 Autenticando superusuario en ${PB_URL} ..."
TOKEN="$(curl -fsS -X POST "${PB_URL}/api/collections/_superusers/auth-with-password" \
  -H "Content-Type: application/json" \
  -d "{\"identity\":\"${PB_ADMIN_EMAIL}\",\"password\":\"${PB_ADMIN_PASSWORD}\"}" \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"

if [ -z "${TOKEN}" ]; then
  echo "❌ No se pudo obtener token. ¿Creaste el primer superusuario? (panel ${PB_URL}/_/)" >&2
  exit 1
fi
echo "✅ Autenticado."

# ¿Existe ya la colección?
EXISTS="$(curl -fsS "${PB_URL}/api/collections/supports" \
  -H "Authorization: ${TOKEN}" -o /dev/null -w '%{http_code}' || true)"
if [ "${EXISTS}" = "200" ]; then
  echo "ℹ️  La colección 'supports' ya existe. Nada que hacer."
  exit 0
fi

echo "📦 Creando colección 'supports' ..."
curl -fsS -X POST "${PB_URL}/api/collections" \
  -H "Authorization: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "supports",
    "type": "base",
    "createRule": "",
    "fields": [
      { "name": "email",     "type": "email", "required": true },
      { "name": "country",   "type": "text"  },
      { "name": "locale",    "type": "text"  },
      { "name": "confirmed", "type": "bool"  },
      { "name": "created",   "type": "autodate", "onCreate": true, "onUpdate": false }
    ],
    "indexes": [
      "CREATE UNIQUE INDEX `idx_supports_email` ON `supports` (`email`)"
    ]
  }' > /dev/null

echo "🎉 Colección 'supports' creada correctamente."
echo "   Campos: email (único/required), country, locale, confirmed (bool), created (auto)."
