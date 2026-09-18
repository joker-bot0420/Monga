#!/usr/bin/env python3
import argparse
import gc
import json
from pathlib import Path

import unsloth
import torch
from unsloth import FastLanguageModel


def parse_args():
    p = argparse.ArgumentParser(description="Compare Monga v1 and v2 adapters on 20 held-out prompts.")
    p.add_argument("--v1-adapter", default="/content/monga-qwen3-0.6b-memory-sft/adapter")
    p.add_argument("--v2-adapter", default="/content/monga-qwen3-0.6b-memory-sft-v2/adapter")
    p.add_argument("--heldout", default="finetune/data/heldout.jsonl")
    p.add_argument("--heldout-no-memory", default="finetune/data/heldout_no_memory_v2.jsonl")
    p.add_argument("--output", default="/content/monga-v1-v2-comparison.json")
    p.add_argument("--max-seq-length", type=int, default=1024)
    p.add_argument("--max-new-tokens", type=int, default=128)
    return p.parse_args()


def load_rows(paths):
    rows = []
    for path in paths:
        with Path(path).open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    rows.append(json.loads(line))
    return rows


def generate(source, rows, args):
    print(f"\n=== loading: {source} ===")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=str(source),
        max_seq_length=args.max_seq_length,
        load_in_4bit=True,
        full_finetuning=False,
    )
    FastLanguageModel.for_inference(model)

    answers = {}
    for row in rows:
        messages = row["messages"][:-1]
        prompt = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=False,
        )
        inputs = tokenizer(
            prompt,
            return_tensors="pt",
            add_special_tokens=False,
        ).to("cuda")

        with torch.inference_mode():
            output = model.generate(
                **inputs,
                max_new_tokens=args.max_new_tokens,
                do_sample=False,
                use_cache=True,
                pad_token_id=tokenizer.eos_token_id,
            )

        generated = output[0, inputs["input_ids"].shape[1]:]
        answer = tokenizer.decode(generated, skip_special_tokens=True).strip()
        answers[row["id"]] = answer
        print(f"[{row['id']}] {answer}")

    del model
    del tokenizer
    gc.collect()
    torch.cuda.empty_cache()
    return answers


def main():
    args = parse_args()
    rows = load_rows([args.heldout, args.heldout_no_memory])

    if len(rows) != 20:
        raise RuntimeError(f"Expected 20 held-out examples, got {len(rows)}.")

    for path in [args.v1_adapter, args.v2_adapter]:
        if not Path(path).exists():
            raise FileNotFoundError(f"Adapter not found: {path}")

    v1 = generate(args.v1_adapter, rows, args)
    v2 = generate(args.v2_adapter, rows, args)

    comparisons = []
    for row in rows:
        item = {
            "id": row["id"],
            "tags": row.get("tags", []),
            "user": row["messages"][-2]["content"],
            "expected": row["messages"][-1]["content"],
            "v1": v1[row["id"]],
            "v2": v2[row["id"]],
        }
        comparisons.append(item)

    output_path = Path(args.output)
    output_path.write_text(
        json.dumps(comparisons, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print("\n=== V1 VS V2 HELD-OUT COMPARISON ===")
    for item in comparisons:
        print(f"\n{item['id']}")
        print(f"Q: {item['user']}")
        print(f"EXPECTED: {item['expected']}")
        print(f"V1: {item['v1']}")
        print(f"V2: {item['v2']}")

    print(f"\nsaved comparison: {output_path}")


if __name__ == "__main__":
    main()
