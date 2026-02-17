#!/bin/bash
# ============================================================================
#  kristina.sh — The Special K Report™
#  "Are you guys even getting anything done?"
#
#  Usage: ./kristina.sh          (full report)
#         ./kristina.sh --quick  (one-liner for iMessage)
#         ./kristina.sh --json   (machine-readable for dashboards)
#         ./kristina.sh --html   (generate data/about.html for ESP32)
#
#  Named with love. Run with pride. Deploy when doubted.
# ============================================================================

set -e
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# Colors (disabled if piped)
if [ -t 1 ]; then
  GOLD='\033[1;33m'
  CYAN='\033[1;36m'
  GREEN='\033[1;32m'
  RED='\033[1;31m'
  DIM='\033[2m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GOLD=''; CYAN=''; GREEN=''; RED=''; DIM=''; BOLD=''; RESET=''
fi

# ---- Core Stats ----
TOTAL_COMMITS=$(git log --oneline | wc -l | tr -d ' ')
FIRST_COMMIT_DATE=$(git log --reverse --format="%ai" | head -1 | cut -d' ' -f1)
LATEST_COMMIT_DATE=$(git log -1 --format="%ai" | cut -d' ' -f1)
FIRST_EPOCH=$(git log --reverse --format="%at" | head -1)
LATEST_EPOCH=$(git log -1 --format="%at")
NOW_EPOCH=$(date +%s)
PROJECT_AGE_DAYS=$(( (NOW_EPOCH - FIRST_EPOCH) / 86400 ))
if [ "$PROJECT_AGE_DAYS" -eq 0 ]; then PROJECT_AGE_DAYS=1; fi
DAYS_SINCE_LAST=$(( (NOW_EPOCH - LATEST_EPOCH) / 86400 ))

TOTAL_LINES=$(git ls-files | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
TOTAL_FILES=$(git ls-files | wc -l | tr -d ' ')
TOTAL_INSERTIONS=$(git log --shortstat | grep "files changed" | awk '{s+=$4} END {print s+0}')
TOTAL_DELETIONS=$(git log --shortstat | grep "files changed" | awk '{s+=$6} END {print s+0}')
TOTAL_TOUCHED=$((TOTAL_INSERTIONS + TOTAL_DELETIONS))

CPP_LINES=$(git ls-files '*.cpp' '*.h' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
HTML_LINES=$(git ls-files '*.html' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
JS_LINES=$(git ls-files '*.js' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
CSS_LINES=$(git ls-files '*.css' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')

# Functions count
CPP_FUNCS=$(grep -rh "^void \|^bool \|^int \|^String \|^float \|^uint" *.cpp *.h 2>/dev/null | wc -l | tr -d ' ')
JS_FUNCS=$(grep -ch "function " data/*.html data/*.js 2>/dev/null | awk '{s+=$1} END {print s+0}')
API_ENDPOINTS=$(grep -c "server.on" web_server.cpp 2>/dev/null || echo 0)

# Late night commits (10pm - 6am)
LATE_NIGHT=$(git log --format="%ad" --date=format:"%H" | awk '$1 >= 22 || $1 <= 6' | wc -l | tr -d ' ')
LATE_PCT=$(( LATE_NIGHT * 100 / TOTAL_COMMITS ))

# Commits per day average
COMMITS_PER_DAY=$(echo "scale=1; $TOTAL_COMMITS / $PROJECT_AGE_DAYS" | bc)
LINES_PER_DAY=$(echo "scale=0; $TOTAL_INSERTIONS / $PROJECT_AGE_DAYS" | bc)

# Biggest single commit
BIGGEST_COMMIT=$(git log --shortstat --format="%H %s" | grep -B1 "files changed" | paste - - | awk -F',' '{gsub(/[^0-9]/,"",$2); print $2 " " $0}' | sort -rn | head -1)
BIGGEST_LINES=$(echo "$BIGGEST_COMMIT" | awk '{print $1}')
BIGGEST_MSG=$(echo "$BIGGEST_COMMIT" | sed 's/^[0-9]* [a-f0-9]* //' | sed 's/[0-9]* files changed.*//' | head -c 60)

# Dashboard growth
DASH_NOW=$(wc -c < data/dashboard.html | tr -d ' ')
DASH_KB=$(echo "scale=1; $DASH_NOW / 1024" | bc)

# Streak (consecutive days with commits)
STREAK=0
CHECK_DATE=$NOW_EPOCH
while true; do
  CHECK_DAY=$(date -r $CHECK_DATE +%Y-%m-%d 2>/dev/null || date -d @$CHECK_DATE +%Y-%m-%d 2>/dev/null)
  HAS_COMMIT=$(git log --format="%ad" --date=format:"%Y-%m-%d" | grep -c "^${CHECK_DAY}$" || true)
  if [ "$HAS_COMMIT" -gt 0 ]; then
    STREAK=$((STREAK + 1))
    CHECK_DATE=$((CHECK_DATE - 86400))
  else
    break
  fi
done

# Uncommitted work
UNCOMMITTED_ADD=$(git diff HEAD --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
UNCOMMITTED_DEL=$(git diff HEAD --numstat 2>/dev/null | awk '{s+=$2} END {print s+0}')
UNCOMMITTED_FILES=$(git diff HEAD --name-only 2>/dev/null | wc -l | tr -d ' ')

# Conversation logs (Claude sessions)
CLAUDE_DIR="/Users/admin/.claude/projects/-Users-admin-MASS-Trap"
if [ -d "$CLAUDE_DIR" ]; then
  CLAUDE_SESSIONS=$(ls "$CLAUDE_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
  CLAUDE_TOTAL_MB=$(du -sm "$CLAUDE_DIR" 2>/dev/null | awk '{print $1}')
  CLAUDE_PAGES=$(echo "scale=0; $CLAUDE_TOTAL_MB * 1048576 / 2000" | bc 2>/dev/null || echo "0")
else
  CLAUDE_SESSIONS=0
  CLAUDE_TOTAL_MB=0
  CLAUDE_PAGES=0
fi

# ---- Random "Baseball Announcer" Stats ----
# Pick a random fun stat each run
RANDOM_STATS=(
  "That's ${LINES_PER_DAY} lines of code per day — more output than a court stenographer on espresso."
  "At ${COMMITS_PER_DAY} commits/day, this repo ships faster than Amazon Prime."
  "${LATE_PCT}% of commits happened between 10pm and 6am. Sleep is for projects that don't have deadlines."
  "The dashboard is now ${DASH_KB}KB. That's bigger than the original Doom executable."
  "${CPP_FUNCS} C++ functions and ${JS_FUNCS} JavaScript functions. That's ${TOTAL_FUNCS:=$((CPP_FUNCS + JS_FUNCS))} functions working harder than a substitute teacher on a Friday."
  "This firmware has ${API_ENDPOINTS} API endpoints. The Twitter API launched with 20."
  "${TOTAL_TOUCHED} total lines touched in ${PROJECT_AGE_DAYS} days. That's a novel every $(echo "scale=1; $PROJECT_AGE_DAYS * 250 / $TOTAL_INSERTIONS" | bc 2>/dev/null || echo '0.3') days."
  "The ESP32 running this costs \$7. The software on it would cost \$$(echo "scale=0; $TOTAL_LINES * 15 / 100" | bc 2>/dev/null || echo '3000')+ to commission."
  "Current streak: ${STREAK} consecutive day(s) with commits. The man does not take days off."
  "${TOTAL_FILES} files in the repo. Each one handcrafted. No boilerplate. No frameworks. Pure violence."
  "${CLAUDE_SESSIONS} pair programming sessions totaling ~${CLAUDE_TOTAL_MB}MB of dialogue. That's roughly ${CLAUDE_PAGES} pages — longer than War and Peace. Five times over."
  "If these ${TOTAL_LINES} lines were printed single-spaced, the stack would be $(echo "scale=1; $TOTAL_LINES * 0.3 / 10" | bc 2>/dev/null || echo '645')mm tall. Taller than a Hot Wheels car."
)
RANDOM_INDEX=$((RANDOM % ${#RANDOM_STATS[@]}))
RANDOM_STAT="${RANDOM_STATS[$RANDOM_INDEX]}"

# ---- Feature Inventory (Kristina-Friendly Descriptions) ----
FEATURES=(
  "Playlist Mode|Guided science fair testing — tells Ben which car to run next|done"
  "Evidence System|Every race gets a case number, QR code, and printable label|done"
  "Photo Upload|Tap the camera on any evidence tag, photo links to the run automatically|done"
  "NFC Tags|Scan a sticker on the car — auto-selects car and arms the track|done"
  "Science Fair Report|One button generates a full forensic report with data and analysis|done"
  "Label Printing|Evidence tags print on 7 different label printer models|done"
  "5 Visual Themes|Classic, Case File, Cyber, Minimalist, and Dark themes|done"
  "Browser Firmware Update|Update device firmware from any web browser — no cables needed|done"
  "Audio Announcer|Track calls out race results, car names, and speed records|done"
  "LiDAR Auto-Arm|TF-Luna laser sensor detects car at start gate, arms automatically|done"
  "Speed Trap|Third sensor measures mid-track velocity with dual IR beams|done"
  "Live Leaderboard|Most Wanted list ranks all cars by speed with criminal verdicts|done"
  "Kiosk Mode|Display-only presentation mode for science fair booth|done"
  "The Special K Report|Click version badge on any page to see this — you are here|done"
  "Logo and Badge|Judge Dredd shield design for the project identity|wip"
)

# ---- Commit Timeline ----
COMMIT_LOG=$(git log --format="%ai|%s" -20)

# Software value estimate
SOFTWARE_VALUE=$(echo "scale=0; $TOTAL_LINES * 15 / 100" | bc 2>/dev/null || echo "3000")

# Conversation hours estimate (~500 words/min reading speed, ~250 words/page)
CONVO_HOURS=$(echo "scale=0; $CLAUDE_PAGES * 250 / 500 / 60" | bc 2>/dev/null || echo "700")

# ---- Output Modes ----

if [ "$1" = "--html" ]; then
  # Generate standalone About page for ESP32
  OUTPUT_FILE="$REPO_DIR/data/about.html"
  GENERATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  GENERATED_HUMAN=$(date "+%B %d, %Y at %I:%M %p")

  cat > "$OUTPUT_FILE" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
<title>The Special K Report™ — M.A.S.S. Trap</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{--navy:#091B2F;--navy-light:#0d2847;--navy-mid:#112d4e;--gold:#D4AF37;--gold-dim:rgba(212,175,55,0.3);--orange:#FF4500;--text:#E8E8E8;--text-muted:#8899AA;--green:#28a745;--red:#dc3545;--cyan:#17a2b8;--font-main:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;--font-data:"SF Mono",Monaco,"Cascadia Code",monospace}
body{background:var(--navy);color:var(--text);font-family:var(--font-main);line-height:1.6;min-height:100vh}
.container{max-width:900px;margin:0 auto;padding:20px 16px 60px}
a{color:var(--gold);text-decoration:none}
a:hover{text-decoration:underline}

/* Hero */
.hero{text-align:center;padding:40px 20px 30px;border-bottom:2px solid var(--gold-dim);margin-bottom:30px}
.hero-badge{display:inline-block;background:var(--gold);color:var(--navy);font-size:0.7rem;font-weight:700;padding:3px 12px;border-radius:12px;text-transform:uppercase;letter-spacing:1px;margin-bottom:12px}
.hero h1{font-size:2rem;color:var(--gold);margin-bottom:4px;letter-spacing:2px}
.hero h2{font-size:1rem;color:var(--text-muted);font-weight:400;margin-bottom:8px}
.hero .subtitle{font-style:italic;color:var(--text-muted);font-size:0.9rem}
@media(max-width:600px){.hero h1{font-size:1.4rem}.hero{padding:24px 12px 20px}}

/* Section */
.section{margin-bottom:28px}
.section-title{font-size:1.1rem;color:var(--gold);border-bottom:1px solid var(--gold-dim);padding-bottom:6px;margin-bottom:14px;display:flex;align-items:center;gap:8px}
.section-title span{font-size:1.2rem}

/* Bio */
.bio{background:var(--navy-light);border:1px solid var(--gold-dim);border-radius:10px;padding:20px;line-height:1.8;color:var(--text-muted);font-size:0.92rem}
.bio strong{color:var(--text)}
.bio em{color:var(--gold)}

/* Stat Cards */
.stats-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:12px}
.stat-card{background:var(--navy-light);border:1px solid var(--gold-dim);border-radius:10px;padding:16px 12px;text-align:center;transition:border-color 0.2s}
.stat-card:hover{border-color:var(--gold)}
.stat-value{font-size:1.8rem;font-weight:700;color:var(--gold);font-family:var(--font-data);line-height:1.2}
.stat-label{font-size:0.7rem;color:var(--text-muted);text-transform:uppercase;letter-spacing:1px;margin-top:4px}
@media(max-width:480px){.stats-grid{grid-template-columns:repeat(2,1fr)}.stat-value{font-size:1.4rem}}

/* Features */
.feature-list{list-style:none}
.feature-item{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);display:flex;align-items:flex-start;gap:10px;font-size:0.9rem}
.feature-item:last-child{border-bottom:none}
.feature-icon{font-size:1.1rem;flex-shrink:0;margin-top:1px}
.feature-name{color:var(--text);font-weight:600}
.feature-desc{color:var(--text-muted)}

/* Live Status */
.live-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:10px}
.live-card{background:var(--navy-light);border:1px solid rgba(255,255,255,0.08);border-radius:8px;padding:12px;font-size:0.85rem}
.live-card .label{color:var(--text-muted);font-size:0.7rem;text-transform:uppercase;letter-spacing:0.5px}
.live-card .value{color:var(--text);font-family:var(--font-data);font-size:1rem;margin-top:2px}
.live-card .value.online{color:var(--green)}
.live-card .value.offline{color:var(--red)}
.live-pulse{display:inline-block;width:8px;height:8px;background:var(--green);border-radius:50%;margin-right:6px;animation:pulse 2s ease-in-out infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.3}}

/* Builders */
.builders{background:var(--navy-light);border:1px solid var(--gold-dim);border-radius:10px;padding:24px;text-align:center}
.builder-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:16px;margin-bottom:20px}
.builder{padding:12px}
.builder-name{font-size:1rem;font-weight:700;color:var(--gold)}
.builder-role{font-size:0.78rem;color:var(--text-muted);margin-top:2px}
.dedication{font-style:italic;color:var(--text-muted);font-size:0.88rem;line-height:1.7;max-width:640px;margin:0 auto;border-top:1px solid var(--gold-dim);padding-top:16px}

/* Announcer */
.announcer{background:linear-gradient(135deg,var(--navy-light),var(--navy-mid));border:2px solid var(--gold);border-radius:12px;padding:20px 24px;text-align:center;font-size:1rem;color:var(--cyan);font-style:italic;line-height:1.6;position:relative}
.announcer::before{content:"⚾";font-size:1.4rem;display:block;margin-bottom:8px;font-style:normal}

/* Timeline */
.timeline{font-size:0.82rem}
.timeline-item{padding:8px 0;border-bottom:1px solid rgba(255,255,255,0.04);display:flex;gap:12px}
.timeline-item:last-child{border-bottom:none}
.timeline-date{color:var(--text-muted);font-family:var(--font-data);white-space:nowrap;min-width:90px;flex-shrink:0}
.timeline-msg{color:var(--text)}
.timeline-toggle{background:none;border:1px solid var(--gold-dim);color:var(--text-muted);padding:6px 14px;border-radius:6px;font-size:0.8rem;cursor:pointer;margin-top:8px}
.timeline-toggle:hover{border-color:var(--gold);color:var(--gold)}

/* Roster */
.roster-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:8px}
.roster-item{display:flex;justify-content:space-between;padding:6px 12px;background:var(--navy-light);border-radius:6px;font-size:0.85rem}
.roster-item .lang{color:var(--text-muted)}
.roster-item .count{color:var(--text);font-family:var(--font-data);font-weight:600}

/* Footer */
.footer{text-align:center;padding:30px 20px;border-top:1px solid var(--gold-dim);margin-top:30px;color:var(--text-muted);font-size:0.8rem}
.footer .tagline{color:var(--gold);font-style:italic;margin-bottom:8px;font-size:0.9rem}

/* Update notice */
.update-notice{background:rgba(220,53,69,0.1);border:1px solid rgba(220,53,69,0.3);border-radius:8px;padding:12px 16px;margin-bottom:20px;display:none;text-align:center}
.update-notice a{color:var(--red);font-weight:700}

/* Print */
@media print{body{background:#fff;color:#000}.hero h1,.section-title{color:#333}.stat-card,.bio,.builders,.announcer{border-color:#ccc;background:#f9f9f9}.stat-value,.builder-name{color:#333}.live-card{display:none}}
</style>
</head>
<body>
<div class="container">

<!-- Update Notice (hidden unless update detected) -->
<div class="update-notice" id="updateNotice">
  A firmware update is available: <a href="https://github.com/Ryan4n6/MASS-Trap/releases/latest" target="_blank" id="updateLink">Download</a>
</div>

<!-- Hero -->
<div class="hero">
  <div class="hero-badge">Est. 2026</div>
  <h1>THE KRISTINA REPORT&trade;</h1>
  <h2>M.A.S.S. Trap &mdash; Motion Analysis &amp; Speed System</h2>
  <p class="subtitle">&ldquo;Are you guys even getting anything done?&rdquo;</p>
</div>

<!-- Project Bio -->
<div class="section">
  <div class="section-title"><span>📖</span> About This Project</div>
  <div class="bio">
    <strong>M.A.S.S. Trap</strong> is a <em>forensic-grade physics laboratory</em> disguised as a Hot Wheels track speedometer.
    Built on a <strong>$7 ESP32 microcontroller</strong>, it measures race timing with <em>microsecond precision</em>,
    calculates velocity, momentum, and kinetic energy, and serves a full web dashboard over WiFi.
    <br><br>
    It was built for <strong>Ben Massfeller's</strong> 5th grade science fair project &mdash;
    an investigation into how mass affects the speed of 1:64 scale vehicles on an inclined track.
    Every race is logged. Every result has a chain of custody. Every data point is court-admissible.
    <br><br>
    The software on this device would cost <strong id="softwareValue">$3,000+</strong> to commission professionally.
    It runs on hardware that costs less than lunch.
  </div>
</div>

<!-- The Scoreboard -->
<div class="section">
  <div class="section-title"><span>📊</span> The Scoreboard</div>
  <div class="stats-grid">
    <div class="stat-card"><div class="stat-value" id="statLines">--</div><div class="stat-label">Lines of Code</div></div>
    <div class="stat-card"><div class="stat-value" id="statCommits">--</div><div class="stat-label">At-Bats (Commits)</div></div>
    <div class="stat-card"><div class="stat-value" id="statAge">--</div><div class="stat-label">Days in Season</div></div>
    <div class="stat-card"><div class="stat-value" id="statLateNight">--%</div><div class="stat-label">After Hours</div></div>
    <div class="stat-card"><div class="stat-value" id="statStreak">--</div><div class="stat-label">Day Streak</div></div>
    <div class="stat-card"><div class="stat-value" id="statFiles">--</div><div class="stat-label">Files in Play</div></div>
  </div>
</div>

<!-- Feature Inventory -->
<div class="section">
  <div class="section-title"><span>🏗️</span> What We Built</div>
  <ul class="feature-list" id="featureList"></ul>
</div>

<!-- The Roster -->
<div class="section">
  <div class="section-title"><span>🏟️</span> The Roster</div>
  <div class="roster-grid" id="rosterGrid"></div>
</div>

<!-- Device Status (Live) -->
<div class="section">
  <div class="section-title"><span>📡</span> Live Device Status</div>
  <div class="live-grid" id="liveGrid">
    <div class="live-card"><div class="label">Status</div><div class="value" id="liveStatus">Connecting...</div></div>
    <div class="live-card"><div class="label">Firmware</div><div class="value"><a href="https://github.com/Ryan4n6/MASS-Trap/releases" target="_blank" id="liveFirmware" style="color:inherit;text-decoration:underline dotted">--</a></div></div>
    <div class="live-card"><div class="label">Uptime</div><div class="value" id="liveUptime">--</div></div>
    <div class="live-card"><div class="label">Free Memory</div><div class="value" id="liveHeap">--</div></div>
    <div class="live-card"><div class="label">WiFi Signal</div><div class="value" id="liveRssi">--</div></div>
    <div class="live-card"><div class="label">Connected Brothers</div><div class="value" id="livePeers">--</div></div>
  </div>
</div>

<!-- Race Activity (Live) -->
<div class="section">
  <div class="section-title"><span>🏎️</span> Race Activity</div>
  <div class="live-grid" id="raceGrid">
    <div class="live-card"><div class="label">Total Races</div><div class="value" id="racesTotal">--</div></div>
    <div class="live-card"><div class="label">Cars in Garage</div><div class="value" id="garageCount">--</div></div>
    <div class="live-card"><div class="label">Fastest Time</div><div class="value" id="fastestTime">--</div></div>
    <div class="live-card"><div class="label">Top Speed</div><div class="value" id="topSpeed">--</div></div>
  </div>
</div>

<!-- Pair Programming -->
<div class="section">
  <div class="section-title"><span>🤖</span> Pair Programming</div>
  <div class="stats-grid">
    <div class="stat-card"><div class="stat-value" id="claudeSessions">--</div><div class="stat-label">Sessions</div></div>
    <div class="stat-card"><div class="stat-value" id="claudeMB">--</div><div class="stat-label">MB of Dialogue</div></div>
    <div class="stat-card"><div class="stat-value" id="claudePages">--</div><div class="stat-label">Pages (~250 words ea.)</div></div>
    <div class="stat-card"><div class="stat-value" id="claudeHours">--</div><div class="stat-label">Est. Hours</div></div>
  </div>
</div>

<!-- Announcer's Booth -->
<div class="section">
  <div class="section-title"><span>⚾</span> Announcer&rsquo;s Booth</div>
  <div class="announcer" id="announcerBooth">Loading...</div>
</div>

<!-- Commit Timeline -->
<div class="section">
  <div class="section-title"><span>📅</span> Commit Timeline</div>
  <div class="timeline" id="commitTimeline"></div>
  <button class="timeline-toggle" id="timelineToggle" style="display:none" onclick="toggleTimeline()">Show All</button>
</div>

<!-- The Builders -->
<div class="section">
  <div class="section-title"><span>🔨</span> The Builders</div>
  <div class="builders">
    <div class="builder-grid">
      <div class="builder">
        <div class="builder-name">Ryan Massfeller</div>
        <div class="builder-role">Creator &bull; Firmware Engineer &bull; 3am Architect</div>
      </div>
      <div class="builder">
        <div class="builder-name">Claude</div>
        <div class="builder-role">AI Pair Programmer &bull; Co-author &bull; Anthropic</div>
      </div>
      <div class="builder">
        <div class="builder-name">Ben Massfeller</div>
        <div class="builder-role">Chief Test Pilot &bull; Science Fair Scientist &bull; Age 10</div>
      </div>
      <div class="builder">
        <div class="builder-name">Sam Massfeller</div>
        <div class="builder-role">V1 Creator &bull; Hardware Builder &bull; Original Vibe Coder</div>
      </div>
      <div class="builder">
        <div class="builder-name">Kristina Massfeller</div>
        <div class="builder-role">Stepmom &bull; Team Morale &bull; The One Who Keeps Us Fed</div>
      </div>
      <div class="builder">
        <div class="builder-name">Richard Massfeller</div>
        <div class="builder-role">Dad &bull; Formula Vee Racer &bull; The 7-Foot Pencil Legend</div>
      </div>
      <div class="builder">
        <div class="builder-name">Sam Troia</div>
        <div class="builder-role">Uncle Sam &bull; Columbia University &bull; Concert Pianist &bull; In Memoriam</div>
      </div>
      <div class="builder">
        <div class="builder-name">Stephen Massfeller</div>
        <div class="builder-role">Uncle Beaver &bull; Pipeline Welder &bull; Built Things That Last &bull; In Memoriam</div>
      </div>
    </div>
    <div class="dedication">
      This project was built at kitchen tables and workbenches between the hours of
      midnight and sunrise. A dad, his two sons, a stepmom who keeps the whole operation running,
      and an AI &mdash; carrying forward the legacy of Richard&rsquo;s Formula Vees, Uncle Sam&rsquo;s
      perfect pitch, and Uncle Beaver&rsquo;s pipeline welds. The best tools in the world are
      worthless without the people willing to stay up all night using them.
      <br><br>
      <em>For Sam Troia and Stephen Massfeller &mdash; who built things that mattered.</em>
      <br><br>
      <span id="convoHoursNote">Built with love, caffeine, and approximately -- hours of conversation.</span>
    </div>
  </div>
</div>

<!-- Links -->
<div class="section">
  <div class="section-title"><span>🔗</span> Links</div>
  <div style="display:flex;flex-wrap:wrap;gap:12px;justify-content:center;padding:12px 0">
    <a href="https://github.com/Ryan4n6/MASS-Trap" target="_blank" style="color:var(--gold);text-decoration:none;padding:8px 16px;border:1px solid var(--gold);border-radius:6px">&#128187; GitHub Repo</a>
    <a href="https://ryan4n6.github.io/MASS-Trap/" target="_blank" style="color:var(--gold);text-decoration:none;padding:8px 16px;border:1px solid var(--gold);border-radius:6px">&#127968; Project Site</a>
    <a href="https://ryan4n6.github.io/MASS-Trap/store.html" target="_blank" style="color:var(--gold);text-decoration:none;padding:8px 16px;border:1px solid var(--gold);border-radius:6px">&#128722; Parts Store</a>
    <a href="https://github.com/Ryan4n6/MASS-Trap/releases" target="_blank" style="color:var(--gold);text-decoration:none;padding:8px 16px;border:1px solid var(--gold);border-radius:6px">&#128230; Releases</a>
  </div>
</div>

<!-- Footer -->
<div class="footer">
  <div class="tagline">The Special K Report&trade; &mdash; because the scoreboard doesn&rsquo;t lie.</div>
  <div><a href="/dashboard.html">&larr; Back to Dashboard</a></div>
  <div style="margin-top:8px" id="generatedAt">Generated: --</div>
</div>

</div>

<script>
HTMLEOF

  # Now inject the JavaScript with baked-in stats
  cat >> "$OUTPUT_FILE" << JSEOF
// ---- Baked-in Stats (generated $(date "+%Y-%m-%d %H:%M:%S")) ----
var STATS = {
  totalLines: ${TOTAL_LINES},
  totalCommits: ${TOTAL_COMMITS},
  totalFiles: ${TOTAL_FILES},
  totalInsertions: ${TOTAL_INSERTIONS},
  totalDeletions: ${TOTAL_DELETIONS},
  totalTouched: ${TOTAL_TOUCHED},
  projectAgeDays: ${PROJECT_AGE_DAYS},
  firstCommitDate: "${FIRST_COMMIT_DATE}",
  latestCommitDate: "${LATEST_COMMIT_DATE}",
  daysSinceLast: ${DAYS_SINCE_LAST},
  commitsPerDay: ${COMMITS_PER_DAY},
  linesPerDay: ${LINES_PER_DAY},
  lateNight: ${LATE_NIGHT},
  latePct: ${LATE_PCT},
  streak: ${STREAK},
  cppLines: ${CPP_LINES},
  htmlLines: ${HTML_LINES},
  jsLines: ${JS_LINES},
  cssLines: ${CSS_LINES},
  cppFuncs: ${CPP_FUNCS},
  jsFuncs: ${JS_FUNCS},
  apiEndpoints: ${API_ENDPOINTS},
  dashKB: ${DASH_KB},
  claudeSessions: ${CLAUDE_SESSIONS},
  claudeTotalMB: ${CLAUDE_TOTAL_MB},
  claudePages: ${CLAUDE_PAGES},
  convoHours: ${CONVO_HOURS},
  softwareValue: ${SOFTWARE_VALUE},
  generated: "${GENERATED}",
  generatedHuman: "${GENERATED_HUMAN}"
};

var FEATURES = [
JSEOF

  # Inject features array
  for feat in "${FEATURES[@]}"; do
    FNAME=$(echo "$feat" | cut -d'|' -f1)
    FDESC=$(echo "$feat" | cut -d'|' -f2)
    FSTATUS=$(echo "$feat" | cut -d'|' -f3)
    echo "  {name:\"${FNAME}\",desc:\"${FDESC}\",status:\"${FSTATUS}\"}," >> "$OUTPUT_FILE"
  done

  cat >> "$OUTPUT_FILE" << 'JSEOF2'
];

var COMMITS = [
JSEOF2

  # Inject commit timeline
  while IFS='|' read -r cdate cmsg; do
    cdate_short=$(echo "$cdate" | cut -d' ' -f1)
    cmsg_escaped=$(echo "$cmsg" | sed 's/"/\\"/g' | sed "s/'/\\\\'/g")
    echo "  {date:\"${cdate_short}\",msg:\"${cmsg_escaped}\"}," >> "$OUTPUT_FILE"
  done <<< "$COMMIT_LOG"

  cat >> "$OUTPUT_FILE" << 'JSEOF3'
];

var ANNOUNCER_STATS = [
JSEOF3

  # Inject announcer stats as JS strings
  for stat in "${RANDOM_STATS[@]}"; do
    stat_escaped=$(echo "$stat" | sed 's/"/\\"/g')
    echo "  \"${stat_escaped}\"," >> "$OUTPUT_FILE"
  done

  cat >> "$OUTPUT_FILE" << 'JSEOF4'
];

// ---- Populate Page ----
function init() {
  // Scoreboard
  document.getElementById('statLines').textContent = STATS.totalLines.toLocaleString();
  document.getElementById('statCommits').textContent = STATS.totalCommits;
  document.getElementById('statAge').textContent = STATS.projectAgeDays;
  document.getElementById('statLateNight').textContent = STATS.latePct + '%';
  document.getElementById('statStreak').textContent = STATS.streak;
  document.getElementById('statFiles').textContent = STATS.totalFiles;
  document.getElementById('softwareValue').textContent = '$' + STATS.softwareValue.toLocaleString() + '+';

  // Pair Programming
  document.getElementById('claudeSessions').textContent = STATS.claudeSessions;
  document.getElementById('claudeMB').textContent = STATS.claudeTotalMB;
  document.getElementById('claudePages').textContent = STATS.claudePages.toLocaleString();
  document.getElementById('claudeHours').textContent = '~' + STATS.convoHours;
  document.getElementById('convoHoursNote').textContent =
    'Built with love, caffeine, and approximately ' + STATS.convoHours + ' hours of conversation.';

  // Features
  var fl = document.getElementById('featureList');
  var fhtml = '';
  for (var i = 0; i < FEATURES.length; i++) {
    var f = FEATURES[i];
    var icon = f.status === 'done' ? '✅' : '🔧';
    fhtml += '<li class="feature-item"><span class="feature-icon">' + icon + '</span><div><span class="feature-name">' + f.name + '</span> <span class="feature-desc">&mdash; ' + f.desc + '</span></div></li>';
  }
  fl.innerHTML = fhtml;

  // Roster
  var rg = document.getElementById('rosterGrid');
  var roster = [
    {lang: 'C++ (firmware)', count: STATS.cppLines.toLocaleString() + ' lines'},
    {lang: 'HTML (dashboard)', count: STATS.htmlLines.toLocaleString() + ' lines'},
    {lang: 'JavaScript', count: STATS.jsLines.toLocaleString() + ' lines'},
    {lang: 'CSS (5 themes)', count: STATS.cssLines.toLocaleString() + ' lines'},
    {lang: 'C++ functions', count: STATS.cppFuncs},
    {lang: 'JS functions', count: STATS.jsFuncs},
    {lang: 'API endpoints', count: STATS.apiEndpoints},
    {lang: 'Lines written', count: '+' + STATS.totalInsertions.toLocaleString()},
    {lang: 'Lines revised', count: '-' + STATS.totalDeletions.toLocaleString()}
  ];
  var rhtml = '';
  for (var r = 0; r < roster.length; r++) {
    rhtml += '<div class="roster-item"><span class="lang">' + roster[r].lang + '</span><span class="count">' + roster[r].count + '</span></div>';
  }
  rg.innerHTML = rhtml;

  // Timeline
  var tl = document.getElementById('commitTimeline');
  var thtml = '';
  var showInitial = 8;
  for (var t = 0; t < COMMITS.length; t++) {
    var hidden = t >= showInitial ? ' style="display:none" class="timeline-item timeline-extra"' : ' class="timeline-item"';
    thtml += '<div' + hidden + '><span class="timeline-date">' + COMMITS[t].date + '</span><span class="timeline-msg">' + COMMITS[t].msg + '</span></div>';
  }
  tl.innerHTML = thtml;
  if (COMMITS.length > showInitial) {
    document.getElementById('timelineToggle').style.display = 'inline-block';
  }

  // Announcer
  var idx = Math.floor(Math.random() * ANNOUNCER_STATS.length);
  document.getElementById('announcerBooth').innerHTML = '⚾<br>&ldquo;' + ANNOUNCER_STATS[idx] + '&rdquo;';

  // Generated timestamp
  document.getElementById('generatedAt').textContent = 'Stats generated: ' + STATS.generatedHuman;

  // Fetch live data
  fetchLiveData();
}

function toggleTimeline() {
  var extras = document.querySelectorAll('.timeline-extra');
  var btn = document.getElementById('timelineToggle');
  var showing = extras.length > 0 && extras[0].style.display !== 'none';
  for (var i = 0; i < extras.length; i++) {
    extras[i].style.display = showing ? 'none' : 'flex';
  }
  btn.textContent = showing ? 'Show All' : 'Show Less';
}

function fetchLiveData() {
  // Device info
  fetch('/api/info').then(function(r){return r.json()}).then(function(d) {
    document.getElementById('liveStatus').innerHTML = '<span class="live-pulse"></span>Online';
    document.getElementById('liveStatus').className = 'value online';
    document.getElementById('liveFirmware').textContent = 'v' + (d.firmware || d.version || '--');
    if (d.uptime_seconds) {
      var h = Math.floor(d.uptime_seconds / 3600);
      var m = Math.floor((d.uptime_seconds % 3600) / 60);
      document.getElementById('liveUptime').textContent = h + 'h ' + m + 'm';
    }
    if (d.heap_free) {
      document.getElementById('liveHeap').textContent = Math.round(d.heap_free / 1024) + ' KB';
    }
    if (d.wifi_rssi) {
      var rssi = d.wifi_rssi;
      var quality = rssi > -50 ? 'Excellent' : rssi > -60 ? 'Good' : rssi > -70 ? 'Fair' : 'Weak';
      document.getElementById('liveRssi').textContent = rssi + ' dBm (' + quality + ')';
    }
    if (typeof d.peer_count !== 'undefined') {
      document.getElementById('livePeers').textContent = d.peer_count;
    }

    // Check for firmware update
    checkUpdate(d.firmware || d.version);
  }).catch(function() {
    document.getElementById('liveStatus').textContent = 'Offline';
    document.getElementById('liveStatus').className = 'value offline';
  });

  // Race history
  fetch('/api/history').then(function(r){return r.json()}).then(function(h) {
    var races = h.races || h.history || [];
    document.getElementById('racesTotal').textContent = races.length;
    if (races.length > 0) {
      var fastest = Infinity, topSpd = 0;
      for (var i = 0; i < races.length; i++) {
        if (races[i].time && races[i].time < fastest) fastest = races[i].time;
        if (races[i].speed && races[i].speed > topSpd) topSpd = races[i].speed;
      }
      document.getElementById('fastestTime').textContent = fastest < Infinity ? fastest.toFixed(3) + 's' : '--';
      document.getElementById('topSpeed').textContent = topSpd > 0 ? topSpd.toFixed(2) + ' m/s' : '--';
    }
  }).catch(function(){});

  // Garage
  fetch('/api/garage').then(function(r){return r.json()}).then(function(g) {
    var cars = g.cars || g.garage || [];
    document.getElementById('garageCount').textContent = cars.length;
  }).catch(function(){});
}

function checkUpdate(currentFw) {
  if (!currentFw) return;
  fetch('https://api.github.com/repos/Ryan4n6/MASS-Trap/releases/latest')
    .then(function(r){return r.json()})
    .then(function(rel) {
      if (rel.tag_name) {
        var latest = rel.tag_name.replace(/^v/,'').replace(/-.*$/,'');
        var current = currentFw.replace(/-.*$/,'');
        if (latest !== current) {
          var notice = document.getElementById('updateNotice');
          var link = document.getElementById('updateLink');
          link.textContent = 'v' + latest + ' available — Download';
          link.href = rel.html_url || 'https://github.com/Ryan4n6/MASS-Trap/releases/latest';
          notice.style.display = 'block';
        }
      }
    }).catch(function(){});
}

// Go
init();
JSEOF4

  # Close the HTML
  cat >> "$OUTPUT_FILE" << 'HTMLEND'
</script>
</body>
</html>
HTMLEND

  echo "Generated: $OUTPUT_FILE"
  echo "Size: $(wc -c < "$OUTPUT_FILE" | tr -d ' ') bytes"
  echo ""
  echo "Deploy with:"
  echo "  curl -X POST \"http://192.168.1.83/api/files?path=/about.html\" -H \"X-API-Key: admin\" --data-binary @data/about.html"
  exit 0
fi

if [ "$1" = "--quick" ]; then
  # One-liner for iMessage
  echo "M.A.S.S. Trap: ${TOTAL_LINES} lines of code, ${TOTAL_COMMITS} commits in ${PROJECT_AGE_DAYS} days. ${LATE_NIGHT} late-night commits (${LATE_PCT}%). ${UNCOMMITTED_ADD} new lines pending. ${RANDOM_STAT}"
  exit 0
fi

if [ "$1" = "--json" ]; then
  cat <<ENDJSON
{
  "project": "M.A.S.S. Trap",
  "report": "The Special K Report",
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "age_days": ${PROJECT_AGE_DAYS},
  "total_commits": ${TOTAL_COMMITS},
  "total_lines": ${TOTAL_LINES},
  "total_files": ${TOTAL_FILES},
  "total_insertions": ${TOTAL_INSERTIONS},
  "total_deletions": ${TOTAL_DELETIONS},
  "total_touched": ${TOTAL_TOUCHED},
  "commits_per_day": ${COMMITS_PER_DAY},
  "lines_per_day": ${LINES_PER_DAY},
  "late_night_commits": ${LATE_NIGHT},
  "late_night_pct": ${LATE_PCT},
  "streak_days": ${STREAK},
  "cpp_lines": ${CPP_LINES},
  "html_lines": ${HTML_LINES},
  "js_lines": ${JS_LINES},
  "css_lines": ${CSS_LINES},
  "cpp_functions": ${CPP_FUNCS},
  "js_functions": ${JS_FUNCS},
  "api_endpoints": ${API_ENDPOINTS},
  "dashboard_kb": ${DASH_KB},
  "uncommitted_additions": ${UNCOMMITTED_ADD},
  "uncommitted_deletions": ${UNCOMMITTED_DEL},
  "claude_sessions": ${CLAUDE_SESSIONS},
  "claude_total_mb": ${CLAUDE_TOTAL_MB},
  "random_stat": "$(echo "$RANDOM_STAT" | sed 's/"/\\"/g')"
}
ENDJSON
  exit 0
fi

# ---- Full Report ----
echo ""
echo -e "${GOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GOLD}║${RESET}${BOLD}          ⚾ THE KRISTINA REPORT™ — M.A.S.S. Trap ⚾          ${RESET}${GOLD}║${RESET}"
echo -e "${GOLD}║${RESET}${DIM}       \"Are you guys even getting anything done?\"            ${RESET}${GOLD}║${RESET}"
echo -e "${GOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BOLD}📅 PROJECT TIMELINE${RESET}"
echo -e "   First pitch:     ${CYAN}${FIRST_COMMIT_DATE}${RESET}"
echo -e "   Latest at-bat:   ${CYAN}${LATEST_COMMIT_DATE}${RESET} (${DAYS_SINCE_LAST} day(s) ago)"
echo -e "   Season length:   ${BOLD}${PROJECT_AGE_DAYS} days${RESET}"
echo -e "   Current streak:  ${GREEN}${STREAK} consecutive day(s)${RESET}"
echo ""
echo -e "${BOLD}📊 BATTING AVERAGE${RESET}"
echo -e "   Total commits:        ${BOLD}${TOTAL_COMMITS}${RESET}"
echo -e "   Commits per day:      ${BOLD}${COMMITS_PER_DAY}${RESET}"
echo -e "   Lines written:        ${GREEN}+${TOTAL_INSERTIONS}${RESET}"
echo -e "   Lines revised:        ${RED}-${TOTAL_DELETIONS}${RESET}"
echo -e "   Total lines touched:  ${BOLD}${TOTAL_TOUCHED}${RESET}"
echo -e "   Lines per day:        ${BOLD}${LINES_PER_DAY}${RESET}"
echo ""
echo -e "${BOLD}🏟️  THE ROSTER${RESET}"
echo -e "   Files in play:    ${TOTAL_FILES}"
echo -e "   Lines on field:   ${TOTAL_LINES}"
echo -e "   C++ (firmware):   ${CPP_LINES} lines"
echo -e "   HTML (dashboard): ${HTML_LINES} lines"
echo -e "   JavaScript:       ${JS_LINES} lines"
echo -e "   CSS (5 themes):   ${CSS_LINES} lines"
echo -e "   C++ functions:    ${CPP_FUNCS}"
echo -e "   JS functions:     ${JS_FUNCS}"
echo -e "   API endpoints:    ${API_ENDPOINTS}"
echo ""
echo -e "${BOLD}🌙 LATE NIGHT STATS${RESET}"
echo -e "   After-hours commits (10pm-6am): ${BOLD}${LATE_NIGHT}${RESET} of ${TOTAL_COMMITS} (${LATE_PCT}%)"
EARLY_HOUR=$(git log --format="%ad" --date=format:"%H:%M" | sort | head -1)
LATE_HOUR=$(git log --format="%ad" --date=format:"%H:%M" | sort | tail -1)
echo -e "   Earliest commit: ${CYAN}${EARLY_HOUR}${RESET}"
echo -e "   Latest commit:   ${CYAN}${LATE_HOUR}${RESET}"
echo ""
echo -e "${BOLD}🔧 ON THE BENCH (uncommitted)${RESET}"
if [ "$UNCOMMITTED_ADD" -gt 0 ] || [ "$UNCOMMITTED_DEL" -gt 0 ]; then
  echo -e "   ${GREEN}+${UNCOMMITTED_ADD}${RESET} / ${RED}-${UNCOMMITTED_DEL}${RESET} lines across ${UNCOMMITTED_FILES} file(s)"
else
  echo -e "   ${DIM}Clean working tree — nothing pending${RESET}"
fi
echo ""
echo -e "${BOLD}🤖 PAIR PROGRAMMING (Claude Sessions)${RESET}"
echo -e "   Sessions:         ${CLAUDE_SESSIONS}"
echo -e "   Total dialogue:   ~${CLAUDE_TOTAL_MB}MB (~${CLAUDE_PAGES} pages)"
echo ""
echo -e "${GOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}⚾ ANNOUNCER'S BOOTH:${RESET}"
echo -e "   ${CYAN}\"${RANDOM_STAT}\"${RESET}"
echo -e "${GOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "${DIM}The Special K Report™ — because the scoreboard doesn't lie.${RESET}"
echo ""
