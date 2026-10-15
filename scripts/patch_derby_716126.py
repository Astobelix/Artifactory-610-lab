#!/usr/bin/env python3
"""Lab uniquement : isoler l'URL Derby historique dans artifactory.database."""
import os
import shutil
import sys
from pathlib import Path
import yaml

p = Path(sys.argv[1])
if not p.is_file():
    raise SystemExit(f"system.yaml absent : {p}")
config = yaml.safe_load(p.read_text(encoding="utf-8"))
if not isinstance(config, dict):
    raise SystemExit("system.yaml invalide")
shared = config.get("shared", {}).get("database", {})
if not isinstance(shared, dict):
    raise SystemExit("shared.database inattendu")
url = shared.get("url")
if not isinstance(url, str) or not url.startswith("jdbc:derby:"):
    raise SystemExit("URL Derby historique introuvable sous shared.database")
art = config.setdefault("artifactory", {})
database = art.setdefault("database", {})
if database.get("url") not in (None, url):
    raise SystemExit("Une autre URL artifactory.database existe deja")
database["url"] = url
database["type"] = shared.get("type", "derby")
database["driver"] = shared.get("driver", "org.apache.derby.jdbc.EmbeddedDriver")
for name in ("url", "type", "driver"):
    shared.pop(name, None)
shared["allowNonPostgresql"] = True
backup = p.with_suffix(".yaml.before-derby-fix")
shutil.copy2(p, backup)
with p.open("w", encoding="utf-8") as f:
    yaml.safe_dump(config, f, sort_keys=False, allow_unicode=True)
print("Derby: URL conservee sous artifactory.database ;")
print("shared.database utilise les valeurs par defaut pour Access/Topology/JFConfig.")
print("Sauvegarde locale system.yaml.before-derby-fix creee.")
