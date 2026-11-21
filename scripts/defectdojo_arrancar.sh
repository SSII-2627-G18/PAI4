#!/usr/bin/env bash
# Levanta un DefectDojo efímero con ci/defectdojo/docker-compose.yml y obtiene un token de la API.
#
# - Genera contraseña y claves aleatorias en cada ejecución (nada se guarda en el repositorio).
# - Escribe DD_URL y DD_TOKEN en $GITHUB_ENV (en el CI) o en la ruta de $SALIDA (en local).
#
# Variables opcionales: DD_PORT (8080), COMPOSE_PROJECT_NAME (ddci), ESPERA_MAX_S (480)
set -euo pipefail

DIR="$(cd "$(dirname "$0")/../ci/defectdojo" && pwd)"
export DD_PORT="${DD_PORT:-8080}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-ddci}"
SALIDA="${GITHUB_ENV:-$DIR/.salida}"
ESPERA_MAX_S="${ESPERA_MAX_S:-480}"

umask 077
DD_ADMIN_PASSWORD="$(openssl rand -hex 16)"
DD_SECRET_KEY="$(openssl rand -hex 32)"
DD_CREDENTIAL_AES_256_KEY="$(openssl rand -hex 16)"   # 32 caracteres
echo "::add-mask::$DD_ADMIN_PASSWORD"
cat > "$DIR/.env" <<EOF
DD_ADMIN_PASSWORD=$DD_ADMIN_PASSWORD
DD_SECRET_KEY=$DD_SECRET_KEY
DD_CREDENTIAL_AES_256_KEY=$DD_CREDENTIAL_AES_256_KEY
EOF

docker compose -f "$DIR/docker-compose.yml" --env-file "$DIR/.env" up -d

URL="http://127.0.0.1:$DD_PORT"
echo "Esperando a DefectDojo en $URL ..."
inicio=$SECONDS
until [ "$(curl -s -o /dev/null -w '%{http_code}' "$URL/login" || true)" = "200" ]; do
  if [ $((SECONDS - inicio)) -gt "$ESPERA_MAX_S" ]; then
    echo "::error::DefectDojo no arrancó en ${ESPERA_MAX_S}s"
    docker compose -f "$DIR/docker-compose.yml" --env-file "$DIR/.env" logs --tail 40
    exit 1
  fi
  sleep 3
done
echo "DefectDojo listo en $((SECONDS - inicio)) s"

# El token se pide por stdin para que la contraseña no aparezca en la lista de procesos.
TOKEN="$(printf '{"username":"admin","password":"%s"}' "$DD_ADMIN_PASSWORD" \
  | curl -fsS -X POST "$URL/api/v2/api-token-auth/" -H 'Content-Type: application/json' --data @- \
  | python3 -c 'import sys, json; print(json.load(sys.stdin)["token"])')"
echo "::add-mask::$TOKEN"

{
  echo "DD_URL=$URL"
  echo "DD_TOKEN=$TOKEN"
} >> "$SALIDA"
echo "Token obtenido y guardado en $SALIDA"
