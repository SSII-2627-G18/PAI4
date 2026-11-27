# Triaje de hallazgos

Triar es revisar cada hallazgo y decidir qué hacer con él, dejando una justificación. Corresponde al paso 3 del
[diagrama de flujo](diagramas/flujo-vulnerabilidad-v2.svg).

## Cómo funciona en este proyecto

1. El pipeline importa los informes a DefectDojo por la API (job `defectdojo`, con `scripts/defectdojo_import.sh`).
2. El triaje automático (`scripts/defectdojo_triaje.py`, ejecutado contra el DefectDojo local) aplica las decisiones del equipo y deja una nota con la justificación en cada hallazgo.
3. El equipo revisa el resultado en DefectDojo y corrige lo que no comparta. Los hallazgos sin triar quedan *Active* para decidir.
4. Si un hallazgo es un **falso positivo**: se marca como tal con su justificación **y se ajusta la regla de la herramienta** para que deje de aparecer.
5. Si es una **vulnerabilidad real**: se corrige el código o la dependencia y se hace commit; el pipeline vuelve a ejecutarse.

Las reglas del triaje automático son **propuestas del equipo**: hay que revisarlas y asumirlas, no darlas por buenas sin más.

## Decisiones aplicadas

| Decisión | Hallazgos | Criterio | Dónde está |
|---|---|---|---|
| Falso positivo | 4 (Semgrep, High) | Fragmentos de código de ayuda de los retos de Juice Shop (`data/static/codefixes`). Se muestran como texto en la aplicación y nunca se ejecutan, aunque contienen patrones de inyección SQL a propósito. | `defectdojo_triaje.py` y ajuste de Semgrep |
| Fuera de alcance | 94 (84 Trivy, 10 Semgrep) | Terraform de AWS y ficheros de prueba de Juice Shop que el equipo no despliega (el despliegue es con Docker). | `defectdojo_triaje.py` |
| Verificado | 25 | Vulnerabilidades reales: inyección SQL en `login.ts` y `search.ts`, `eval` en `userProfile.ts`, secreto JWT incrustado, nuestro manifiesto de Kubernetes inseguro a propósito, y las alertas de ZAP sobre CSP y configuración cross-domain. | `defectdojo_triaje.py` |

Los «fuera de alcance» **se mantienen visibles** en DefectDojo (no se excluyen del análisis): se decidió así para que quede constancia de qué se
descartó y por qué. Solo los falsos positivos se excluyen del análisis.

## Ajustes de reglas realizados

| Fecha | Herramienta | Ajuste | Efecto medido |
|---|---|---|---|
| 23-nov-2026 | Semgrep | `--exclude` de los 4 ficheros de `codefixes` con falsos positivos (job `sast`) | De 30 a 26 hallazgos; los High pasan de 7 a 3. El resto no cambia. |

Para excluir en Semgrep se usa `--exclude` en la propia llamada, que **se suma** a lo que Semgrep ignora por defecto. Un fichero
`.semgrepignore` propio no sirve aquí: reemplaza los patrones por defecto y haría analizar ficheros que hoy se omiten.

## Cómo marcar un falso positivo y ajustar la regla

1. En DefectDojo, abre el hallazgo, márcalo como *False Positive* y escribe la justificación en una nota.
2. Añade la excepción en la herramienta, con un comentario que explique por qué:
   - **Semgrep:** `--exclude '<fichero>'` en el job `sast`.
   - **Trivy:** fichero `.trivyignore` con el identificador de la regla, o `--skip-files` si es un fichero concreto.
   - **ZAP:** fichero de reglas con la alerta en `IGNORE`.
3. Añade la fila al registro de ajustes de arriba, con el efecto medido.
4. Si el hallazgo lo marca el triaje automático, actualiza también la regla correspondiente en `scripts/defectdojo_triaje.py`.
