#!/usr/bin/env python3
import argparse
from pathlib import Path

import unsloth
from unsloth import FastLanguageModel, is_bfloat16_supported
from datasets import load_dataset
from trl import SFTConfig, SFTTrainer

TARGET_MODULES = [
    "q_proj",
    "k_proj",
    "v_proj",
    "o_proj",
    "gate_proj",
    "up_proj",
    "down_proj",
]


def parse_args():
    p = argparse.ArgumentParser(description="Monga v4 polarity-balanced memory-grounding SFT with QLoRA")
    p.add_argument("--model", default="Qwen/Qwen3-0.6B")
    p.add_argument("--output-dir", default="finetune/runs/qwen3-0.6b-memory-sft-v4")
    p.add_argument("--max-seq-length", type=int, default=1024)
    p.add_argument("--epochs", type=float, default=3.0)
    p.add_argument("--batch-size", type=int, default=1)
    p.add_argument("--grad-accum", type=int, default=4)
    p.add_argument("--learning-rate", type=float, default=2e-4)
    p.add_argument("--lora-r", type=int, default=16)
    p.add_argument("--lora-alpha", type=int, default=16)
    p.add_argument("--seed", type=int, default=3407)
    return p.parse_args()


def main():
    args = parse_args()
    root = Path(__file__).resolve().parent
    data_root = root / "data"
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    dataset = load_dataset(
        "json",
        data_files={
            "train": [
                str(data_root / "train.jsonl"),
                str(data_root / "train_balance_v3a.jsonl"),
                str(data_root / "train_balance_v3b.jsonl"),
                str(data_root / "train_polarity_v4.jsonl"),
            ],
            "validation": [
                str(data_root / "validation.jsonl"),
                str(data_root / "validation_v2.jsonl"),
                str(data_root / "validation_v3.jsonl"),
                str(data_root / "validation_v4.jsonl"),
            ],
        },
    )

    train_count = len(dataset["train"])
    validation_count = len(dataset["validation"])
    print(f"v4 train examples: {train_count}")
    print(f"v4 validation examples: {validation_count}")

    if train_count != 100:
        raise RuntimeError(f"Expected 100 v4 train examples, got {train_count}.")
    if validation_count != 26:
        raise RuntimeError(f"Expected 26 v4 validation examples, got {validation_count}.")

    def to_prompt_completion(example):
        messages = example["messages"]
        if len(messages) < 2 or messages[-1].get("role") != "assistant":
            raise ValueError("Each training example must end with one assistant message.")
        return {
            "prompt": messages[:-1],
            "completion": [messages[-1]],
        }

    for split in dataset:
        dataset[split] = dataset[split].map(
            to_prompt_completion,
            remove_columns=dataset[split].column_names,
        )

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.model,
        max_seq_length=args.max_seq_length,
        load_in_4bit=True,
        full_finetuning=False,
    )

    if tokenizer.eos_token is None or tokenizer.eos_token_id is None:
        raise RuntimeError("Tokenizer has no valid EOS token.")
    if tokenizer.pad_token is None or tokenizer.pad_token_id is None:
        raise RuntimeError("Tokenizer has no valid PAD token.")

    print(
        f"tokenizer special tokens: eos={tokenizer.eos_token!r} "
        f"(id={tokenizer.eos_token_id}), "
        f"pad={tokenizer.pad_token!r} (id={tokenizer.pad_token_id})"
    )

    model = FastLanguageModel.get_peft_model(
        model,
        r=args.lora_r,
        target_modules=TARGET_MODULES,
        lora_alpha=args.lora_alpha,
        lora_dropout=0,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=args.seed,
        use_rslora=False,
    )

    config = SFTConfig(
        output_dir=str(output_dir),
        max_length=args.max_seq_length,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=1,
        gradient_accumulation_steps=args.grad_accum,
        num_train_epochs=args.epochs,
        learning_rate=args.learning_rate,
        warmup_steps=1,
        logging_steps=1,
        eval_strategy="epoch",
        save_strategy="epoch",
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="cosine",
        seed=args.seed,
        report_to="none",
        bf16=is_bfloat16_supported(),
        fp16=not is_bfloat16_supported(),
        completion_only_loss=True,
        assistant_only_loss=False,
        eos_token=tokenizer.eos_token,
        pad_token=tokenizer.pad_token,
        packing=False,
    )

    trainer = SFTTrainer(
        model=model,
        processing_class=tokenizer,
        train_dataset=dataset["train"],
        eval_dataset=dataset["validation"],
        args=config,
    )

    trainer.train()

    adapter_dir = output_dir / "adapter"
    model.save_pretrained(str(adapter_dir))
    tokenizer.save_pretrained(str(adapter_dir))
    print(f"saved adapter: {adapter_dir}")


if __name__ == "__main__":
    main()
