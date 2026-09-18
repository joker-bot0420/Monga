# Monga fine-tuning dataset schema

Each JSONL row is one supervised conversational example.

```json
{
  "id": "train-001",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "..."}
  ],
  "tags": ["episodic", "recent", "entailment"]
}
```

Rules:
- `messages` must contain exactly one system, one user, and one assistant message in that order for the seed set.
- The assistant answer is the supervised target.
- `tags` are metadata only and are not shown to the model.
- Public committed examples must be synthetic. Do not commit real user memories, private logs, health data, credentials, or personal identifiers.
- `train.jsonl` and `validation.jsonl` are used during SFT.
- `heldout.jsonl` must never be passed to the trainer. It exists only for post-training behavioral comparison.
