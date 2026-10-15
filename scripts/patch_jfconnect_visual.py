#!/usr/bin/env python3
"""Correctif OSS de laboratoire uniquement, sans impact sur les volumes sources."""
import shutil
import sys
from pathlib import Path

import yaml

p = Path(sys.argv[1])
data = yaml.safe_load(p.read_text(encoding="utf-8"))
assert isinstance(data, dict)
settings = data.setdefault("jfconnect", {})
assert isinstance(settings, dict)
settings["enabled"] = False
shutil.copy2(p, p.with_name("system.yaml.jfconnect-original"))
p.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")
print("JFConnect desactive dans la configuration OSS du volume clone.")
