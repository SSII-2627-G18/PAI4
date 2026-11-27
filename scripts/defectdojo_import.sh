#!/usr/bin/env bash
# Importa los informes de seguridad a DefectDojo con la API (reimport-scan).
#
# Variables de entorno:
#   DD_URL    URL base de DefectDojo (sin barra final)       [obligatoria]
#   DD_TOKEN  Token de la API                                [obligatoria]
#   REPORTS   Carpeta con los informes (por defecto: reports)
#   DD_PRODUCT_TYPE, DD_PRODUCT, DD_ENGAGEMENT   Organización de los resultados
#
# reimport-scan crea el producto y el engagement si no existen (auto_create_context)
# y, en cada ejecución, actualiza el mismo Test de cada herramienta sin duplicar hallazgos.
set -euo pipefail

: "${DD_URL:?falta DD_URL}"
: "${DD_TOKEN:?falta DD_TOKEN}"
# Los secretos pueden llegar con espacios o saltos de línea al final (por ejemplo, al copiar y pegar la dirección):
# se limpian, y se quita la barra final de la dirección.
DD_URL="$(printf '%s' "$DD_URL" | tr -d '[:space:]')"
DD_URL="${DD_URL%/}"
DD_TOKEN="$(printf '%s' "$DD_TOKEN" | tr -d '[:space:]')"
REPORTS="${REPORTS:-reports}"
DD_PRODUCT_TYPE="${DD_PRODUCT_TYPE:-Research and Development}"
DD_PRODUCT="${DD_PRODUCT:-Juice Shop G18}"
DD_ENGAGEMENT="${DD_ENGAGEMENT:-Pipeline CI}"
BRANCH="${GITHUB_REF_NAME:-local}"
COMMIT="${GITHUB_SHA:-local}"

fallos=0
importar() {  # $1 = tipo de escaneo en DefectDojo, $2 = fichero del informe
  if [ ! -f "$2" ]; then
    echo "::warning::Falta $2, no se importa $1"
    return 0
  fi
  # --form-string para los valores de texto: nada se interpreta como fichero.
  resp="$(mktemp)"
  codigo="$(curl -sS -m 120 -X POST "$DD_URL/api/v2/reimport-scan/" \
      -H "Authorization: Token $DD_TOKEN" \
      -F "file=@$2" \
      --form-string "scan_type=$1" \
      --form-string "product_type_name=$DD_PRODUCT_TYPE" \
      --form-string "product_name=$DD_PRODUCT" \
      --form-string "engagement_name=$DD_ENGAGEMENT" \
      --form-string "test_title=$1" \
      --form-string "branch_tag=$BRANCH" \
      --form-string "commit_hash=$COMMIT" \
      --form-string "auto_create_context=true" \
      --form-string "close_old_findings=true" \
      -o "$resp" -w '%{http_code}' || true)"
  if [ "$codigo" = "201" ] || [ "$codigo" = "200" ]; then
    echo "Importado: $1"
  else
    # Se muestra el código HTTP y el comienzo de la respuesta (nunca la dirección ni el token).
    echo "::error::Falló la importación de $1 (HTTP ${codigo:-000})"
    head -c 300 "$resp" | tr -d '\r' | sed 's/^/    respuesta: /'
    echo
    fallos=$((fallos + 1))
  fi
  rm -f "$resp"
}

importar "Semgrep JSON Report" "$REPORTS/semgrep.json"
importar "Trivy Scan"          "$REPORTS/trivy.json"
importar "ZAP Scan"            "$REPORTS/zap.xml"

exit "$fallos"
