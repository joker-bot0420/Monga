#!/usr/bin/env python3
import argparse
import gc
import json
from pathlib import Path

import unsloth
import torch
from unsloth import FastLanguageModel


def parse_args():
    p = argparse.ArgumentParser(
        description="Compare base Qwen3 against a Monga LoRA adapter on held-out examples."
    )
    p.add_argument("--base-model", default="Qwen/Qwen3-0.6B")
    p.add_argument(
        "--adapter",
        default="/content/monga-qwen3-0.6b-memory-sft/adapter",
    )
    p.add_argument(
        "--heldout",
        default="finetune/data/heldout.jsonl",
    )
    p.add_argument(
        "--output",
        default="/content/monga-heldout-comparison.json",
    )
    p.add_argument("--max-seq-length", type=int, default=1024)
    p.add_argument("--max-new-tokens", type=int, default=128)
    p.add_argument("--seed", type=int, default=3407)
    return p.parse_args()


def load_rows(path):
    rows = []
    with Path(path).open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def generate_for_source(source, rows, args):
    print(f"\n=== loading: {source} ===")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=source,
        max_seq_length=args.max_seq_length,
        load_in_4bit=True,
        full_finetuning=False,
    )
    FastLanguageModel.for_inference(model)

    answers = []
    for index, row in enumerate(rows):
        messages = row["messages"][:-1]
        expected = row["messages"][-1]["content"]

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

        seed = args.seed + index
        torch.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)

        with torch.inference_mode():
            output = model.generate(
                **inputs,
                max_new_tokens=args.max_new_tokens,
                do_sample=True,
                temperature=0.7,
                top_p=0.8,
                top_k=20,
                use_cache=True,
                pad_token_id=tokenizer.eos_token_id,
            )

        generated = output[0, inputs["input_ids"].shape[1]:]
        answer = tokenizer.decode(
            generated,
            skip_special_tokens=True,
        ).strip()

        answers.append(
            {
                "id": row["id"],
                "user": messages[-1]["content"],
                "expected": expected,
                "answer": answer,
            }
        )
        print(f"[{row['id']}] {answer}")

    del model
    del tokenizer
    gc.collect()
    torch.cuda.empty_cache()
    return answers


def main():
    args = parse_args()
    rows = load_rows(args.heldout)
    if not rows:
        raise RuntimeError("Held-out dataset is empty.")

    adapter_path = Path(args.adapter)
    if not adapter_path.exists():
        raise FileNotFoundError(f"Adapter not found: {adapter_path}")

    base_answers = generate_for_source(args.base_model, rows, args)
    tuned_answers = generate_for_source(str(adapter_path), rows, args)

    comparisons = []
    for row, base, tuned in zip(rows, base_answers, tuned_answers):
        comparisons.append(
            {
                "id": row["id"],
                "tags": row.get("tags", []),
                "user": base["user"],
                "expected": base["expected"],
                "base_answer": base["answer"],
                "tuned_answer": tuned["answer"],
            }
        )

    output_path = Path(args.output)
    output_path.write_text(
        json.dumps(comparisons, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print("\n=== HELD-OUT COMPARISON ===")
    for item in comparisons:
        print(f"\n{item['id']}")
        print(f"Q: {item['user']}")
        print(f"EXPECTED: {item['expected']}")
        print(f"BASE: {item['base_answer']}")
        print(f"TUNED: {item['tuned_answer']}")

    print(f"\nsaved comparison: {output_path}")


if __name__ == "__main__":
    main()
