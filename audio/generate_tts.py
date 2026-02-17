#!/usr/bin/env python3
"""
M.A.S.S. Trap — TTS Audio Generator
====================================
Generates police dispatcher voice clips using OpenAI's gpt-4o-mini-tts API.

Setup:
  1. Get an OpenAI API key at https://platform.openai.com/api-keys
     (New accounts get $5 free credits — more than enough for this)
  2. Export your key:  export OPENAI_API_KEY="sk-..."
  3. Install the SDK:  pip3 install openai
  4. Run this script:  python3 generate_tts.py

The script reads clips.json, generates raw WAV files into raw/, then you
run radio_filter.sh to apply the police radio effect and convert to ESP32 format.

Voices to try (pass --voice NAME):
  onyx   — Deep, authoritative (default, best for dispatcher)
  ash    — Calm, steady
  echo   — Neutral, clear
  nova   — Warm, slightly softer
  alloy  — Balanced

You can also customize the voice instruction (pass --instruction "...").
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLIPS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "clips.json")
RAW_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")

DEFAULT_VOICE = "onyx"
DEFAULT_MODEL = "gpt-4o-mini-tts"

DEFAULT_INSTRUCTION = (
    "Speak as a calm authoritative police radio dispatcher with clipped cadence "
    "and clear enunciation, professional and slightly tense, like calling out a "
    "pursuit over the radio, short pauses between phrases, no filler words"
)

# ---------------------------------------------------------------------------
# OpenAI TTS via raw HTTP (no SDK dependency)
# ---------------------------------------------------------------------------
def generate_clip_raw_http(api_key, text, voice, instruction, model, output_path):
    """Generate a single TTS clip using urllib (no openai package needed)."""
    url = "https://api.openai.com/v1/audio/speech"

    payload = json.dumps({
        "model": model,
        "input": text,
        "voice": voice,
        "instructions": instruction,
        "response_format": "wav"
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Authorization", "Bearer " + api_key)
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            audio_data = resp.read()
            with open(output_path, "wb") as f:
                f.write(audio_data)
            return len(audio_data)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("  API error %d: %s" % (e.code, body[:200]))
        return 0


# ---------------------------------------------------------------------------
# OpenAI TTS via SDK (if installed)
# ---------------------------------------------------------------------------
def generate_clip_sdk(client, text, voice, instruction, model, output_path):
    """Generate a single TTS clip using the openai Python SDK."""
    try:
        response = client.audio.speech.create(
            model=model,
            input=text,
            voice=voice,
            instructions=instruction,
            response_format="wav"
        )
        response.stream_to_file(output_path)
        return os.path.getsize(output_path)
    except Exception as e:
        print("  SDK error: %s" % str(e))
        return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate M.A.S.S. Trap dispatcher audio clips via OpenAI TTS"
    )
    parser.add_argument("--voice", default=DEFAULT_VOICE,
                        help="Voice name (default: %s)" % DEFAULT_VOICE)
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help="TTS model (default: %s)" % DEFAULT_MODEL)
    parser.add_argument("--instruction", default=DEFAULT_INSTRUCTION,
                        help="Voice style instruction")
    parser.add_argument("--only", nargs="*",
                        help="Only generate these clip filenames (e.g. --only armed go finish)")
    parser.add_argument("--category", choices=["firmware", "lab", "extra"],
                        help="Only generate clips in this category")
    parser.add_argument("--overwrite", action="store_true",
                        help="Overwrite existing raw files")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be generated without calling the API")
    parser.add_argument("--list", action="store_true",
                        help="List all clips and exit")
    args = parser.parse_args()

    # Load clip definitions
    with open(CLIPS_FILE, "r") as f:
        data = json.load(f)

    clips = data["clips"]

    if args.list:
        print("\n  M.A.S.S. Trap Audio Clips (%d total)" % len(clips))
        print("  " + "=" * 60)
        for c in clips:
            status = "EXISTS" if os.path.exists(os.path.join(RAW_DIR, c["filename"] + ".wav")) else "MISSING"
            print("  [%s] %-7s  %-20s  %s" % (
                status, c["category"], c["filename"], c["script"][:50]
            ))
        print()
        return

    # Filter clips
    if args.only:
        clips = [c for c in clips if c["filename"] in args.only]
    if args.category:
        clips = [c for c in clips if c["category"] == args.category]

    if not clips:
        print("No clips matched the filter. Use --list to see available clips.")
        return

    # Check API key
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        print("\n  ERROR: OPENAI_API_KEY not set")
        print("  Get a key at https://platform.openai.com/api-keys")
        print("  Then run:  export OPENAI_API_KEY=\"sk-...\"")
        print("  Or test first with:  python3 generate_tts.py --dry-run\n")
        sys.exit(1)

    # Try to use SDK, fall back to raw HTTP
    use_sdk = False
    client = None
    if not args.dry_run:
        try:
            import openai
            client = openai.OpenAI(api_key=api_key)
            use_sdk = True
            print("  Using OpenAI SDK v%s" % openai.__version__)
        except ImportError:
            print("  OpenAI SDK not installed, using raw HTTP (works fine)")

    # Ensure output dir
    os.makedirs(RAW_DIR, exist_ok=True)

    print("\n  M.A.S.S. Trap TTS Generator")
    print("  " + "=" * 40)
    print("  Voice: %s" % args.voice)
    print("  Model: %s" % args.model)
    print("  Clips: %d" % len(clips))
    print("  Output: %s/" % RAW_DIR)
    if args.dry_run:
        print("  Mode: DRY RUN (no API calls)")
    print()

    total_chars = 0
    generated = 0
    skipped = 0
    errors = 0

    for i, clip in enumerate(clips):
        filename = clip["filename"] + ".wav"
        output_path = os.path.join(RAW_DIR, filename)
        script = clip["script"]
        total_chars += len(script)

        # Skip existing files unless --overwrite
        if os.path.exists(output_path) and not args.overwrite:
            print("  [%d/%d] SKIP %s (exists, use --overwrite)" % (i + 1, len(clips), filename))
            skipped += 1
            continue

        print("  [%d/%d] %s" % (i + 1, len(clips), filename))
        print("         \"%s\"" % script)

        if args.dry_run:
            print("         (dry run, skipping API call)")
            continue

        # Generate
        start = time.time()
        if use_sdk:
            size = generate_clip_sdk(client, script, args.voice, args.instruction, args.model, output_path)
        else:
            size = generate_clip_raw_http(api_key, script, args.voice, args.instruction, args.model, output_path)

        elapsed = time.time() - start

        if size > 0:
            print("         OK  %d bytes  %.1fs" % (size, elapsed))
            generated += 1
        else:
            print("         FAILED")
            errors += 1

        # Small delay to be nice to the API
        if i < len(clips) - 1:
            time.sleep(0.3)

    print("\n  " + "-" * 40)
    print("  Generated: %d" % generated)
    print("  Skipped:   %d" % skipped)
    print("  Errors:    %d" % errors)
    print("  Total characters: %d" % total_chars)
    est_cost = total_chars * 15 / 1000000
    print("  Estimated cost: $%.4f" % est_cost)
    print()

    if generated > 0:
        print("  Next step: run ./radio_filter.sh to apply the police radio effect")
        print("  Then run: ./push_audio.sh to upload WAVs to your ESP32 devices")
        print()


if __name__ == "__main__":
    main()
