# Correspondencia entre los diagramas y el pipeline

Cada elemento de los dos diagramas ([pipeline](diagramas/pipeline-v1.svg) y [flujo ante una vulnerabilidad](diagramas/flujo-vulnerabilidad-v2.svg))
y dónde está implementado. Todo lo que aparece en el pipeline está en un diagrama, y viceversa.

## Diagrama 1.a · Pipeline

| Elemento del diagrama | Dónde está en el repositorio |
|---|---|
| Disparador «Push o pull request a main» | `on:` de `.github/workflows/devsecops.yml` |
| Build · imagen (`docker build`) | job `build` |
| Análisis · Semgrep (SAST) → `semgrep.json` | job `sast` |
| Análisis · Trivy (IaC) → `trivy.json` | job `iac` |
| **Gate A**, modo aviso, umbral ≥1 Critical/High | job `gate-a` (pasos con `continue-on-error`) y `scripts/gate.py` |
| Staging · Juice Shop (`docker run`) | job `dast`, paso «Staging · desplegar Juice Shop» |
| DAST · ZAP → `zap.xml` | job `dast`, paso «DAST · ZAP baseline» |
| **Gate B**, bloqueante, umbral ZAP ≥ Medium | job `gate-b`, `scripts/gate.py` y la variable `ZAP_MIN_RISK` |
| Producción, solo `main`, aprobación manual | job `deploy` y entorno `production` con revisor obligatorio |
| Job `defectdojo` (importación por API) | job `defectdojo` y `scripts/defectdojo_import.sh`; DefectDojo corre en local y se alcanza por un túnel de Cloudflare |

Nota sobre Staging: es una etapa del diagrama y un paso del workflow, no un job aparte, porque el contenedor desplegado no persiste
entre jobs de GitHub Actions; se despliega y se ataca en la misma máquina.

## Diagrama 1.b · Flujo ante una vulnerabilidad

La columna «Comprobado» indica cómo se verificó cada rama sobre el DefectDojo real del equipo.

| Elemento del diagrama | Dónde está en el repositorio | Comprobado |
|---|---|---|
| Herramienta detecta un hallazgo | jobs `sast`, `iac` y `dast` (generan el informe) | Ejecuciones de GitHub |
| ¿Supera el umbral? | `scripts/gate.py` | Gate A y B en las ejecuciones |
| «Sin bloqueo»: se importa igual | el job `defectdojo` importa todos los hallazgos, superen o no el umbral | Importación de 147 hallazgos |
| ¿Etapa bloqueante? | `gate-a` (aviso, no detiene) frente a `gate-b` (falla el job y `deploy` no se ejecuta) | Ejecuciones de GitHub |
| Modo aviso: sigue y avisa en la PR | `gate-a` y job `avisos` (comentario en la PR; en un push, en el commit) | Comentario del bot en el commit |
| Bloquea (Gate B): sin deploy, avisa al autor | `gate-b` falla; job `avisos` comenta mencionando a quien subió el cambio | Comentario del bot en el commit |
| El informe llega a DefectDojo, siempre, vía API | job `defectdojo` (`if: always()`) y `scripts/defectdojo_import.sh` | Importación por la API |
| ¿Ya existe? Sí: se actualiza, no se crea otro | `reimport-scan` de DefectDojo, que compara con los hallazgos del mismo test | Reimportar el mismo informe: 0 nuevos, 0 duplicados, 0 cambios de estado |
| Ciclo de vida: si no aparece, se cierra; si reaparece, se reabre | `close_old_findings=true` en `scripts/defectdojo_import.sh` | Quitar un hallazgo del informe lo cerró (inactivo y mitigado); al volver a importarlo se reabrió el mismo registro |
| ¿Lo repite otro test? Sí: se marca Duplicate | Deduplicación activada en DefectDojo (`scripts/defectdojo_configurar.sh`) | Importar el mismo informe como test nuevo: 26 de 26 hallazgos marcados Duplicate, apuntando al original |
| Hallazgo nuevo: se crea como Active | `reimport-scan` | Primera importación |
| ¿Qué severidad tiene? SLA de 7, 30, 90 y 120 días | Configuración de SLA de DefectDojo (la que trae por defecto) | Los hallazgos activos muestran sus días restantes: 23 (High), 83 (Medium) y 113 (Low) |
| Triaje en DefectDojo | `scripts/defectdojo_triaje.py` (reglas, se ejecuta a mano) y revisión del equipo en la interfaz | 4 falsos positivos, 94 fuera de alcance y 25 verificados |
| Falso positivo / fuera de alcance / riesgo aceptado / real | Estados de DefectDojo. El riesgo aceptado solo se fija en la interfaz, no por API | Notas de justificación en cada hallazgo |
| Corregir y commit, vuelve al inicio | manual: un nuevo `push` lanza otra vez el pipeline | n/a |

## Cosas a tener en cuenta

- **Importación a DefectDojo:** automática desde el pipeline. DefectDojo corre en el portátil del equipo y se expone con un túnel de Cloudflare
  (dirección temporal: hay que actualizar el secreto `DEFECTDOJO_URL` cada vez que se abre el túnel). Si el túnel está cerrado, el job falla y los
  informes siguen disponibles como artefactos para importarlos a mano.

- **Avisos:** en una pull request el aviso va a la propia PR; en un push, como comentario del commit con mención a quien lo subió
  (GitHub le envía un correo). Si no hay nada que atender, no se publica nada.
- **Ajuste de reglas:** hoy está aplicado en Semgrep (4 falsos positivos). Trivy y ZAP no tienen falsos positivos marcados todavía.
