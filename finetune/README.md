# Monga fine-tuning seed

This directory is the first narrow fine-tuning experiment for Monga's memory-grounding behavior.

## Goal

Teach a small Qwen3 model to:
1. use a retrieved episodic memory even when the user's wording differs,
2. avoid denying an event that is present in memory,
3. answer the supported part of a question,
4. avoid inventing emotions, causes, evaluations, or missing details,
5. behave sensibly when no memory evidence is supplied.

This is intentionally not a personality fine-tune and not a knowledge fine-tune.

## Seed data

- `data/train.jsonl`: 24 synthetic training examples
- `data/validation.jsonl`: 6 synthetic validation examples
- `data/heldout.jsonl`: 8 synthetic held-out behavior checks

The first supervised seed therefore contains 30 golden examples. Held-out examples are never used for gradient updates.

## Privacy

This repository is public. Never commit real personal memories or raw user conversation logs here.

Use `data/private/` for local experiments. That path is ignored by Git.

## Validate the dataset

```bash
python finetune/validate_dataset.py
```

## Training target

Start with Qwen3 0.6B. The experiment is deliberately small: first verify that the behavior moves in the desired direction before scaling the dataset or model.

Recommended first command:

```bash
python finetune/train_sft.py \
  --model Qwen/Qwen3-0.6B \
  --output-dir finetune/runs/qwen3-0.6b-memory-sft \
  --epochs 3
```

The script uses 4-bit QLoRA by default. It trains only adapter weights and uses TRL's assistant-only loss on the conversational `messages` dataset.

## First success criterion

Before training and after training, compare the same held-out prompts. The first run is successful only if memory-grounded answers improve without causing unsupported details to increase.

Do not merge a tuned model into the Android app based only on training loss.

## After the smoke run

If the 0.6B adapter improves held-out behavior:
1. expand the synthetic set to roughly 300-500 examples,
2. add manually reviewed failure-derived examples,
3. compare 0.6B vs 1.7B,
4. only then merge/export to GGUF and test on the Galaxy device.

If it does not improve, inspect data coverage and prompt format before increasing epochs.
