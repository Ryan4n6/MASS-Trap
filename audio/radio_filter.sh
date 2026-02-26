#!/bin/bash
# ============================================================================
# M.A.S.S. Trap — Police Radio Filter + ESP32 Format Converter
# ============================================================================
# Takes raw TTS WAV files from raw/ and applies:
#   1. Band-pass filter (300Hz-3000Hz) — simulates radio bandwidth
#   2. Heavy compression — squashes dynamic range like a radio transmitter
#   3. Optional pink noise — subtle static crackle for realism
#   4. Converts to 8-bit 16kHz mono PCM — what the ESP32 I2S driver expects
#
# Output goes to esp32/ (ready to push to devices via LittleFS)
# A second copy in radio/ keeps the full-quality filtered version
#
# Usage:
#   ./radio_filter.sh              # Process all raw clips
#   ./radio_filter.sh armed go     # Process only these clips
#   ./radio_filter.sh --no-static  # Skip the static/crackle layer
#   ./radio_filter.sh --preview    # Also generate MP3 previews for listening
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RAW_DIR="$SCRIPT_DIR/raw"
RADIO_DIR="$SCRIPT_DIR/radio"
ESP32_DIR="$SCRIPT_DIR/esp32"
DATA_DIR="$SCRIPT_DIR/../data"

# Find ffmpeg
FFMPEG="/usr/local/Cellar/ffmpeg/8.0.1_1/bin/ffmpeg"
if [ ! -x "$FFMPEG" ]; then
    FFMPEG="$(which ffmpeg 2>/dev/null)"
fi
if [ ! -x "$FFMPEG" ]; then
    echo "ERROR: ffmpeg not found"
    echo "Install via: brew install ffmpeg"
    exit 1
fi

# Parse flags
ADD_STATIC=true
MAKE_PREVIEW=false
SPECIFIC_CLIPS=()

for arg in "$@"; do
    case "$arg" in
        --no-static)  ADD_STATIC=false ;;
        --preview)    MAKE_PREVIEW=true ;;
        --help|-h)
            echo "Usage: $0 [--no-static] [--preview] [clip1 clip2 ...]"
            echo ""
            echo "Options:"
            echo "  --no-static   Skip the subtle static/crackle layer"
            echo "  --preview     Also generate MP3 preview files"
            echo "  clip1 clip2   Only process these clips (without .wav extension)"
            echo ""
            echo "Output:"
            echo "  esp32/    — 8-bit 16kHz mono WAV (push to ESP32 LittleFS)"
            echo "  radio/    — Full-quality filtered WAV (archive)"
            echo "  ../data/  — Copies ESP32 files for PlatformIO uploadfs"
            exit 0
            ;;
        *)  SPECIFIC_CLIPS+=("$arg") ;;
    esac
done

mkdir -p "$RADIO_DIR" "$ESP32_DIR"

# Count raw files
if [ ${#SPECIFIC_CLIPS[@]} -gt 0 ]; then
    FILES=()
    for name in "${SPECIFIC_CLIPS[@]}"; do
        f="$RAW_DIR/${name}.wav"
        if [ -f "$f" ]; then
            FILES+=("$f")
        else
            echo "WARNING: $f not found, skipping"
        fi
    done
else
    FILES=("$RAW_DIR"/*.wav)
fi

if [ ${#FILES[@]} -eq 0 ] || [ ! -f "${FILES[0]}" ]; then
    echo "No WAV files found in $RAW_DIR/"
    echo "Run generate_tts.py first to create raw clips"
    exit 1
fi

echo ""
echo "  M.A.S.S. Trap — Police Radio Filter"
echo "  ========================================"
echo "  Input:    $RAW_DIR/"
echo "  Output:   $ESP32_DIR/ (8-bit 16kHz mono)"
echo "  Archive:  $RADIO_DIR/ (full quality)"
echo "  Static:   $ADD_STATIC"
echo "  Files:    ${#FILES[@]}"

# --- Pre-convert chatter ambience to 16kHz mono with radio EQ (one-time) ---
CHATTER_SRC="$SCRIPT_DIR/chatter.m4a"
CHATTER_WAV="$RADIO_DIR/_chatter_prepared.wav"
CHATTER_DURATION=0
if [ -f "$CHATTER_SRC" ]; then
    echo "  Chatter: $CHATTER_SRC (preparing...)"
    RADIO_EQ_PREP="highpass=f=300,lowpass=f=3200,equalizer=f=1000:width_type=o:width=1.5:g=6,acompressor=threshold=0.15:ratio=10:attack=5:release=50:makeup=2,asoftclip=type=atan:param=1.0"
    "$FFMPEG" -y -i "$CHATTER_SRC" \
        -af "aresample=16000,$RADIO_EQ_PREP" \
        -acodec pcm_s16le -ac 1 -ar 16000 \
        "$CHATTER_WAV" \
        -loglevel error 2>&1
    # Get duration in seconds (integer)
    CHATTER_DURATION=$("$FFMPEG" -i "$CHATTER_WAV" 2>&1 | grep Duration | sed 's/.*Duration: \([0-9]*\):\([0-9]*\):\([0-9]*\).*/\1*3600+\2*60+\3/' | bc)
    echo "  Chatter: ready (${CHATTER_DURATION}s prepared)"
else
    echo "  Chatter: not found (skipping ambience layer)"
fi
echo ""

PROCESSED=0
ERRORS=0

for filepath in "${FILES[@]}"; do
    filename="$(basename "$filepath")"
    name="${filename%.wav}"

    echo "  Processing: $name"

    # AUTHENTIC POLICE DISPATCHER FILTER
    # 1. Downsample: 24kHz → 8kHz → 16kHz. Destroys everything above 4kHz.
    # 2. Bandpass: 300Hz-3200Hz (Strict radio frequency standard)
    # 3. Equalizer: +12dB boost at 1000Hz. Creates that "nasal/boxy" radio sound.
    # 4. Crusher: Reduces audio resolution to simulate digital radio (P25/Tetra) artifacting.
    # 5. Overdrive: Hard clipping to simulate a dispatcher speaking too close to the mic.
    # 6. Squelch burst at start + roger beep at end — the iconic radio bookends.

    # --- Step 1: Generate clean elements (no radio filter yet) ---

    # Squelch burst (short static pop, ~150ms)
    "$FFMPEG" -y \
        -f lavfi -i "anoisesrc=d=0.15:c=white:r=24000:a=0.6" \
        -af "afade=t=in:d=0.02,afade=t=out:st=0.10:d=0.05" \
        -acodec pcm_s16le -ac 1 -ar 24000 \
        "$RADIO_DIR/_squelch.wav" \
        -loglevel error 2>&1

    # Roger beep (warm buzz chirp)
    "$FFMPEG" -y \
        -f lavfi -i "sine=frequency=1000:duration=0.08:sample_rate=24000" \
        -f lavfi -i "sine=frequency=700:duration=0.08:sample_rate=24000" \
        -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1,volume=2.0,asoftclip=type=atan:param=2.0,volume=0.4,afade=t=out:st=0.10:d=0.06" \
        -acodec pcm_s16le -ac 1 -ar 24000 \
        "$RADIO_DIR/_roger.wav" \
        -loglevel error 2>&1

    # Silence gap (250ms)
    "$FFMPEG" -y \
        -f lavfi -i "anullsrc=r=24000:cl=mono" \
        -t 0.25 -acodec pcm_s16le \
        "$RADIO_DIR/_gap.wav" \
        -loglevel error 2>&1

    # --- Step 2: Concatenate clean: squelch + gap + voice + roger ---
    "$FFMPEG" -y \
        -i "$RADIO_DIR/_squelch.wav" \
        -i "$RADIO_DIR/_gap.wav" \
        -i "$filepath" \
        -i "$RADIO_DIR/_roger.wav" \
        -filter_complex "[0:a][1:a][2:a][3:a]concat=n=4:v=0:a=1" \
        -acodec pcm_s16le -ac 1 -ar 24000 \
        "$RADIO_DIR/_assembled.wav" \
        -loglevel error 2>&1

    if [ $? -ne 0 ]; then
        echo "    FAILED (concatenation)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # --- Step 3: Apply radio filter to the whole assembled clip at once ---
    RADIO_EQ="aresample=12000,aresample=16000,highpass=f=300,lowpass=f=3200,equalizer=f=1000:width_type=o:width=1.5:g=6,acompressor=threshold=0.15:ratio=10:attack=5:release=50:makeup=2,asoftclip=type=atan:param=1.0"

    if [ "$ADD_STATIC" = true ]; then
        "$FFMPEG" -y \
            -i "$RADIO_DIR/_assembled.wav" \
            -f lavfi -i "anoisesrc=d=30:c=pink:r=16000:a=0.05" \
            -filter_complex \
            "[0:a]${RADIO_EQ}[voice];[1:a]highpass=f=300,lowpass=f=3200,volume=0.15[static];[voice][static]amix=inputs=2:duration=first:weights=10 1" \
            -acodec pcm_s16le -ac 1 -ar 16000 \
            "$RADIO_DIR/_filtered.wav" \
            -loglevel error 2>&1
    else
        "$FFMPEG" -y \
            -i "$RADIO_DIR/_assembled.wav" \
            -af "${RADIO_EQ}" \
            -acodec pcm_s16le -ac 1 -ar 16000 \
            "$RADIO_DIR/_filtered.wav" \
            -loglevel error 2>&1
    fi

    if [ $? -ne 0 ]; then
        echo "    FAILED (radio filter)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # --- Step 4: Mix chatter ambience underneath at 50% (if available) ---
    if [ -f "$CHATTER_WAV" ] && [ "$CHATTER_DURATION" -gt 0 ]; then
        MAX_OFFSET=$((CHATTER_DURATION - 10))
        if [ "$MAX_OFFSET" -lt 1 ]; then MAX_OFFSET=1; fi
        RAND_OFFSET=$(( RANDOM % MAX_OFFSET ))
        "$FFMPEG" -y \
            -i "$RADIO_DIR/_filtered.wav" \
            -ss "$RAND_OFFSET" -i "$CHATTER_WAV" \
            -filter_complex "[1:a]volume=0.30[bg];[0:a][bg]amix=inputs=2:duration=first:weights=1 1" \
            -acodec pcm_s16le -ac 1 -ar 16000 \
            "$RADIO_DIR/$filename" \
            -loglevel error 2>&1
        if [ $? -ne 0 ]; then
            echo "    WARNING: chatter mix failed, using filtered without ambience"
            mv "$RADIO_DIR/_filtered.wav" "$RADIO_DIR/$filename"
        fi
    else
        mv "$RADIO_DIR/_filtered.wav" "$RADIO_DIR/$filename"
    fi

    # --- Step 3: ESP32 format (8-bit unsigned PCM, 16kHz mono) ---
    "$FFMPEG" -y -i "$RADIO_DIR/$filename" \
        -acodec pcm_u8 -ac 1 -ar 16000 \
        "$ESP32_DIR/$filename" \
        -loglevel error 2>&1

    if [ $? -ne 0 ]; then
        echo "    FAILED (ESP32 convert)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # --- Step 4: Copy to data/ for PlatformIO uploadfs ---
    cp "$ESP32_DIR/$filename" "$DATA_DIR/$filename" 2>/dev/null

    # --- Step 5: Optional MP3 preview ---
    if [ "$MAKE_PREVIEW" = true ]; then
        "$FFMPEG" -y -i "$RADIO_DIR/$filename" \
            -codec:a libmp3lame -b:a 128k \
            "$RADIO_DIR/${name}.mp3" \
            -loglevel error 2>&1
    fi

    # Clean up temp files
    rm -f "$RADIO_DIR/_squelch.wav" "$RADIO_DIR/_gap.wav" "$RADIO_DIR/_assembled.wav" "$RADIO_DIR/_filtered.wav" "$RADIO_DIR/_roger.wav"

    # Report sizes
    RAW_SIZE=$(wc -c < "$filepath" | tr -d ' ')
    ESP_SIZE=$(wc -c < "$ESP32_DIR/$filename" | tr -d ' ')
    echo "    OK  raw: ${RAW_SIZE}B  esp32: ${ESP_SIZE}B"

    PROCESSED=$((PROCESSED + 1))
done

echo ""
echo "  ----------------------------------------"
echo "  Processed: $PROCESSED"
echo "  Errors:    $ERRORS"
echo ""

if [ $PROCESSED -gt 0 ]; then
    # Show total size of ESP32 files
    TOTAL=$(du -sh "$ESP32_DIR" 2>/dev/null | cut -f1)
    echo "  ESP32 files total: $TOTAL"
    echo "  Files copied to: $DATA_DIR/"
    echo ""
    echo "  Next step: ./push_audio.sh to upload to your ESP32 devices"
    echo "  Or: cd .. && pio run -t uploadfs  (uploads all LittleFS data)"
    echo ""
fi
