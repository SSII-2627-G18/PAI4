# Correspondencia entre los diagramas y el pipeline

Cada elemento de los dos diagramas ([pipeline](diagramas/pipeline-v1.svg) y [flujo ante una vulnerabilidad](diagramas/flujo-vulnerabilidad-v1.svg))
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
| Job `defectdojo` (importación por API y triaje) | job `defectdojo` y `scripts/defectdojo_*` |

Nota sobre Staging: es una etapa del diagrama y un paso del workflow, no un job aparte, porque el contenedor desplegado no persiste
entre jobs de GitHub Actions; se despliega y se ataca en la misma máquina.

## Diagrama 1.b · Flujo ante una vulnerabilidad

| Elemento del diagrama | Dónde está en el repositorio |
|---|---|
| Herramienta detecta un hallazgo | jobs `sast`, `iac` y `dast` (generan el informe) |
| Informe a DefectDojo, siempre, por API | job `defectdojo` (`if: always()`) y `scripts/defectdojo_import.sh` |
| ¿Supera el umbral? | `scripts/gate.py` |
| «Sin bloqueo»: queda activo en DefectDojo | los hallazgos bajo el umbral se importan y quedan *Active* |
| ¿Etapa bloqueante? | `gate-a` (aviso, no detiene) frente a `gate-b` (falla el job y `deploy` no se ejecuta) |
| Modo aviso: sigue y avisa en la PR | `gate-a` y job `avisos` (comentario en la PR; en un push, en el commit) |
| Bloquea (Gate B): sin deploy, avisa al autor | `gate-b` falla; job `avisos` comenta mencionando a quien subió el cambio |
| Triaje en DefectDojo | `scripts/defectdojo_triaje.py` (reglas) y revisión del equipo en la interfaz |
| ¿Falso positivo? → se justifica y se ajusta | nota de justificación en DefectDojo y ajuste de la regla (ver [triaje](triaje.md)) |
| Corregir y commit, vuelve al inicio | manual: un nuevo `push` lanza otra vez el pipeline |

## Cosas a tener en cuenta

- **Avisos:** en una pull request el aviso va a la propia PR; en un push, como comentario del commit con mención a quien lo subió
  (GitHub le envía un correo). Si no hay nada que atender, no se publica nada.
- **Ajuste de reglas:** hoy está aplicado en Semgrep (4 falsos positivos). Trivy y ZAP no tienen falsos positivos marcados todavía.
