# righttoupdates-api

API de datos para la Iniciativa Ciudadana Europea **Right to Updates**
(<https://righttoupdates.eu>). Una instancia de **PocketBase** en su propio
contenedor Docker, detrás de **Traefik**, expuesta en `data.righttoupdates.eu`.

Almacena los apoyos a la campaña en la colección `supports`.

## Arquitectura

- **PocketBase** corre en un contenedor aparte (`righttoupdates-pocketbase`),
  construido desde el `Dockerfile` con una versión fijada
  (ver `.pocketbase-version`).
- Los datos persisten en un bind mount **`./pb_data`** del host (no se versiona).
- Traefik publica el servicio en `https://data.righttoupdates.eu` (router TLS con
  `certresolver=letsencrypt`).

> El `docker-compose.yml` real con los dominios y la `.env` con credenciales **no se
> versionan**. Se versiona solo `docker-compose.example.yml` y `.env.example`, igual
> que en `seguridad-sin-caducidad`.

## Requisitos

- Docker + Docker Compose.
- Una red externa de Traefik llamada `traefik` ya en marcha:
  ```bash
  docker network create traefik   # si aún no existe
  ```

## Levantarlo

```bash
# 1) Copia las plantillas y ajusta valores
cp docker-compose.example.yml docker-compose.yml   # revisa el dominio data.righttoupdates.eu
cp .env.example .env                               # rellena email/contraseña del admin

# 2) Arranca el contenedor (construye la imagen la primera vez)
docker compose up -d --build

# 3) Crea el primer superusuario de PocketBase
#    Opción A — por el panel web:  http://localhost:8090/_/
#    Opción B — por CLI:
docker compose exec pocketbase \
  pocketbase --dir=/pb/pb_data superuser upsert "$PB_ADMIN_EMAIL" "$PB_ADMIN_PASSWORD"
```

El panel de administración queda en `http://localhost:8090/_/` (local) o en
`https://data.righttoupdates.eu/_/` (producción, vía Traefik).

## Crear la colección `supports`

Tras el primer arranque y haber creado el superusuario, ejecuta el script incluido:

```bash
./init-collection.sh
```

Lee `PB_URL`, `PB_ADMIN_EMAIL` y `PB_ADMIN_PASSWORD` desde `.env`, se autentica
contra la API y crea la colección de forma **idempotente** (si ya existe, no hace
nada). En producción, pon `PB_URL=https://data.righttoupdates.eu` en tu `.env`.

### Esquema de `supports`

| Campo       | Tipo       | Notas                                  |
|-------------|------------|----------------------------------------|
| `email`     | `email`    | requerido y **único** (índice único)   |
| `country`   | `text`     | país del firmante                      |
| `locale`    | `text`     | idioma/locale (p. ej. `es`, `de`)      |
| `confirmed` | `bool`     | doble opt-in confirmado                 |
| `created`   | `autodate` | se rellena automáticamente al crear     |

### Alternativa manual (sin el script)

```bash
# 1) Autenticación (PocketBase 0.23+: superusuarios en _superusers)
TOKEN=$(curl -s -X POST \
  "$PB_URL/api/collections/_superusers/auth-with-password" \
  -H "Content-Type: application/json" \
  -d '{"identity":"admin@righttoupdates.eu","password":"TU_PASSWORD"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

# 2) Crear la colección
curl -s -X POST "$PB_URL/api/collections" \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "name": "supports",
    "type": "base",
    "fields": [
      { "name": "email",     "type": "email", "required": true },
      { "name": "country",   "type": "text"  },
      { "name": "locale",    "type": "text"  },
      { "name": "confirmed", "type": "bool"  },
      { "name": "created",   "type": "autodate", "onCreate": true, "onUpdate": false }
    ],
    "indexes": ["CREATE UNIQUE INDEX `idx_supports_email` ON `supports` (`email`)"]
  }'
```

## Crear un apoyo (ejemplo)

```bash
curl -s -X POST "$PB_URL/api/collections/supports/records" \
  -H "Content-Type: application/json" \
  -d '{"email":"persona@example.eu","country":"ES","locale":"es","confirmed":false}'
```

> Por defecto, las reglas de acceso de la colección son restrictivas (solo admin).
> Si quieres permitir altas públicas desde la web, ajusta la *create rule* de
> `supports` en el panel `/_/` según tu política.

## Notas de seguridad

- Nunca subas `pb_data/`, `.env` ni el `docker-compose.yml` real con dominios.
- Cambia `PB_ADMIN_PASSWORD` antes de exponer el servicio.
