"""
Convert OpenAI CLIP BPE vocabulary to JSON format for Dart tokenizer.

Input: bpe_simple_vocab_16e6.txt (from OpenAI CLIP repo)
Output: bpe_vocab.json with {"encoder": {...}, "merges": [...]}
"""

import json
import sys
import os

def bytes_to_unicode():
    """Construct the byte-to-unicode mapping used by CLIP tokenizer."""
    bs = (
        list(range(ord("!"), ord("~") + 1))
        + list(range(ord("\xa1"), ord("\xac") + 1))
        + list(range(ord("\xae"), ord("\xff") + 1))
    )
    cs = list(bs)
    n = 0
    for b in range(2**8):
        if b not in bs:
            bs.append(b)
            cs.append(2**8 + n)
            n += 1
    cs = [chr(c) for c in cs]
    return dict(zip(bs, cs))

def build_encoder_and_merges(vocab_path):
    """Build encoder dict and merges list from BPE vocab file."""
    with open(vocab_path, 'r', encoding='utf-8') as f:
        lines = f.read().strip().split('\n')

    # First line is a version header, skip it.
    # Standard CLIP uses 49152 - 256 - 2 = 48894 merges
    # (256 base bytes + 256 </w> bytes + 48894 merges + 2 special = 49408 total)
    num_merges = 49152 - 256 - 2
    merges = []
    for line in lines[1:num_merges + 1]:
        stripped = line.strip()
        parts = stripped.split(' ')
        if len(parts) == 2:
            merges.append(stripped)

    # Build encoder: byte-level BPE tokens
    byte2unicode = bytes_to_unicode()
    vocab = list(byte2unicode.values())
    vocab += [v + '</w>' for v in vocab]

    for merge in merges:
        first, second = merge.split(' ')
        vocab.append(first + second)

    # Add special tokens
    vocab.extend(['<|startoftext|>', '<|endoftext|>'])

    encoder = {token: i for i, token in enumerate(vocab)}

    return encoder, merges

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_path = '/tmp/bpe_simple_vocab_16e6.txt'
    output_path = os.path.join(script_dir, '..', 'assets', 'tokenizer', 'bpe_vocab.json')

    if not os.path.exists(input_path):
        print(f"Error: {input_path} not found.")
        print("Download it first:")
        print("  curl -sL https://raw.githubusercontent.com/openai/CLIP/main/clip/bpe_simple_vocab_16e6.txt.gz | gunzip > /tmp/bpe_simple_vocab_16e6.txt")
        sys.exit(1)

    print(f"Reading: {input_path}")
    encoder, merges = build_encoder_and_merges(input_path)

    output = {
        "encoder": encoder,
        "merges": merges,
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False)

    print(f"Written: {output_path}")
    print(f"  Encoder size: {len(encoder)} tokens")
    print(f"  Merges count: {len(merges)} rules")

if __name__ == '__main__':
    main()
