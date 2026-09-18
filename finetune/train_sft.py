#!/usr/bin/env python3
import argparse
from pathlib import Path

from datasets import load_dataset
from trl import SFTConfig, SFTTrainer
from unsloth import FastLanguageModel, is_bfloat16_supported

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
    p = argparse.ArgumentParser(description="Monga memory-grounding SFT with QLoRA")
    p.add_argument("--model", default="Qwen/Qwen3-0.6B")
    p.add_argument("--output-dir", default="finetune/runs/qwen3-0.6b-memory-sft")
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
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    dataset = load_dataset(
        "json",
        data_files={
            "train": str(root / "data" / "train.jsonl"),
            "validation": str(root / "data" / "validation.jsonl"),
        },
    )

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.model,
        max_seq_length=args.max_seq_length,
        load_in_4bit=True,
        full_finetuning=False,
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
        warmup_ratio=0.05,
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
        assistant_only_loss=True,
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
