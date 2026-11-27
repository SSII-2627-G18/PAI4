#!/usr/bin/env bash
# Configura la instancia de DefectDojo para que el diagrama 1.b se cumpla tal como está dibujado.
#
# Activa la DEDUPLICACIÓN: por defecto viene desactivada y, sin ella, un hallazgo repetido en otro test no se
# marca como Duplicate. Es idempotente: se puede ejecutar varias veces.
#
# Variables de entorno: DD_URL (URL base, sin barra final) y DD_TOKEN (token de la API).
set -euo pipefail
: "${DD_URL:?falta DD_URL}"
: "${DD_TOKEN:?falta DD_TOKEN}"

curl -fsS -X PATCH "$DD_URL/api/v2/system_settings/1/" \
  -H "Authorization: Token $DD_TOKEN" -H "Content-Type: application/json" \
  -d '{"enable_deduplication": true}' -o /dev/null
echo "Deduplicación activada en $DD_URL"
