# ledger-entry v0 fixtures

Conforming and negative fixtures for
`schemas/agentic/v0/ledger-entry.schema.json`.

- **conforming/** — must validate
- **negative/** — must fail validation

Synthetic engagement codename: `fixture-eng` (never a real engagement).

Validate with any JSON Schema 2020-12 checker (e.g. `jsonschema` CLI, or the
consumer's embedded validator). Example with Python:

```bash
python3 - <<'PY'
import json, pathlib, sys
from jsonschema import Draft202012Validator
root = pathlib.Path(__file__).resolve().parent
schema = json.loads((root.parent / "ledger-entry.schema.json").read_text())
v = Draft202012Validator(schema)
ok = True
for path in sorted((root / "conforming").glob("*.json")):
    inst = json.loads(path.read_text())
    errs = sorted(v.iter_errors(inst), key=lambda e: e.path)
    if errs:
        ok = False
        print(f"FAIL conforming {path.name}: {errs[0].message}")
    else:
        print(f"ok  conforming {path.name}")
for path in sorted((root / "negative").glob("*.json")):
    inst = json.loads(path.read_text())
    errs = list(v.iter_errors(inst))
    if not errs:
        ok = False
        print(f"FAIL negative {path.name}: expected rejection")
    else:
        print(f"ok  negative {path.name}")
sys.exit(0 if ok else 1)
PY
```
