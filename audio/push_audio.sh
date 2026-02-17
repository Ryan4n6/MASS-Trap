#!/bin/bash
# ============================================================================
# M.A.S.S. Trap — Push Audio Files to ESP32 Devices
# ============================================================================
# Hot-pushes WAV files from esp32/ to device LittleFS via the file API.
# No recompile needed — files are immediately available for playback.
#
# Usage:
#   ./push_audio.sh                    # Push to all online devices
#   ./push_audio.sh finish             # Push to finish gate only
#   ./push_audio.sh start speedtrap    # Push to specific devices
#   ./push_audio.sh --only armed go    # Only push these clip files
#   ./push_audio.sh --verify           # Just check what's on each device
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ESP32_DIR="$SCRIPT_DIR/esp32"
API_KEY="admin"

# Device fleet — role:ip pairs
declare -A DEVICES
DEVICES[finish]="192.168.1.83"
DEVICES[start]="192.168.1.244"
DEVICES[speedtrap]="192.168.1.55"

# Which clips go to which devices
# Firmware clips: armed/go play on start gate, finish/record on finish gate, speed_trap on speedtrap
# Lab/extra clips: all go to finish gate (dashboard host)
declare -A CLIP_TARGETS
CLIP_TARGETS[armed]="start"
CLIP_TARGETS[go]="start"
CLIP_TARGETS[finish]="finish"
CLIP_TARGETS[record]="finish"
CLIP_TARGETS[reset]="finish"
CLIP_TARGETS[sync]="finish"
CLIP_TARGETS[error]="finish start speedtrap"
CLIP_TARGETS[speed_trap]="speedtrap"
CLIP_TARGETS[attention]="finish"
CLIP_TARGETS[next_car]="finish"
CLIP_TARGETS[condition_change]="finish"
CLIP_TARGETS[trial_complete]="finish"
CLIP_TARGETS[experiment_done]="finish"
CLIP_TARGETS[sanity_alert]="finish"
CLIP_TARGETS[case_assigned]="finish"
CLIP_TARGETS[leaderboard]="finish"
CLIP_TARGETS[startup]="finish start speedtrap"
CLIP_TARGETS[peer_found]="finish start speedtrap"
CLIP_TARGETS[calibration]="finish"
CLIP_TARGETS[photo_prompt]="finish"

# Parse args
ONLY_DEVICES=()
ONLY_CLIPS=()
VERIFY_ONLY=false
PARSING_CLIPS=false

for arg in "$@"; do
    case "$arg" in
        --only)     PARSING_CLIPS=true ;;
        --verify)   VERIFY_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [--verify] [--only clip1 clip2] [device1 device2]"
            echo ""
            echo "Devices: finish, start, speedtrap"
            echo "Clips:   armed, go, finish, record, etc (without .wav)"
            echo ""
            echo "Options:"
            echo "  --verify     Just check what audio files are on each device"
            echo "  --only       Only push these specific clips"
            echo ""
            echo "Examples:"
            echo "  $0                           Push all clips to all devices"
            echo "  $0 finish                    Push only to finish gate"
            echo "  $0 --only armed go finish    Push only these 3 clips"
            echo "  $0 --verify                  Check device audio inventory"
            exit 0
            ;;
        *)
            if [ "$PARSING_CLIPS" = true ]; then
                ONLY_CLIPS+=("$arg")
            else
                ONLY_DEVICES+=("$arg")
            fi
            ;;
    esac
done

echo ""
echo "  M.A.S.S. Trap — Audio Push"
echo "  ==============================="

# Verify mode: just check what's on each device
if [ "$VERIFY_ONLY" = true ]; then
    echo "  Mode: Verify (checking device audio inventory)"
    echo ""
    for role in finish start speedtrap; do
        ip="${DEVICES[$role]}"
        echo "  $role ($ip):"
        # Ping check
        if ! ping -c 1 -W 1 "$ip" > /dev/null 2>&1; then
            echo "    OFFLINE"
            echo ""
            continue
        fi
        # Get file list and filter for .wav
        FILES=$(curl -s -H "X-API-Key: $API_KEY" "http://$ip/api/files" 2>/dev/null)
        if [ -z "$FILES" ]; then
            echo "    No response from API"
        else
            WAV_COUNT=$(echo "$FILES" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    wavs = [f for f in data.get('files', []) if f.get('name', '').endswith('.wav')]
    if not wavs:
        print('    No WAV files found')
    else:
        total = 0
        for f in sorted(wavs, key=lambda x: x.get('name', '')):
            size = f.get('size', 0)
            total += size
            print('    %-25s %6d bytes' % (f['name'], size))
        print('    --- %d files, %d bytes total ---' % (len(wavs), total))
except:
    print('    Error parsing API response')
" 2>/dev/null)
            echo "$WAV_COUNT"
        fi
        echo ""
    done
    exit 0
fi

# Push mode
PUSHED=0
FAILED=0
SKIPPED=0

for role in finish start speedtrap; do
    ip="${DEVICES[$role]}"

    # Filter by device if specified
    if [ ${#ONLY_DEVICES[@]} -gt 0 ]; then
        MATCH=false
        for d in "${ONLY_DEVICES[@]}"; do
            if [ "$d" = "$role" ]; then MATCH=true; fi
        done
        if [ "$MATCH" = false ]; then continue; fi
    fi

    # Ping check
    echo ""
    echo "  $role ($ip):"
    if ! ping -c 1 -W 1 "$ip" > /dev/null 2>&1; then
        echo "    OFFLINE — skipping"
        continue
    fi

    # Push each clip that targets this device
    for wav_file in "$ESP32_DIR"/*.wav; do
        [ -f "$wav_file" ] || continue

        filename="$(basename "$wav_file")"
        clipname="${filename%.wav}"

        # Filter by clip name if --only specified
        if [ ${#ONLY_CLIPS[@]} -gt 0 ]; then
            MATCH=false
            for c in "${ONLY_CLIPS[@]}"; do
                if [ "$c" = "$clipname" ]; then MATCH=true; fi
            done
            if [ "$MATCH" = false ]; then continue; fi
        fi

        # Check if this clip targets this device
        TARGETS="${CLIP_TARGETS[$clipname]}"
        if [ -z "$TARGETS" ]; then
            # Unknown clip — default to finish gate
            TARGETS="finish"
        fi

        SHOULD_PUSH=false
        for t in $TARGETS; do
            if [ "$t" = "$role" ]; then SHOULD_PUSH=true; fi
        done

        if [ "$SHOULD_PUSH" = false ]; then continue; fi

        # Push the file
        LOCAL_SIZE=$(wc -c < "$wav_file" | tr -d ' ')
        printf "    %-22s (%5d bytes) ... " "$filename" "$LOCAL_SIZE"

        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "http://$ip/api/files?path=/$filename" \
            -H "X-API-Key: $API_KEY" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "@$wav_file" \
            --connect-timeout 5 \
            --max-time 15 2>/dev/null)

        if [ "$HTTP_CODE" = "200" ]; then
            # Verify file size on device
            REMOTE_SIZE=$(curl -s -H "X-API-Key: $API_KEY" "http://$ip/api/files" 2>/dev/null | \
                python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for f in data.get('files', []):
        if f.get('name') == '/$filename':
            print(f.get('size', 0))
            break
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)

            if [ "$REMOTE_SIZE" = "0" ] || [ -z "$REMOTE_SIZE" ]; then
                echo "PUSHED but verify failed (may need re-push)"
                FAILED=$((FAILED + 1))
            elif [ "$REMOTE_SIZE" = "$LOCAL_SIZE" ]; then
                echo "OK"
                PUSHED=$((PUSHED + 1))
            else
                echo "SIZE MISMATCH (local=$LOCAL_SIZE remote=$REMOTE_SIZE)"
                FAILED=$((FAILED + 1))
            fi
        else
            echo "FAILED (HTTP $HTTP_CODE)"
            FAILED=$((FAILED + 1))
        fi
    done
done

echo ""
echo "  ----------------------------------------"
echo "  Pushed:   $PUSHED"
echo "  Failed:   $FAILED"
echo ""

if [ $PUSHED -gt 0 ]; then
    echo "  Audio files are live on devices"
    echo "  Test via: curl -X POST http://192.168.1.83/api/audio/test -H 'X-API-Key: admin' -H 'Content-Type: application/json' -d '{\"file\":\"finish.wav\"}'"
    echo ""
fi
