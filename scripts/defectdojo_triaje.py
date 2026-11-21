#!/usr/bin/env python3
"""Triaje como código: aplica en DefectDojo las decisiones del equipo y exporta los resultados.

Variables de entorno: DD_URL (URL base) y DD_TOKEN (token de la API).
Uso: defectdojo_triaje.py [--salida reports/defectdojo-hallazgos.json]

Las reglas están en `decidir()`. Cada decisión deja una nota con su justificación en el hallazgo.
Así el triaje queda versionado en el repositorio y se repite igual en cada ejecución.
(El estado "riesgo aceptado" DefectDojo solo permite fijarlo desde su interfaz, no por API.)
"""
import argparse
import collections
import json
import os
import sys
import urllib.request

URL = os.environ["DD_URL"].rstrip("/") + "/api/v2"
TOKEN = os.environ["DD_TOKEN"]
HERRAMIENTAS = {"Semgrep JSON Report": "Semgrep", "Trivy Scan": "Trivy", "ZAP Scan": "ZAP"}


def api(metodo, ruta, cuerpo=None):
    req = urllib.request.Request(
        URL + ruta, method=metodo,
        data=json.dumps(cuerpo).encode() if cuerpo is not None else None,
        headers={"Authorization": "Token " + TOKEN, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def listar(ruta):
    """Recorre todas las páginas de un listado de la API."""
    sep = "&" if "?" in ruta else "?"
    siguiente, salida = f"{ruta}{sep}limit=200", []
    while siguiente:
        datos = api("GET", siguiente)
        salida += datos["results"]
        siguiente = datos["next"].replace(URL, "") if datos.get("next") else None
    return salida


def decidir(hallazgo, herramienta):
    """Devuelve (estado, justificación) o None si el hallazgo no se tria automáticamente."""
    ruta, titulo, sev = hallazgo.get("file_path") or "", hallazgo["title"], hallazgo["severity"]
    if herramienta == "Semgrep" and "data/static/codefixes/" in ruta and "iacLeaked" not in ruta:
        return ("false_p", "Falso positivo: fragmento de código de ayuda de un reto de Juice Shop. "
                "Se sirve como texto en la interfaz y nunca se ejecuta en la aplicación.")
    if any(x in ruta for x in ("iacLeakedKeyChallenge", "terraform/networking.tf", "test/smoke/Dockerfile")):
        return ("out_of_scope", "Fuera de alcance: Terraform de AWS y ficheros de prueba de Juice Shop que el "
                "equipo no despliega (el despliegue es con Docker). No afectan al entorno analizado.")
    if herramienta == "Semgrep" and sev == "High":
        return ("verified", "Verdadero positivo: consulta o código construido con datos del usuario. "
                "Vulnerabilidad real (intencionada en Juice Shop).")
    if herramienta == "Semgrep" and "hardcoded-jwt-secret" in titulo:
        return ("verified", "Verdadero positivo: secreto JWT incrustado en el código (intencionado en Juice Shop).")
    if herramienta == "Trivy" and ruta.startswith("k8s/"):
        return ("verified", "Verdadero positivo: manifiesto de K8s del equipo, inseguro a propósito "
                "para demostrar la detección de IaC.")
    if herramienta == "ZAP" and ("Content Security Policy" in titulo or "Cross-Domain" in titulo):
        return ("verified", "Verdadero positivo: configuración ausente confirmada en la respuesta real de la app.")
    return None


PARCHES = {
    "false_p": {"false_p": True, "active": False, "verified": False},
    "out_of_scope": {"out_of_scope": True, "active": False},
    "verified": {"verified": True},
}


def estado(h):
    if h["false_p"]:
        return "Falso positivo"
    if h["out_of_scope"]:
        return "Fuera de alcance"
    if not h["active"]:
        return "Inactivo"
    return "Activo verificado" if h["verified"] else "Activo sin triar"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--salida", default="reports/defectdojo-hallazgos.json")
    args = p.parse_args()

    tests = {t["id"]: HERRAMIENTAS.get(t["title"], t["title"]) for t in listar("/tests/")}
    aplicados = collections.Counter()
    for h in listar("/findings/"):
        d = decidir(h, tests.get(h["test"], ""))
        if not d:
            continue
        est, nota = d
        api("PATCH", f"/findings/{h['id']}/", PARCHES[est])
        api("POST", f"/findings/{h['id']}/notes/", {"entry": nota})
        aplicados[est] += 1
    print("Triaje aplicado:", dict(aplicados))

    # Exportación: todos los hallazgos con su estado final, y un resumen para el job.
    hallazgos = listar("/findings/")
    os.makedirs(os.path.dirname(args.salida) or ".", exist_ok=True)
    with open(args.salida, "w", encoding="utf-8") as f:
        json.dump([{"herramienta": tests.get(h["test"]), "severidad": h["severity"], "titulo": h["title"],
                    "fichero": h.get("file_path"), "estado": estado(h)} for h in hallazgos],
                  f, ensure_ascii=False, indent=1)
    cuenta = collections.Counter((tests.get(h["test"], "?"), estado(h)) for h in hallazgos)
    filas = "\n".join(f"| {t} | {e} | {n} |" for (t, e), n in sorted(cuenta.items()))
    resumen = (f"### DefectDojo · resultado del triaje\n\nTotal: **{len(hallazgos)}** hallazgos.\n\n"
               f"| Herramienta | Estado | Hallazgos |\n|---|---|---|\n{filas}\n")
    print(resumen)
    destino = os.environ.get("GITHUB_STEP_SUMMARY")
    if destino:
        with open(destino, "a", encoding="utf-8") as f:
            f.write(resumen + "\n")


if __name__ == "__main__":
    sys.exit(main())
