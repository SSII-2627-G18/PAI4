# PAI 4 · DevSecOps (equipo G18)

Pipeline CI/CD con pruebas de seguridad automatizadas sobre OWASP Juice Shop.

## Diseño (v1, previo a la implementación)

| Diagrama | Fichero |
|---|---|
| Pipeline DevSecOps (objetivo 1.a) | [docs/diagramas/pipeline-v1.svg](docs/diagramas/pipeline-v1.svg) |
| Flujo ante una vulnerabilidad (objetivo 1.b) | [docs/diagramas/flujo-vulnerabilidad-v1.svg](docs/diagramas/flujo-vulnerabilidad-v1.svg) |

Herramientas previstas: Semgrep (SAST), Trivy config (IaC), ZAP (DAST) y DefectDojo (gestión de vulnerabilidades).
Quality gates: A en modo aviso (tras el análisis) y B bloqueante (tras el DAST).

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| `app/juice-shop/` | Código de OWASP Juice Shop fijado en la v20.4.0 (ver [app/UPSTREAM.md](app/UPSTREAM.md)). |
| `k8s/deployment.yaml` | Manifiesto de Kubernetes **inseguro a propósito**, objetivo del análisis de IaC. No se despliega. |
| `.github/workflows/devsecops.yml` | Pipeline de GitHub Actions: build → Semgrep + Trivy → gate A (aviso) → ZAP → gate B (bloqueante) → deploy simulado, más un job de avisos al equipo. |
| `scripts/gate.py` | Evalúa los informes contra el umbral de cada quality gate. |
| `scripts/avisos.sh` | Avisa al equipo del resultado de los gates: comentario en la PR o, en un push, en el commit (menciona a su autor). |
| `scripts/defectdojo_*.sh/.py` | Importan a DefectDojo los informes de una ejecución (API) y aplican el triaje como código (reglas y justificaciones versionadas). Se ejecutan a mano contra el DefectDojo local; no forman parte del pipeline. |
| `ci/defectdojo/docker-compose.yml` | DefectDojo mínimo y desechable (v3.5.202), de cuando el pipeline levantaba una instancia efímera. Hoy no lo usa el pipeline; se conserva para poder recuperarlo. |
| `docs/diagramas/` | Diagramas de diseño del pipeline. |
| `docs/correspondencia-diagramas.md` | Dónde está implementado cada elemento de los dos diagramas. |
| `docs/triaje.md` | Flujo de triaje, decisiones aplicadas y ajustes de reglas de las herramientas. |

## Configuración necesaria en GitHub

- **Secretos:** ahora no hace falta ninguno. Si el pipeline llegara a importar a un DefectDojo accesible desde Internet, harían falta `DEFECTDOJO_URL` y `DEFECTDOJO_TOKEN`.
- **Entorno `production`** (Settings → Environments): añadir revisores obligatorios para que el despliegue exija aprobación manual.
- Las herramientas se ejecutan como imágenes Docker fijadas por digest y las actions por hash de commit.

## DefectDojo (local)

Los informes de cada ejecución se guardan como artefactos (`report-semgrep`, `report-trivy`, `report-zap`). Se importan al DefectDojo local así:

```bash
DD_URL=http://127.0.0.1:8082 DD_TOKEN=<token> REPORTS=<carpeta con los informes> bash scripts/defectdojo_import.sh
DD_URL=http://127.0.0.1:8082 DD_TOKEN=<token> python3 scripts/defectdojo_triaje.py
```

La aplicación es vulnerable a propósito: solo se analiza la versión desplegada por el propio equipo.

> Los diagramas deben mantenerse coherentes con lo implementado; si el diseño cambia, se actualizan y se explica el motivo en el informe.
