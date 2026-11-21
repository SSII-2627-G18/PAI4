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
| `.github/workflows/devsecops.yml` | Pipeline de GitHub Actions: build → Semgrep + Trivy → gate A (aviso) → ZAP → gate B (bloqueante) → deploy simulado, y un job final que levanta un DefectDojo efímero, importa los informes, aplica el triaje y exporta los hallazgos. |
| `scripts/gate.py` | Evalúa los informes contra el umbral de cada quality gate. |
| `scripts/defectdojo_*.sh/.py` | Arrancan DefectDojo efímero, importan los informes por API y aplican el triaje como código (reglas y justificaciones versionadas). |
| `ci/defectdojo/docker-compose.yml` | DefectDojo mínimo (v3.5.202) que se levanta dentro del runner de GitHub y desaparece al acabar el job. |
| `docs/diagramas/` | Diagramas de diseño del pipeline. |

## Configuración necesaria en GitHub

- **Secretos (opcionales)** (Settings → Secrets and variables → Actions): `DEFECTDOJO_URL` y `DEFECTDOJO_TOKEN`. Sin ellos, el pipeline usa un DefectDojo efímero dentro del runner; con ellos, importa en esa instancia externa.
- **Entorno `production`** (Settings → Environments): añadir revisores obligatorios para que el despliegue exija aprobación manual.
- Las herramientas se ejecutan como imágenes Docker fijadas por digest y las actions por hash de commit.

La aplicación es vulnerable a propósito: solo se analiza la versión desplegada por el propio equipo.

> Los diagramas deben mantenerse coherentes con lo implementado; si el diseño cambia, se actualizan y se explica el motivo en el informe.
