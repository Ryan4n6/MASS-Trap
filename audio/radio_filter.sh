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
echo ""

PROCESSED=0
ERRORS=0

for filepath in "${FILES[@]}"; do
    filename="$(basename "$filepath")"
    name="${filename%.wav}"

    echo "  Processing: $name"

    # Build the filter chain
    if [ "$ADD_STATIC" = true ]; then
        # Radio filter WITH subtle static crackle
        # The anoisesrc generates pink noise mixed at very low volume
        FILTER_COMPLEX=(
            -f lavfi -i "anoisesrc=d=30:c=pink:a=0.008"
            -filter_complex
            "[0:a][1:a]amix=inputs=2:duration=first:weights=1 0.03,highpass=f=300,lowpass=f=3000,acompressor=threshold=0.05:ratio=8:attack=5:release=50:makeup=5,volume=1.3"
        )
    else
        # Radio filter WITHOUT static (cleaner sound)
        FILTER_COMPLEX=(
            -af
            "highpass=f=300,lowpass=f=3000,acompressor=threshold=0.05:ratio=8:attack=5:release=50:makeup=5,volume=1.3"
        )
    fi

    # Step 1: Full-quality radio-filtered version (archive)
    "$FFMPEG" -y -i "$filepath" \
        "${FILTER_COMPLEX[@]}" \
        -acodec pcm_s16le -ac 1 -ar 16000 \
        "$RADIO_DIR/$filename" \
        -loglevel error 2>&1

    if [ $? -ne 0 ]; then
        echo "    FAILED (radio filter)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Step 2: ESP32 format (8-bit unsigned PCM, 16kHz mono)
    "$FFMPEG" -y -i "$RADIO_DIR/$filename" \
        -acodec pcm_u8 -ac 1 -ar 16000 \
        "$ESP32_DIR/$filename" \
        -loglevel error 2>&1

    if [ $? -ne 0 ]; then
        echo "    FAILED (ESP32 convert)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Step 3: Copy to data/ for PlatformIO uploadfs
    cp "$ESP32_DIR/$filename" "$DATA_DIR/$filename" 2>/dev/null

    # Step 4: Optional MP3 preview
    if [ "$MAKE_PREVIEW" = true ]; then
        "$FFMPEG" -y -i "$RADIO_DIR/$filename" \
            -codec:a libmp3lame -b:a 128k \
            "$RADIO_DIR/${name}.mp3" \
            -loglevel error 2>&1
    fi

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
