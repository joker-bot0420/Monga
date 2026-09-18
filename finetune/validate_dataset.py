#!/usr/bin/env python3
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FILES = [
    ROOT / "data" / "train.jsonl",
    ROOT / "data" / "validation.jsonl",
    ROOT / "data" / "heldout.jsonl",
]
EXPECTED_ROLES = ["system", "user", "assistant"]

def load_rows(path: Path):
    rows = []
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as e:
                raise SystemExit(f"{path}:{line_no}: invalid JSON: {e}")
            rows.append((line_no, row))
    return rows

seen_ids = set()
tag_counts = Counter()
total = 0

for path in FILES:
    rows = load_rows(path)
    print(f"{path.name}: {len(rows)} examples")
    for line_no, row in rows:
        total += 1
        row_id = row.get("id")
        if not isinstance(row_id, str) or not row_id:
            raise SystemExit(f"{path}:{line_no}: missing id")
        if row_id in seen_ids:
            raise SystemExit(f"{path}:{line_no}: duplicate id {row_id}")
        seen_ids.add(row_id)

        messages = row.get("messages")
        if not isinstance(messages, list) or len(messages) != 3:
            raise SystemExit(f"{path}:{line_no}: messages must contain exactly 3 entries")

        roles = [m.get("role") for m in messages]
        if roles != EXPECTED_ROLES:
            raise SystemExit(f"{path}:{line_no}: roles {roles} != {EXPECTED_ROLES}")

        for message in messages:
            content = message.get("content")
            if not isinstance(content, str) or not content.strip():
                raise SystemExit(f"{path}:{line_no}: empty message content")

        tags = row.get("tags", [])
        if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
            raise SystemExit(f"{path}:{line_no}: tags must be a list of strings")
        tag_counts.update(tags)

print(f"total: {total}")
print("top tags:")
for tag, count in tag_counts.most_common():
    print(f"  {tag}: {count}")
print("dataset validation: PASS")
