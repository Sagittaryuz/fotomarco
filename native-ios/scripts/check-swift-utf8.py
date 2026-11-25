"""Fail early if a Swift source is not valid UTF-8."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
invalid = []
for source in sorted(root.rglob("*.swift")):
    try:
        source.read_bytes().decode("utf-8")
    except UnicodeDecodeError as error:
        invalid.append(f"{source.relative_to(root)}: byte {error.start}")
if invalid:
    raise SystemExit("Swift sources must be UTF-8:\n" + "\n".join(invalid))
print("Swift sources are valid UTF-8.")
