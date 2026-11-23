#!/usr/bin/env python3
"""Quality gate: evalúa un informe de seguridad contra un umbral.

Uso: gate.py <semgrep|trivy|zap> <informe.json> [--min-zap-risk N]

- Cuenta los hallazgos por severidad y los muestra en el resumen del job.
- Termina con código 1 si hay al menos un hallazgo Critical/High
  (en ZAP: de riesgo >= --min-zap-risk, por defecto 3 = High).
- Si el gate está en modo aviso, el workflow lo marca con `continue-on-error`.
"""
import argparse
import collections
import json
import os
import sys

ORDEN = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]
SEMGREP = {"CRITICAL": "CRITICAL", "HIGH": "HIGH", "ERROR": "HIGH",
           "MEDIUM": "MEDIUM", "WARNING": "MEDIUM", "LOW": "LOW", "INFO": "LOW"}
ZAP = {"3": "HIGH", "2": "MEDIUM", "1": "LOW", "0": "INFO"}


def contar(herramienta, datos):
    c = collections.Counter()
    if herramienta == "semgrep":
        for r in datos.get("results", []):
            c[SEMGREP.get(str(r["extra"]["severity"]).upper(), "LOW")] += 1
    elif herramienta == "trivy":
        for res in datos.get("Results", []):
            for h in (res.get("Misconfigurations") or []) + (res.get("Vulnerabilities") or []):
                c[str(h.get("Severity", "UNKNOWN")).upper()] += 1
    elif herramienta == "zap":
        for sitio in datos.get("site", []):
            for alerta in sitio.get("alerts", []):
                c[ZAP.get(str(alerta.get("riskcode")), "INFO")] += 1
    return c


def main():
    p = argparse.ArgumentParser()
    p.add_argument("herramienta", choices=["semgrep", "trivy", "zap"])
    p.add_argument("informe")
    p.add_argument("--min-zap-risk", type=int, default=3)
    a = p.parse_args()

    try:
        with open(a.informe, encoding="utf-8") as f:
            datos = json.load(f)
    except (OSError, ValueError) as e:
        print(f"::error::No se pudo leer el informe {a.informe}: {e}")
        return 2

    c = contar(a.herramienta, datos)
    if a.herramienta == "zap":
        # ZAP solo distingue High/Medium/Low/Info: se aplica el umbral de riesgo.
        sobre = sum(n for sev, n in c.items()
                    if int({v: k for k, v in ZAP.items()}[sev]) >= a.min_zap_risk)
        umbral = f"riesgo ZAP >= {a.min_zap_risk}"
    else:
        sobre = c["CRITICAL"] + c["HIGH"]
        umbral = "Critical/High"

    filas = "\n".join(f"| {s} | {c[s]} |" for s in ORDEN if c[s])
    resumen = (f"### Gate · {a.herramienta}\n\n| Severidad | Hallazgos |\n|---|---|\n{filas}\n\n"
               f"Umbral: >=1 hallazgo {umbral}. Encontrados: **{sobre}**.\n")
    print(resumen)
    destino = os.environ.get("GITHUB_STEP_SUMMARY")
    if destino:
        with open(destino, "a", encoding="utf-8") as f:
            f.write(resumen + "\n")

    # Salidas del paso (las usa el job de avisos): cuántos superan el umbral y el detalle por severidad.
    salida = os.environ.get("GITHUB_OUTPUT")
    if salida:
        detalle = ", ".join(f"{c[s]} {s}" for s in ORDEN if c[s]) or "sin hallazgos"
        with open(salida, "a", encoding="utf-8") as f:
            f.write(f"sobre={sobre}\ndetalle={detalle}\n")

    if sobre >= 1:
        print(f"::warning::{a.herramienta}: {sobre} hallazgo(s) {umbral} superan el umbral")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
