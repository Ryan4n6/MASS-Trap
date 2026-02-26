#!/usr/bin/env python3
"""
M.A.S.S. Trap — TTS Audio Generator
====================================
Generates AI companion voice clips using OpenAI or ElevenLabs TTS APIs.
Voice style: calm, warm, composed — like Karen from Spider-Man: Homecoming.

Providers (pass --provider NAME):

  elevenlabs  — Highest quality, most natural-sounding output (default)
                Setup: export ELEVENLABS_API_KEY="your-key"
                       (or store in macOS Keychain as ELEVENLABS_API_KEY)
                Voices: rachel (default), matilda, emily, alice, sarah,
                        dorothy, charlotte, nicole, lily, serena
                        Or pass any voice_id from the Voice Library.

  openai      — gpt-4o-mini-tts with natural language style steering
                Setup: export OPENAI_API_KEY="sk-..."
                Voices: nova (default), shimmer, alloy, echo, onyx, ash

Usage:
  python3 generate_tts.py --provider elevenlabs              # Best quality
  python3 generate_tts.py --provider elevenlabs --voice matilda
  python3 generate_tts.py --provider elevenlabs --voice "raw-voice-id"
  python3 generate_tts.py --provider openai                   # OpenAI fallback
  python3 generate_tts.py --list                              # Show all clips
  python3 generate_tts.py --dry-run                           # Preview only
  python3 generate_tts.py --voices                            # List voice presets

The script reads clips.json, generates raw WAV files into raw/, then you
run radio_filter.sh to apply the police radio effect and convert to ESP32 format.
"""

import json
import os
import sys
import time
import subprocess
import urllib.request
import urllib.error

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLIPS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "clips.json")
RAW_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")

# OpenAI defaults (nova is warm/friendly female — best for AI companion)
OPENAI_DEFAULT_VOICE = "nova"
OPENAI_DEFAULT_MODEL = "gpt-4o-mini-tts"
OPENAI_DEFAULT_INSTRUCTION = (
    "Speak as a calm, warm AI companion with composed delivery and clear "
    "enunciation, like an intelligent suit AI giving tactical updates, "
    "friendly but professional, slight warmth in tone, no filler words"
)

# ElevenLabs defaults
ELEVENLABS_DEFAULT_MODEL = "eleven_multilingual_v2"
ELEVENLABS_DEFAULT_VOICE = "bella"

# ElevenLabs pre-made voice name -> ID shortcuts (female, AI companion style)
ELEVENLABS_VOICES = {
    "bella":     "hpp4J3VqNfWAUOO0d1Us",  # Default ElevenLabs female — warm, natural
    "rachel":    "21m00Tcm4TlvDq8ikWAM",  # Calm — composed presence
    "matilda":   "XrExE9yKIg1WjnnlVkGX",  # Warm — friendly AI companion
    "emily":     "LcfcDJNUP1GQjkzn1xUU",  # Calm — composed presence
    "alice":     "Xb7hH8MSUJpSbSDYk0k2",  # Confident — more assertive
    "sarah":     "EXAVITQu4vr4xnSDxMaL",  # Soft — gentle delivery
    "dorothy":   "ThT5KcBeYPX3keUQqHPh",  # Pleasant — warm and clear
    "charlotte": "XB0fDUnXU5powFXDhCwa",  # Seductive — smooth, lower register
    "nicole":    "piTKgcLEGmPE4e6mEKli",  # Whisper — intimate, quiet
    "lily":      "pFZP5JQG7iQjIQuC4Bku",  # Raspy — textured
    "serena":    "pMsXgVXv3BLzUgSXRplE",  # Pleasant — balanced
}

# Voice settings tuned for calm, composed AI companion delivery
ELEVENLABS_VOICE_SETTINGS = {
    "stability": 0.75,          # Steady and consistent
    "similarity_boost": 0.80,   # Faithful to voice character
    "style": 0.0,
    "use_speaker_boost": True,
    "speed": 1.0,
}


# ---------------------------------------------------------------------------
# macOS Keychain helper
# ---------------------------------------------------------------------------
def get_keychain_key(service_name):
    """Try to retrieve an API key from macOS Keychain. Returns empty string on failure."""
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", service_name, "-w"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return ""


def get_api_key(env_var, service_name, provider_name):
    """Get API key from environment variable, falling back to macOS Keychain."""
    key = os.environ.get(env_var, "")
    if key:
        return key
    key = get_keychain_key(service_name)
    if key:
        print("  Using %s key from macOS Keychain" % provider_name)
        return key
    return ""


# ---------------------------------------------------------------------------
# OpenAI TTS via raw HTTP (no SDK dependency)
# ---------------------------------------------------------------------------
def generate_openai_http(api_key, text, voice, instruction, model, output_path):
    """Generate a single TTS clip using OpenAI via urllib."""
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
def generate_openai_sdk(client, text, voice, instruction, model, output_path):
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
# ElevenLabs TTS via raw HTTP
# ---------------------------------------------------------------------------
def generate_elevenlabs(api_key, text, voice_id, model, voice_settings, output_path):
    """Generate a single TTS clip using ElevenLabs API via urllib."""
    url = "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=pcm_24000" % voice_id

    payload = json.dumps({
        "text": text,
        "model_id": model,
        "voice_settings": voice_settings,
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("xi-api-key", api_key)
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            pcm_data = resp.read()

            # ElevenLabs pcm_24000 returns raw signed 16-bit LE mono at 24kHz
            # Wrap in a WAV header so radio_filter.sh can process it
            sample_rate = 24000
            num_channels = 1
            bits_per_sample = 16
            byte_rate = sample_rate * num_channels * bits_per_sample // 8
            block_align = num_channels * bits_per_sample // 8
            data_size = len(pcm_data)

            import struct
            with open(output_path, "wb") as f:
                # RIFF header
                f.write(b"RIFF")
                f.write(struct.pack("<I", 36 + data_size))
                f.write(b"WAVE")
                # fmt chunk
                f.write(b"fmt ")
                f.write(struct.pack("<I", 16))
                f.write(struct.pack("<H", 1))           # PCM format
                f.write(struct.pack("<H", num_channels))
                f.write(struct.pack("<I", sample_rate))
                f.write(struct.pack("<I", byte_rate))
                f.write(struct.pack("<H", block_align))
                f.write(struct.pack("<H", bits_per_sample))
                # data chunk
                f.write(b"data")
                f.write(struct.pack("<I", data_size))
                f.write(pcm_data)

            return 44 + data_size
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("  API error %d: %s" % (e.code, body[:200]))
        return 0
    except Exception as e:
        print("  Error: %s" % str(e))
        return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate M.A.S.S. Trap AI companion audio clips via TTS API"
    )
    parser.add_argument("--provider", choices=["openai", "elevenlabs"],
                        default="elevenlabs",
                        help="TTS provider (default: elevenlabs)")
    parser.add_argument("--voice", default=None,
                        help="Voice name or raw voice_id (default: rachel for elevenlabs, nova for openai)")
    parser.add_argument("--model", default=None,
                        help="TTS model (provider-specific)")
    parser.add_argument("--instruction", default=OPENAI_DEFAULT_INSTRUCTION,
                        help="Voice style instruction (OpenAI only)")
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
    parser.add_argument("--voices", action="store_true",
                        help="List built-in voice presets and exit")
    args = parser.parse_args()

    # List voices
    if args.voices:
        print("\n  ElevenLabs Voice Presets (female, AI companion style)")
        print("  " + "=" * 55)
        for name, vid in sorted(ELEVENLABS_VOICES.items()):
            marker = " <-- default" if name == ELEVENLABS_DEFAULT_VOICE else ""
            print("  %-12s  %s%s" % (name, vid, marker))
        print()
        print("  You can also pass any voice_id from the Voice Library:")
        print("    --voice \"paste-voice-id-here\"")
        print()
        print("  OpenAI voices: nova (default), shimmer, alloy, echo, onyx, ash")
        print()
        return

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

    # Resolve provider-specific defaults
    provider = args.provider

    if provider == "elevenlabs":
        voice = args.voice or ELEVENLABS_DEFAULT_VOICE
        model = args.model or ELEVENLABS_DEFAULT_MODEL

        # Resolve voice name to ID, or treat as raw voice_id
        if voice.lower() in ELEVENLABS_VOICES:
            voice_id = ELEVENLABS_VOICES[voice.lower()]
            voice_display = "%s (%s)" % (voice.lower(), voice_id[:8] + "...")
        else:
            voice_id = voice
            voice_display = "custom (%s)" % (voice[:16] + "..." if len(voice) > 16 else voice)

        # Get API key
        api_key = get_api_key("ELEVENLABS_API_KEY", "ELEVENLABS_API_KEY", "ElevenLabs")
        if not api_key and not args.dry_run:
            print("\n  ERROR: ELEVENLABS_API_KEY not set")
            print("  Get a key at https://elevenlabs.io/app/settings/api-keys")
            print("  Then either:")
            print("    export ELEVENLABS_API_KEY=\"your-key\"")
            print("  Or store in macOS Keychain:")
            print("    security add-generic-password -a \"$USER\" -s ELEVENLABS_API_KEY -T \"\" -w \"your-key\"")
            print("  Or test first with:  python3 generate_tts.py --dry-run\n")
            sys.exit(1)
    else:
        voice = args.voice or OPENAI_DEFAULT_VOICE
        model = args.model or OPENAI_DEFAULT_MODEL
        voice_display = voice

        # Get API key
        api_key = get_api_key("OPENAI_API_KEY", "OPENAI_API_KEY", "OpenAI")
        if not api_key and not args.dry_run:
            print("\n  ERROR: OPENAI_API_KEY not set")
            print("  Get a key at https://platform.openai.com/api-keys")
            print("  Then either:")
            print("    export OPENAI_API_KEY=\"sk-...\"")
            print("  Or store in macOS Keychain:")
            print("    security add-generic-password -a \"$USER\" -s OPENAI_API_KEY -T \"\" -w \"sk-...\"")
            print("  Or test first with:  python3 generate_tts.py --dry-run\n")
            sys.exit(1)

    # OpenAI SDK check
    use_sdk = False
    client = None
    if provider == "openai" and not args.dry_run:
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
    print("  Provider: %s" % provider)
    print("  Voice: %s" % voice_display)
    print("  Model: %s" % model)
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

        # Generate via selected provider
        start_time = time.time()

        if provider == "elevenlabs":
            size = generate_elevenlabs(
                api_key, script, voice_id, model,
                ELEVENLABS_VOICE_SETTINGS, output_path
            )
        elif use_sdk:
            size = generate_openai_sdk(
                client, script, voice, args.instruction, model, output_path
            )
        else:
            size = generate_openai_http(
                api_key, script, voice, args.instruction, model, output_path
            )

        elapsed = time.time() - start_time

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

    # Cost estimate
    if provider == "elevenlabs":
        # ElevenLabs eleven_multilingual_v2: 1 credit per character
        # Starter plan: 30,000 credits/mo ($5/mo)
        # Full 20-clip batch = ~925 credits (~$0.15)
        # As of 2026-02-17: balance 8,605 credits after 2 batches
        print("  Credits used: ~%d" % total_chars)
        print("  Cost per clip (avg): ~%d credits" % (total_chars // max(len(clips), 1)))
        print("  Starter plan: 30,000 credits/mo ($5/mo), ~$0.17 per 1000 chars")
    else:
        est_cost = total_chars * 15 / 1000000
        print("  Estimated cost: $%.4f" % est_cost)
    print()

    if generated > 0:
        print("  Next step: run ./radio_filter.sh to apply the police radio effect")
        print("  Then run: ./push_audio.sh to upload WAVs to your ESP32 devices")
        print()


if __name__ == "__main__":
    main()
