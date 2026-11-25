#!/usr/bin/env bash
# Avisa al equipo del resultado de los quality gates (paso "se avisa" del diagrama 1.b).
#
# - Pull request  -> comentario en la propia PR.
# - Push / manual -> comentario en el commit, mencionando a quien lo ha subido (GitHub le envía un correo).
# Solo avisa si hay algo que atender: avisos del Gate A o bloqueo del Gate B.
#
# Entradas por variables de entorno (las rellena el workflow):
#   EVENTO, PR_NUM, ACTOR, SHA, REPO, RUN_URL
#   A_SEMGREP_SOBRE, A_SEMGREP_DETALLE, A_TRIVY_SOBRE, A_TRIVY_DETALLE   (Gate A)
#   B_RESULTADO (success|failure|skipped|cancelled), B_ZAP_SOBRE, B_ZAP_DETALLE   (Gate B)
#   DD_IMPORTADO (true si el job de DefectDojo importó los informes)
#   AVISOS_DRY_RUN=1  -> imprime el mensaje en vez de publicarlo (para probar en local)
set -euo pipefail

A_SEMGREP_SOBRE="${A_SEMGREP_SOBRE:-0}"
A_TRIVY_SOBRE="${A_TRIVY_SOBRE:-0}"
B_RESULTADO="${B_RESULTADO:-skipped}"
ACTOR="${ACTOR:-equipo}"

if [ "$A_SEMGREP_SOBRE" = "0" ] && [ "$A_TRIVY_SOBRE" = "0" ] && [ "$B_RESULTADO" = "success" ]; then
  echo "Sin avisos que comunicar: todos los controles han pasado."
  exit 0
fi

fila_a() {  # $1 = herramienta, $2 = nº sobre el umbral, $3 = detalle
  if [ "$2" = "0" ]; then echo "| $1 | Aviso | OK, sin hallazgos Critical/High |"
  else echo "| $1 | Aviso | **$2 hallazgos Critical/High** ($3). El pipeline continúa. |"; fi
}

case "$B_RESULTADO" in
  success)   fila_b="| Gate B · ZAP (DAST) | Bloqueante | OK, no supera el umbral |" ;;
  failure)   fila_b="| Gate B · ZAP (DAST) | Bloqueante | **BLOQUEADO**: ${B_ZAP_SOBRE:-?} alertas sobre el umbral (${B_ZAP_DETALLE:-sin detalle}). El pipeline se ha detenido y **no se despliega**. |" ;;
  *)         fila_b="| Gate B · ZAP (DAST) | Bloqueante | No se ha ejecutado (falló una etapa anterior) |" ;;
esac

if [ "${DD_IMPORTADO:-}" = "true" ]; then
  linea_dd="Los hallazgos se han importado automáticamente a DefectDojo, donde quedan para triarlos (ver \`docs/triaje.md\`). Los informes también están como artefactos de la [ejecución](${RUN_URL:-#})."
else
  linea_dd="No se ha podido importar a DefectDojo en esta ejecución (¿túnel cerrado o secretos sin configurar?). Los informes están como artefactos de la [ejecución](${RUN_URL:-#}) y se pueden importar a mano con \`scripts/defectdojo_import.sh\`."
fi

cuerpo="## Resultado del pipeline de seguridad

@${ACTOR}, este es el resultado para \`${SHA:0:7}\`:

| Control | Modo | Resultado |
|---|---|---|
$(fila_a "Gate A · Semgrep (SAST)" "$A_SEMGREP_SOBRE" "${A_SEMGREP_DETALLE:-}")
$(fila_a "Gate A · Trivy (IaC)" "$A_TRIVY_SOBRE" "${A_TRIVY_DETALLE:-}")
${fila_b}

${linea_dd}
Si algún hallazgo es un falso positivo, se marca en DefectDojo con su justificación y se ajusta la regla de la herramienta."

if [ "${AVISOS_DRY_RUN:-0}" = "1" ]; then
  printf '%s\n' "$cuerpo"
  exit 0
fi

export GH_REPO="$REPO"
if [ "${EVENTO:-}" = "pull_request" ] && [ -n "${PR_NUM:-}" ]; then
  gh pr comment "$PR_NUM" --body "$cuerpo"
  echo "Aviso publicado en la pull request #$PR_NUM"
else
  gh api "repos/$REPO/commits/$SHA/comments" -f body="$cuerpo" >/dev/null
  echo "Aviso publicado en el commit ${SHA:0:7}"
fi
