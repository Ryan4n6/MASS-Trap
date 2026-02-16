#!/bin/bash
# ============================================================================
# generate_stats.sh — M.A.S.S. Trap Baseball Card Generator
#
# Regenerates docs/stats.json from live git data + hardcoded project constants.
# Run after any significant commit, release, or fleet change.
#
# Usage:  ./generate_stats.sh           (regenerate stats.json)
#         ./generate_stats.sh --dry-run  (print to stdout, don't write)
#
# This script exists because Agent K keeps getting neuralized and needs
# a single source of truth that survives context compression events.
# If it wasn't documented, it didn't happen.
# ============================================================================

set -e
cd "$(dirname "$0")"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ---- Git stats (computed live) ----
TOTAL_COMMITS=$(git rev-list --count HEAD)
TOTAL_FILES=$(git ls-files | wc -l | tr -d ' ')
TOTAL_LINES=$(git ls-files | grep -v '.pio' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
LATEST_HASH=$(git log -1 --format='%h')
LATEST_DATE=$(git log -1 --format='%ci' | cut -d' ' -f1)
FIRST_DATE=$(git log --reverse --format='%ci' | head -1 | cut -d' ' -f1)
INSERTIONS=$(git log --shortstat --format="" | grep -oE '[0-9]+ insertion' | awk '{s+=$1}END{print s+0}')
DELETIONS=$(git log --shortstat --format="" | grep -oE '[0-9]+ deletion' | awk '{s+=$1}END{print s+0}')
CONTRIBUTORS=$(git shortlog -sn --all | wc -l | tr -d ' ')
ACTIVE_DAYS=$(git log --format='%ad' --date=short | sort -u | wc -l | tr -d ' ')
LATE_NIGHT=$(git log --format='%ai' | awk '{split($2,t,":");h=int(t[1]);if(h>=22||h<6)c++}END{print c+0}')
TAGS=$(git tag | wc -l | tr -d ' ')

# Streak: consecutive days from today going back
STREAK=0
CHECK_DATE=$(date +%Y-%m-%d)
while git log --format='%ad' --date=short | sort -u | grep -q "^${CHECK_DATE}$" 2>/dev/null; do
  STREAK=$((STREAK + 1))
  CHECK_DATE=$(date -v-${STREAK}d +%Y-%m-%d 2>/dev/null || date -d "${STREAK} days ago" +%Y-%m-%d 2>/dev/null || break)
done

# ---- Code breakdown ----
CPP_LINES=$(cat *.cpp *.h *.ino 2>/dev/null | wc -l | tr -d ' ')
HTML_LINES=$(cat data/*.html docs/*.html 2>/dev/null | wc -l | tr -d ' ')
JS_LINES=$(cat data/*.js 2>/dev/null | wc -l | tr -d ' ')
CSS_LINES=$(cat data/*.css 2>/dev/null | wc -l | tr -d ' ')
CPP_FUNCS=$(grep -cE '^[A-Za-z].*\(' *.cpp 2>/dev/null | awk -F: '{s+=$2}END{print s+0}')
JS_FUNCS=$(grep -c 'function ' data/*.html docs/*.html data/*.js 2>/dev/null | awk -F: '{s+=$2}END{print s+0}')
API_ROUTES=$(grep -c 'server\.on' web_server.cpp 2>/dev/null || echo 0)
DASH_BYTES=$(stat -f%z data/dashboard.html 2>/dev/null || stat --printf="%s" data/dashboard.html 2>/dev/null || echo 0)
DASH_KB=$(python3 -c "print(round(${DASH_BYTES}/1024, 1))")
FEATURES_DONE=$(grep -c '"done"' data/about.html 2>/dev/null || echo 0)
FEATURES_WIP=$(grep -c '"wip"' data/about.html 2>/dev/null || echo 0)
DOC_PAGES=$(ls docs/*.html 2>/dev/null | wc -l | tr -d ' ')
ESP_PAGES=$(echo 5)

# ---- Binary (may not exist if not recently compiled) ----
BIN_PATH=".pio/build/mass-trap/firmware.bin"
if [[ -f "$BIN_PATH" ]]; then
  BIN_BYTES=$(stat -f%z "$BIN_PATH" 2>/dev/null || stat --printf="%s" "$BIN_PATH" 2>/dev/null)
  BIN_KB=$(python3 -c "print(round(${BIN_BYTES}/1024, 1))")
else
  BIN_BYTES=1744448
  BIN_KB=1703.6
fi

# ---- Derived stats ----
PROJECT_AGE=$(python3 -c "from datetime import date;d1=date(*(int(x) for x in '${FIRST_DATE}'.split('-')));d2=date(*(int(x) for x in '${LATEST_DATE}'.split('-')));print((d2-d1).days)")
COMMITS_PER_DAY=$(python3 -c "d=max(1,${PROJECT_AGE});print(round(${TOTAL_COMMITS}/d, 1))")
LINES_PER_DAY=$(python3 -c "d=max(1,${PROJECT_AGE});print(int(round(${TOTAL_LINES}/d, 0)))")
LATE_PCT=$(python3 -c "t=max(1,${TOTAL_COMMITS});print(int(round(${LATE_NIGHT}/t*100, 0)))")
TOTAL_FUNCS=$((CPP_FUNCS + JS_FUNCS))
CHURN=$((INSERTIONS + DELETIONS))

# COCOMO II basic model
COCOMO=$(python3 -c "
kloc = ${TOTAL_LINES}/1000
effort = 2.4 * (kloc ** 1.05)
schedule = 2.5 * (effort ** 0.38)
cost = int(effort * 8000)
print(f'{effort:.1f}|{schedule:.1f}|{cost}')
")
COCOMO_EFFORT=$(echo "$COCOMO" | cut -d'|' -f1)
COCOMO_SCHED=$(echo "$COCOMO" | cut -d'|' -f2)
COCOMO_COST=$(echo "$COCOMO" | cut -d'|' -f3)

# ---- AI session stats ----
SESSION_DIR="/Users/admin/.claude/projects/-Users-admin-MASS-Trap"
if [[ -d "$SESSION_DIR" ]]; then
  SESSION_COUNT=$(ls "$SESSION_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
  SESSION_BYTES=$(cat "$SESSION_DIR"/*.jsonl 2>/dev/null | wc -c | tr -d ' ')
  SESSION_MB=$(python3 -c "print(round(${SESSION_BYTES}/1048576, 1))")
  SESSION_PAGES=$(python3 -c "print(int(round(${SESSION_BYTES}/1910, 0)))")  # ~1910 bytes per page estimate
else
  SESSION_COUNT=4
  SESSION_MB=167.7
  SESSION_PAGES=92120
fi

# ---- Fun facts (dynamically generated) ----
STACK_MM=$(python3 -c "print(round(${TOTAL_LINES} * 0.03, 1))")  # ~0.03mm per line single-spaced
STACK_FT=$(python3 -c "print(round(${STACK_MM} / 304.8, 1))")

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NOW_HUMAN=$(date "+%B %d, %Y at %I:%M %p")

# ---- Generate JSON ----
JSON=$(cat <<ENDJSON
{
  "_comment": "M.A.S.S. Trap Project Stats — The Baseball Card. Auto-generated by generate_stats.sh. DO NOT EDIT BY HAND.",
  "_generated": "${NOW}",
  "_generated_human": "${NOW_HUMAN}",
  "_version": "1.0.0",

  "project": {
    "name": "M.A.S.S. Trap",
    "full_name": "Motion Analysis & Speed System",
    "tagline": "Forensic-Grade Physics Lab for \$7",
    "version": "2.6.0-beta",
    "license": "MIT",
    "repo": "https://github.com/Ryan4n6/MASS-Trap",
    "pages_url": "https://ryan4n6.github.io/MASS-Trap/",
    "ga_id": "G-61YKX0133N"
  },

  "codebase": {
    "total_lines": ${TOTAL_LINES},
    "total_files": ${TOTAL_FILES},
    "cpp_lines": ${CPP_LINES},
    "html_lines": ${HTML_LINES},
    "js_lines": ${JS_LINES},
    "css_lines": ${CSS_LINES},
    "cpp_functions": ${CPP_FUNCS},
    "js_functions": ${JS_FUNCS},
    "total_functions": ${TOTAL_FUNCS},
    "api_endpoints": ${API_ROUTES},
    "espnow_message_types": 14,
    "themes": 5,
    "features_shipped": ${FEATURES_DONE},
    "features_wip": ${FEATURES_WIP},
    "dashboard_kb": ${DASH_KB},
    "web_pages_esp32": ${ESP_PAGES},
    "web_pages_github": ${DOC_PAGES}
  },

  "firmware": {
    "version": "2.6.0-beta",
    "binary_bytes": ${BIN_BYTES},
    "binary_kb": ${BIN_KB},
    "flash_pct": 55.4,
    "ram_pct": 19.6,
    "build_date": "2026-02-16",
    "mcu": "ESP32-S3-WROOM-1 N16R8",
    "flash_mb": 16,
    "psram_mb": 8,
    "cores": 2,
    "clock_mhz": 240,
    "littlefs_mb": 9.9,
    "ota_slots": 2,
    "external_deps": 2
  },

  "git": {
    "total_commits": ${TOTAL_COMMITS},
    "total_insertions": ${INSERTIONS},
    "total_deletions": ${DELETIONS},
    "total_churn": ${CHURN},
    "first_commit_date": "${FIRST_DATE}",
    "latest_commit_date": "${LATEST_DATE}",
    "latest_commit_hash": "${LATEST_HASH}",
    "project_age_days": ${PROJECT_AGE},
    "commits_per_day": ${COMMITS_PER_DAY},
    "lines_per_day": ${LINES_PER_DAY},
    "late_night_commits": ${LATE_NIGHT},
    "late_night_pct": ${LATE_PCT},
    "active_days": ${ACTIVE_DAYS},
    "current_streak_days": ${STREAK},
    "contributors": ${CONTRIBUTORS},
    "tags": ${TAGS},
    "releases": ${TAGS},
    "secrets_scrubbed": 6
  },

  "economics": {
    "cocomo_effort_person_months": ${COCOMO_EFFORT},
    "cocomo_schedule_months": ${COCOMO_SCHED},
    "cocomo_cost_usd": ${COCOMO_COST},
    "actual_days": ${PROJECT_AGE},
    "actual_cost_hardware_usd": 1200,
    "mcu_unit_cost_usd": 7,
    "amazon_orders": 30,
    "aliexpress_boards_sat_years": 2.5
  },

  "ai_collaboration": {
    "sessions": ${SESSION_COUNT},
    "session_total_mb": ${SESSION_MB},
    "session_pages_est": ${SESSION_PAGES},
    "neuralyzer_events": 3,
    "agent_codename": "Agent K",
    "human_codename": "Agent J"
  },

  "fun_facts": [
    "${SESSION_MB}MB of conversation — longer than the entire Lord of the Rings trilogy in raw text",
    "Agent K has been neuralized ${SESSION_COUNT} times and still remembered where the config file was",
    "${LATE_PCT}% of commits happened between 10pm and 6am — this project only exists in the dark",
    "The COCOMO model says this should have taken ${COCOMO_SCHED} months. It took ${PROJECT_AGE} days.",
    "The dashboard is ${DASH_KB}KB — bigger than the original Doom executable (144KB)",
    "${COMMITS_PER_DAY} commits per day means a new feature landed roughly every 3 hours",
    "${TOTAL_LINES} lines of code. Printed single-spaced, the stack would be ${STACK_MM}mm tall — ${STACK_FT} feet",
    "${TOTAL_FUNCS} functions working harder than a one-armed paper hanger",
    "${API_ROUTES} API endpoints — more than most production SaaS startups",
    "The firmware binary is ${BIN_KB}KB — fits in the space of one low-res cat photo",
    "\$${COCOMO_COST}: what this codebase would cost conventionally. Hardware budget: \$1,200"
  ]
}
ENDJSON
)

if $DRY_RUN; then
  echo "$JSON"
else
  echo "$JSON" > docs/stats.json
  echo "✅ docs/stats.json regenerated ($(date))"
  echo "   ${TOTAL_LINES} lines | ${TOTAL_COMMITS} commits | ${TOTAL_FILES} files | ${TOTAL_FUNCS} functions"
  echo "   COCOMO: \$${COCOMO_COST} over ${COCOMO_SCHED} months (actual: ${PROJECT_AGE} days)"
  echo "   AI sessions: ${SESSION_COUNT} (${SESSION_MB}MB / ~${SESSION_PAGES} pages)"
fi
