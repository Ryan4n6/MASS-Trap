/* =================================================================
   M.A.S.S. TRAP — UNIFIED JAVASCRIPT v2.5.0
   Motion Analysis & Speed System
   Shared logic: Theme, WebSocket, API, Navigation
   ================================================================= */

// ====================================================================
// CONSTANTS (mirrors firmware config.h for UI-side consistency)
// ====================================================================
var MPS_TO_MPH = 2.23694;
var MPS_TO_KPH = 3.6;
var METERS_TO_FEET = 3.28084;
var MAX_RACE_DURATION_US = 60000000;  // 60s sanity check

// ====================================================================
// TOAST NOTIFICATIONS — slides in from top, auto-dismisses
// Types: 'success' (green), 'error' (red), 'info' (yellow), 'warn' (deep red)
// ====================================================================
function massToast(msg, type, duration) {
  type = type || 'success';
  duration = duration || 2500;
  var container = document.getElementById('toastContainer');
  if (!container) {
    container = document.createElement('div');
    container.className = 'mass-toast-container';
    container.id = 'toastContainer';
    document.body.appendChild(container);
  }
  var t = document.createElement('div');
  t.className = 'mass-toast ' + type;
  t.textContent = msg;
  container.appendChild(t);
  // Force reflow then animate in
  t.offsetHeight;
  t.classList.add('show');
  setTimeout(function() {
    t.classList.remove('show');
    setTimeout(function() { t.remove(); }, 300);
  }, duration);
}

// ====================================================================
// UNIT SYSTEM — "imperial" (mph, ft) or "metric" (km/h, m)
// Loaded from firmware config via WebSocket or /api/config
// ====================================================================
var massUnits = localStorage.getItem('mass_units') || 'imperial';

function setUnits(u) {
  massUnits = u;
  localStorage.setItem('mass_units', u);
}

// Speed: convert m/s to display unit
function formatSpeed(mps, decimals) {
  if (mps == null || isNaN(mps)) return '--';
  decimals = (decimals !== undefined) ? decimals : 1;
  if (massUnits === 'metric') return (mps * MPS_TO_KPH).toFixed(decimals);
  return (mps * MPS_TO_MPH).toFixed(decimals);
}

// Speed unit label
function speedUnit() {
  return massUnits === 'metric' ? 'km/h' : 'mph';
}

// Distance: always stored in meters, display in ft or m
function formatDistance(meters, decimals) {
  if (meters == null || isNaN(meters)) return '--';
  decimals = (decimals !== undefined) ? decimals : 2;
  if (massUnits === 'metric') return meters.toFixed(decimals);
  return (meters * METERS_TO_FEET).toFixed(decimals);
}

// Distance unit label
function distanceUnit() {
  return massUnits === 'metric' ? 'm' : 'ft';
}

// Distance input: display-unit value → meters (for saving to config)
function distanceToMeters(displayVal) {
  if (massUnits === 'metric') return displayVal;
  return displayVal / METERS_TO_FEET;  // ft → m
}

// Distance input: meters → display-unit value (for showing in form)
function metersToDisplay(meters) {
  if (massUnits === 'metric') return meters;
  return meters * METERS_TO_FEET;  // m → ft
}

// Convert mph value from WS to current unit (when mps not available)
function mphToDisplaySpeed(mph) {
  if (mph == null || isNaN(mph)) return '--';
  if (massUnits === 'metric') return (mph * 1.60934).toFixed(1);  // mph → km/h
  return mph.toFixed(1);
}

// ====================================================================
// THEME ENGINE
// ====================================================================
function getTheme() {
  return localStorage.getItem('mass_theme') || 'interceptor';
}

function setTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('mass_theme', theme);
  var sel = document.getElementById('themePicker');
  if (sel) sel.value = theme;
  // Theme-aware header branding
  var themeHeaders = {
    interceptor: { title: 'M.A.S.S. TRAP', subtitle: 'MOTION ANALYSIS & SPEED SYSTEM', tagline: 'COMMAND CENTER' },
    classic:     { title: 'SPEED LAB', subtitle: 'REAL-TIME RACE TIMING SYSTEM', tagline: '' },
    daytona:     { title: 'M.A.S.S. TRAP', subtitle: 'WORLD CENTER OF RACING', tagline: 'RACE CONTROL' },
    casefile:    { title: 'M.A.S.S. TRAP', subtitle: 'MOTION ANALYSIS & SPEED SYSTEM', tagline: 'COMMAND CENTER' },
    cyber:       { title: 'M.A.S.S. TRAP', subtitle: 'MOTION ANALYSIS & SPEED SYSTEM', tagline: 'COMMAND CENTER' }
  };
  var hdr = themeHeaders[theme] || themeHeaders.interceptor;
  var h1 = document.querySelector('.page-header h1');
  var sub = document.querySelector('.page-header .subtitle');
  var tag = document.querySelector('.page-header .tagline');
  if (h1) h1.textContent = hdr.title;
  if (sub) sub.textContent = hdr.subtitle;
  if (tag) { tag.textContent = hdr.tagline; tag.style.display = hdr.tagline ? '' : 'none'; }
  // Daytona: 76 ball version badge — show/hide + transform text
  var vBadge = document.querySelector('.version-badge');
  if (vBadge) {
    var hasFleetBar = !!document.getElementById('fleetBar');
    if (theme === 'daytona') {
      vBadge.style.display = '';
    } else if (hasFleetBar) {
      vBadge.style.display = 'none';
    }
    apply76Ball(vBadge);
  }
  // Dynamic theme-color for mobile browser chrome (address bar matches theme)
  var themeColors = {
    interceptor: '#1a1a2e', classic: '#1a1a1a', daytona: '#0d0d0d',
    casefile: '#f4f1eb', cyber: '#0a0a14'
  };
  var metaTC = document.querySelector('meta[name="theme-color"]');
  if (!metaTC) { metaTC = document.createElement('meta'); metaTC.name = 'theme-color'; document.head.appendChild(metaTC); }
  metaTC.content = themeColors[theme] || themeColors.interceptor;
}

function initTheme() {
  setTheme(getTheme());
}

// ====================================================================
// NAVIGATION — Mark active link based on current path
// ====================================================================
function initNav() {
  var path = window.location.pathname;
  var links = document.querySelectorAll('.mass-nav-list a');
  for (var i = 0; i < links.length; i++) {
    var href = links[i].getAttribute('href');
    if (href === path || (href === '/' && (path === '' || path === '/index.html' || path === '/dashboard.html'))) {
      links[i].classList.add('active');
    } else {
      links[i].classList.remove('active');
    }
  }
}

// ====================================================================
// WEBSOCKET CONNECTION (shared across dashboard + status pages)
// ====================================================================
var ws = null;
var wsReconnectTimer = null;
var wsConnected = false;
var wsMessageHandlers = [];
var wsReconnectAttempts = 0;

function connectWebSocket() {
  // Protocol-aware: use wss:// when loaded over HTTPS (e.g. Tailscale Funnel)
  // When behind a reverse proxy (Tailscale Funnel, nginx, etc.), the WS port
  // may differ from the ESP32's native :81. Use ?ws_port=N or auto-detect:
  //   - Local/LAN: ws://hostname:81
  //   - HTTPS proxy: wss://hostname:8443 (Funnel maps 8443→81)
  var proto = (location.protocol === 'https:') ? 'wss://' : 'ws://';
  var params = new URLSearchParams(window.location.search);
  var wsPort = params.get('ws_port') || (location.protocol === 'https:' ? '8443' : '81');
  var wsUrl = proto + window.location.hostname + ':' + wsPort;

  try {
    ws = new WebSocket(wsUrl);
  } catch (e) {
    console.error('[WS] Constructor failed:', e);
    wsReconnectAttempts++;
    updateConnectionBadge(false);
    wsReconnectTimer = setTimeout(connectWebSocket, 3000);
    return;
  }

  ws.onopen = function() {
    wsConnected = true;
    wsReconnectAttempts = 0;
    updateConnectionBadge(true);
    clearTimeout(wsReconnectTimer);
    console.log('[WS] Connected to ' + wsUrl);
  };

  ws.onclose = function(evt) {
    wsConnected = false;
    wsReconnectAttempts++;
    updateConnectionBadge(false);
    console.log('[WS] Closed (code=' + evt.code + ', reason=' + (evt.reason || 'none') + '). Reconnect #' + wsReconnectAttempts);
    wsReconnectTimer = setTimeout(connectWebSocket, Math.min(2000 * wsReconnectAttempts, 10000));
  };

  ws.onerror = function(evt) {
    console.error('[WS] Error on ' + wsUrl, evt);
  };

  ws.onmessage = function(event) {
    try {
      var data = JSON.parse(event.data);
      for (var i = 0; i < wsMessageHandlers.length; i++) {
        wsMessageHandlers[i](data);
      }
    } catch (e) {
      console.error('[WS] Parse error:', e);
    }
  };
}

function onWsMessage(handler) {
  wsMessageHandlers.push(handler);
}

function wsSend(data) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
  } else {
    alert('Not connected to M.A.S.S. Trap!');
  }
}

function updateConnectionBadge(connected) {
  var el = document.getElementById('connBadge');
  if (!el) return;
  var wasConnected = el.classList.contains('connected');
  el.className = 'conn-badge ' + (connected ? 'connected' : 'disconnected');
  if (connected) {
    el.textContent = 'LINKED';
  } else {
    el.textContent = wsReconnectAttempts > 1 ? 'OFFLINE (' + wsReconnectAttempts + ')' : 'OFFLINE';
  }
  // Dispatcher: announce connection changes (not initial load)
  if (wasConnected !== connected && _announceEl) {
    announce(connected ? 'Dispatch online. Link established.' : 'Signal lost. Reconnecting.');
  }
}

// ====================================================================
// API AUTHENTICATION HELPER
// ====================================================================
function getApiKey() {
  if (!window._apiKey) {
    window._apiKey = localStorage.getItem('mass_api_key') || '';
  }
  if (!window._apiKey) {
    window._apiKey = prompt('Enter API key (OTA password):') || '';
    if (window._apiKey) localStorage.setItem('mass_api_key', window._apiKey);
  }
  return window._apiKey;
}

function authHeaders(extra) {
  return Object.assign({ 'X-API-Key': getApiKey() }, extra || {});
}

// ====================================================================
// VERSION BADGE — with GitHub update check (24hr cache)
// ====================================================================
var GITHUB_API_LATEST = 'https://api.github.com/repos/Ryan4n6/MASS-Trap/releases/latest';
var GITHUB_RELEASES_URL = 'https://github.com/Ryan4n6/MASS-Trap/releases';
var UPDATE_CACHE_KEY = 'mass_update_cache';
var UPDATE_CACHE_TTL = 24 * 60 * 60 * 1000; // 24 hours in ms

function compareSemver(a, b) {
  // Returns: 1 if a > b, -1 if a < b, 0 if equal
  // Strips pre-release suffixes (-rc1, -beta2, etc.) before comparing
  var pa = String(a).replace(/^v/i, '').replace(/-.*$/, '').split('.').map(Number);
  var pb = String(b).replace(/^v/i, '').replace(/-.*$/, '').split('.').map(Number);
  for (var i = 0; i < 3; i++) {
    var va = pa[i] || 0;
    var vb = pb[i] || 0;
    if (va > vb) return 1;
    if (va < vb) return -1;
  }
  return 0;
}

function applyVersionBadge(badge, currentFw, releaseInfo) {
  if (!badge) return;
  if (releaseInfo && releaseInfo.tag_name) {
    var latest = releaseInfo.tag_name.replace(/^v/i, '');
    if (compareSemver(latest, currentFw) > 0) {
      // Update available — breathing red badge links to About page (update info shown there)
      badge.classList.add('update-available');
      badge.innerHTML = '<a href="/about.html" title="Update available! v' + latest + '">' +
        'v' + currentFw + ' → v' + latest + ' ⬆</a>';
      return;
    }
  }
  // Current or check failed — link to About page
  badge.classList.remove('update-available');
  badge.innerHTML = '<a href="/about.html" title="About M.A.S.S. Trap">' +
    'FW v' + currentFw + '</a>';
}

function checkGitHubRelease(forceRefresh) {
  // Check localStorage cache first (unless forced)
  if (!forceRefresh) {
    try {
      var cached = JSON.parse(localStorage.getItem(UPDATE_CACHE_KEY));
      if (cached && cached.ts && (Date.now() - cached.ts) < UPDATE_CACHE_TTL) {
        return Promise.resolve(cached.data);
      }
    } catch (e) { /* ignore parse errors */ }
  }

  // Fetch fresh from GitHub API
  return fetch(GITHUB_API_LATEST).then(function(r) {
    if (!r.ok) throw new Error('GitHub API ' + r.status);
    return r.json();
  }).then(function(data) {
    // Cache the result with timestamp
    try {
      localStorage.setItem(UPDATE_CACHE_KEY, JSON.stringify({ data: data, ts: Date.now() }));
    } catch (e) { /* localStorage full — ignore */ }
    return data;
  }).catch(function(err) {
    // Network error or rate limit — return cached data if available, else null
    try {
      var cached = JSON.parse(localStorage.getItem(UPDATE_CACHE_KEY));
      if (cached && cached.data) return cached.data;
    } catch (e) { /* ignore */ }
    return null;
  });
}

// Daytona 76 ball — transform version badge into an orange sphere
function apply76Ball(badge) {
  if (!badge) return;
  var theme = getTheme();
  var vLink = badge.querySelector('a');
  if (theme === 'daytona') {
    badge.title = 'Sunoco 76 \u2014 Turn 3';
    if (vLink) {
      var fullText = vLink.textContent.trim();
      if (!vLink.getAttribute('data-full-ver')) {
        vLink.setAttribute('data-full-ver', fullText);
      }
      // Extract just major.minor from "FW v2.6.0-beta" → "2.6"
      var match = fullText.match(/(\d+\.\d+)/);
      if (match) vLink.textContent = match[1];
    }
  } else {
    badge.title = '';
    if (vLink && vLink.getAttribute('data-full-ver')) {
      vLink.textContent = vLink.getAttribute('data-full-ver');
    }
  }
}

function loadVersion() {
  fetch('/api/version').then(function(r) { return r.json(); }).then(function(v) {
    var badge = document.getElementById('versionBadge');
    var currentFw = v.firmware || '0.0.0';

    // Start with basic version display immediately — links to About page
    if (badge) {
      badge.innerHTML = '<a href="/about.html" title="About M.A.S.S. Trap">' +
        'FW v' + currentFw + '</a>';
      // Daytona: Transform to 76 ball (short version text)
      apply76Ball(badge);
    }

    // Then check GitHub for updates (uses 24hr cache)
    checkGitHubRelease(false).then(function(releaseInfo) {
      applyVersionBadge(badge, currentFw, releaseInfo);
      // Re-apply 76 ball after update badge changes
      apply76Ball(badge);
    });
  }).catch(function() {
    var meta = document.querySelector('meta[name="fw-version"]');
    var badge = document.getElementById('versionBadge');
    if (meta && badge) badge.textContent = 'v' + meta.content;
  });
}

// ====================================================================
// UTILITY HELPERS
// ====================================================================

// Safe .toFixed() — crash-proof for non-numeric values (data validation)
function safeFixed(val, dec) {
  var n = parseFloat(val);
  return isNaN(n) ? '--' : n.toFixed(dec || 2);
}

// Kiosk mode check — used by hotkey guard and auth integration
function isKioskMode() {
  return document.body.classList.contains('kiosk');
}

function formatBytes(b) {
  if (!b) return '--';
  if (b > 1024 * 1024) return (b / 1024 / 1024).toFixed(1) + ' MB';
  if (b > 1024) return (b / 1024).toFixed(1) + ' KB';
  return b + ' B';
}

function formatUptime(s) {
  if (!s && s !== 0) return '--';
  var h = Math.floor(s / 3600);
  var m = Math.floor((s % 3600) / 60);
  var sec = s % 60;
  if (h > 0) return h + 'h ' + m + 'm ' + sec + 's';
  if (m > 0) return m + 'm ' + sec + 's';
  return sec + 's';
}

function escHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// ====================================================================
// NAV HTML SNIPPET GENERATOR
// Returns the <nav> HTML string to be inserted via JS or inline.
// Each page includes this and calls initNav() after DOM ready.
// ====================================================================
function getNavHTML() {
  return '<nav class="mass-nav"><ul class="mass-nav-list">' +
    '<li><a href="/"><span class="mass-nav-icon">&#x1F3C1;</span><span class="mass-nav-label">Live Monitor</span></a></li>' +
    '<li><a href="/history.html"><span class="mass-nav-icon">&#x1F4CB;</span><span class="mass-nav-label">Evidence Log</span></a></li>' +
    '<li><a href="/config"><span class="mass-nav-icon">&#x2699;&#xFE0F;</span><span class="mass-nav-label">System Config</span></a></li>' +
    '<li><a href="/console"><span class="mass-nav-icon">&#x1F50D;</span><span class="mass-nav-label">Diagnostics</span></a></li>' +
    '</ul></nav>';
}

// ====================================================================
// COMMON INIT — Call from each page's onload
// ====================================================================
function massInit(opts) {
  opts = opts || {};
  initTheme();
  initNav();
  loadVersion();
  initAnnouncer();
  initHotkeys();
  if (opts.ws !== false) connectWebSocket();
  initFleetBar();
}

// ====================================================================
// FLEET DISPATCH BAR — zsh-style persistent bottom status bar
// Shows: hostname │ ● Start ● Trap ● Telem │ drift | RSSI | heap | uptime | FW
// ====================================================================
var _fleetBarTimer = null;
var _fleetBarRole = '';    // This device's role (set on first poll)
var _fleetBarFw = '';      // Firmware version (set on first poll)

function initFleetBar() {
  // Don't double-init
  if (document.getElementById('fleetBar')) return;

  // Hide the old version badge — fleet bar replaces it
  // Exception: Daytona theme shows it as the 76 ball
  var oldBadge = document.getElementById('versionBadge');
  var curTheme = getTheme();
  if (oldBadge) oldBadge.style.display = (curTheme === 'daytona') ? '' : 'none';

  var bar = document.createElement('div');
  bar.id = 'fleetBar';
  bar.className = 'fleet-bar';
  bar.innerHTML =
    '<a class="fleet-bar-host" id="fbHost" href="/" title="Dashboard">--</a>' +
    '<span class="fleet-bar-sep">\u2502</span>' +
    '<a class="fleet-bar-roster" id="fbRoster" href="/console#fleet" title="Fleet Status"></a>' +
    '<span class="fleet-bar-sep">\u2502</span>' +
    '<span class="fleet-bar-metrics" id="fbMetrics">--</span>';
  document.body.appendChild(bar);

  // First poll immediately, then every 10s
  pollFleetBar();
  _fleetBarTimer = setInterval(pollFleetBar, 10000);
}

function pollFleetBar() {
  // Fetch /api/info and /api/peers in parallel
  var infoData = null;
  var peersData = null;
  var done = 0;

  function tryRender() {
    done++;
    if (done >= 2) updateFleetBar(infoData, peersData);
  }

  fetch('/api/info').then(function(r) { return r.json(); }).then(function(d) {
    infoData = d;
    tryRender();
  }).catch(function() { tryRender(); });

  fetch('/api/peers').then(function(r) { return r.json(); }).then(function(d) {
    peersData = d;
    tryRender();
  }).catch(function() { tryRender(); });
}

function updateFleetBar(info, peers) {
  // Host section
  var hostEl = document.getElementById('fbHost');
  var rosterEl = document.getElementById('fbRoster');
  var metricsEl = document.getElementById('fbMetrics');
  if (!hostEl) return;

  if (info) {
    _fleetBarRole = (info.role || '').toLowerCase();
    _fleetBarFw = info.firmware || '';
    hostEl.textContent = info.hostname || 'unknown';
  }

  // Roster section — always show all 4 fleet roles in track flow order
  // Dedup peers: keep only the BEST status per role (online > stale > offline)
  // Show grayed "unknown" placeholder for roles not yet discovered
  if (peers && Array.isArray(peers)) {
    var statusRank = { online: 0, stale: 1, offline: 2 };
    var allRoles = ['start', 'speedtrap', 'finish', 'telemetry'];
    var roleLabel = { start: 'Start', speedtrap: 'Trap', finish: 'Finish', telemetry: 'Telem' };

    // Dedup: group by role, keep best status per role
    var bestByRole = {};
    for (var i = 0; i < peers.length; i++) {
      var p = peers[i];
      var role = p.role || 'unknown';
      var st = (p.status || 'offline').toLowerCase();
      var rank = statusRank[st] !== undefined ? statusRank[st] : 9;
      if (!bestByRole[role] || rank < bestByRole[role]._rank) {
        p._rank = rank;
        bestByRole[role] = p;
      }
    }

    // Render all 4 roles — skip our own role (we ARE that node)
    var html = '';
    for (var r = 0; r < allRoles.length; r++) {
      var role = allRoles[r];
      if (role === _fleetBarRole) continue;  // don't show self
      var label = roleLabel[role];
      var p = bestByRole[role];
      if (p) {
        var status = (p.status || 'offline').toLowerCase();
        var host = p.hostname || '';
        html += '<span class="fb-peer ' + status + '" title="' + host + '">' +
          '\u25CF ' + label + '</span>';
      } else {
        html += '<span class="fb-peer unknown" title="Not discovered">' +
          '\u25CF ' + label + '</span>';
      }
    }
    rosterEl.innerHTML = html;
  }

  // Metrics section
  if (info) {
    var parts = [];

    // Clock sync status (finish gate only — it's the one doing sync)
    // offset != 0 means sync has happened. Show the actual value so user sees it change.
    if (_fleetBarRole === 'finish' && info.clock_offset_us !== undefined) {
      var offset = info.clock_offset_us;
      if (offset !== 0) {
        var absMs = Math.abs(offset / 1000);
        var driftLabel = absMs >= 1000 ? (absMs / 1000).toFixed(1) + 's' :
                         absMs >= 1 ? absMs.toFixed(0) + 'ms' :
                         Math.abs(offset).toFixed(0) + '\u00B5s';
        parts.push('<a class="fb-sync synced" href="/console" title="Clock sync active (' +
          (offset > 0 ? '+' : '') + (offset / 1000).toFixed(0) + 'ms offset)">' +
          '\u2705 ' + driftLabel + '</a>');
      } else {
        parts.push('<a class="fb-sync no-sync" href="/console" title="No clock sync yet \u2014 click SYNC on dashboard">' +
          '\u23F1 unsync\u2019d</a>');
      }
    }

    // WiFi RSSI
    var rssi = info.wifi_rssi || 0;
    var rssiClass = rssi > -50 ? 'fb-heap' : (rssi > -70 ? 'fb-rssi' : 'text-danger');
    parts.push('<span class="' + rssiClass + '">' + rssi + 'dBm</span>');

    // Free heap
    parts.push('<span class="fb-heap">' + formatBytes(info.free_heap) + '</span>');

    // Uptime
    parts.push('<span class="fb-uptime">' + formatUptime(info.uptime_s) + '</span>');

    // Firmware version — links to About page (replaces version badge)
    if (_fleetBarFw) {
      parts.push('<a class="fb-fw" href="/about.html" title="Firmware version">v' +
        _fleetBarFw + '</a>');
    }

    metricsEl.innerHTML = parts.join('<span class="fb-sep">|</span>');
  }
}

// ====================================================================
// DISPATCHER — Screen Reader Announcements ("Radio Comms")
// Tactical Police Dispatcher voice for aria-live announcements
// ====================================================================
var _announceEl = null;
var _lastAnnouncement = '';

function initAnnouncer() {
  if (_announceEl) return;
  _announceEl = document.createElement('div');
  _announceEl.id = 'massAnnouncer';
  _announceEl.className = 'sr-only';
  _announceEl.setAttribute('aria-live', 'assertive');
  _announceEl.setAttribute('aria-atomic', 'true');
  _announceEl.setAttribute('role', 'status');
  document.body.appendChild(_announceEl);
}

function announce(text, priority) {
  priority = priority || 'assertive';
  if (!_announceEl) initAnnouncer();
  _announceEl.setAttribute('aria-live', priority);
  _lastAnnouncement = text;
  // Clear then set after tick — forces screen readers to re-announce
  _announceEl.textContent = '';
  setTimeout(function() { _announceEl.textContent = text; }, 100);
}

// ====================================================================
// TACTICAL HOTKEYS — Keyboard shortcuts for blind users & excited kids
// Guard: only fire when not typing in a form field
// ====================================================================
function initHotkeys() {
  document.addEventListener('keydown', function(e) {
    // Skip if user is typing in a form field
    var tag = (document.activeElement || {}).tagName || '';
    if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;

    // Skip if modifier keys held (allow browser shortcuts)
    if (e.ctrlKey || e.metaKey || e.altKey) return;

    // Skip all hotkeys in kiosk mode (display-only)
    if (isKioskMode()) return;

    var key = e.key;

    // SPACE — Arm system (only on dashboard with armRace available)
    if (key === ' ' && typeof armRace === 'function') {
      e.preventDefault();
      armRace();
      return;
    }

    // R — Reset
    if ((key === 'r' || key === 'R') && typeof resetRace === 'function') {
      e.preventDefault();
      resetRace();
      announce('System reset. Standing by.');
      return;
    }

    // L — Loop (re-announce last message)
    if (key === 'l' || key === 'L') {
      e.preventDefault();
      if (_lastAnnouncement) {
        announce(_lastAnnouncement);
      } else {
        announce('No recent dispatch.');
      }
      return;
    }

    // G — Announce active car (dashboard-specific)
    if ((key === 'g' || key === 'G') && typeof activeCar !== 'undefined') {
      e.preventDefault();
      if (activeCar) {
        var stats = activeCar.stats || {};
        var best = (stats.bestTime != null && isFinite(stats.bestTime)) ? stats.bestTime.toFixed(3) + ' seconds' : 'no runs';
        announce('Active unit: ' + activeCar.name + '. ' +
          activeCar.weight + ' grams. ' +
          (stats.runs || 0) + ' runs. Best: ' + best + '.');
      } else {
        announce('No active unit. Select a vehicle from the garage.');
      }
      return;
    }

    // T — Announce last race time (dashboard-specific)
    if ((key === 't' || key === 'T') && typeof _lastRaceTime !== 'undefined') {
      e.preventDefault();
      if (_lastRaceTime) {
        announce('Last time: ' + _lastRaceTime + '.');
      } else {
        announce('No race data. Arm the system and run a vehicle.');
      }
      return;
    }

    // ? — Help (list hotkeys)
    if (key === '?') {
      e.preventDefault();
      announce('Hotkeys. Space to arm. R to reset. L to repeat. G for active car. T for last time. Question mark for help.');
      return;
    }
  });
}

// ====================================================================
// ARIA TABS — Reusable tab widget initialization (WAI-ARIA pattern)
// ====================================================================
function initAriaTabs(tablistSelector, tabSelector, panelPrefix) {
  var tablist = document.querySelector(tablistSelector);
  if (!tablist) return;
  tablist.setAttribute('role', 'tablist');

  var tabs = tablist.querySelectorAll(tabSelector);
  for (var i = 0; i < tabs.length; i++) {
    var tab = tabs[i];
    var panelId = tab.getAttribute('data-tab');
    if (!panelId) continue;

    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-controls', 'tab-' + panelId);
    if (!tab.id) tab.id = 'tabBtn-' + panelId;
    tab.setAttribute('aria-selected', tab.classList.contains('active') ? 'true' : 'false');
    tab.setAttribute('tabindex', tab.classList.contains('active') ? '0' : '-1');

    var panel = document.getElementById('tab-' + panelId);
    if (panel) {
      panel.setAttribute('role', 'tabpanel');
      panel.setAttribute('aria-labelledby', tab.id);
      panel.setAttribute('tabindex', '0');
    }
  }

  // Arrow key navigation within tablist
  tablist.addEventListener('keydown', function(e) {
    var current = document.activeElement;
    if (!current || current.getAttribute('role') !== 'tab') return;

    var allTabs = tablist.querySelectorAll(tabSelector);
    var idx = -1;
    for (var j = 0; j < allTabs.length; j++) {
      if (allTabs[j] === current) { idx = j; break; }
    }
    if (idx === -1) return;

    var newIdx = -1;
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
      newIdx = (idx + 1) % allTabs.length;
    } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
      newIdx = (idx - 1 + allTabs.length) % allTabs.length;
    } else if (e.key === 'Home') {
      newIdx = 0;
    } else if (e.key === 'End') {
      newIdx = allTabs.length - 1;
    }

    if (newIdx >= 0) {
      e.preventDefault();
      allTabs[newIdx].focus();
      allTabs[newIdx].click();
    }
  });
}

function updateAriaTabState(activeTab, tabSelector) {
  var tabs = document.querySelectorAll(tabSelector);
  for (var i = 0; i < tabs.length; i++) {
    var isActive = tabs[i] === activeTab;
    tabs[i].setAttribute('aria-selected', isActive ? 'true' : 'false');
    tabs[i].setAttribute('tabindex', isActive ? '0' : '-1');
  }
}

// ====================================================================
// AUTH GATE — Badge Reader (viewer) & Internal Affairs (admin)
// Creates full-screen overlay requiring password to dismiss.
// sessionStorage-based: persists across reloads, expires on tab close.
// ====================================================================
function checkAuthGate(tier, opts) {
  opts = opts || {};
  var sessionKey = tier === 'admin' ? 'mass_admin_auth' : 'mass_viewer_auth';
  var apiTier = tier === 'admin' ? 'admin' : 'viewer';

  // Already authenticated this session?
  if (sessionStorage.getItem(sessionKey) === 'true') return;

  fetch('/api/auth/info').then(function(r) { return r.json(); }).then(function(info) {
    var needed = tier === 'admin' ? info.hasAdminPassword : info.hasViewerPassword;
    if (!needed) return; // No password set — open access

    // Build overlay
    var overlay = document.createElement('div');
    overlay.id = 'authGate';
    overlay.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:#000;z-index:10000;display:flex;align-items:center;justify-content:center;';

    var isAdmin = tier === 'admin';
    var title = isAdmin ? 'INTERNAL AFFAIRS' : 'BADGE READER';
    var subtitle = isAdmin ? 'Administrative access required' : 'Scan your badge to proceed';
    var btnText = isAdmin ? 'Authenticate' : 'Scan Badge';
    var accentColor = isAdmin ? '#dc3545' : 'var(--accent, #d4af37)';

    var box = document.createElement('div');
    box.style.cssText = 'background:var(--bg-card,#16213e);border:2px solid ' + accentColor + ';border-radius:12px;padding:40px;text-align:center;max-width:360px;width:90%;';
    box.innerHTML =
      '<div style="font-size:2.5rem;margin-bottom:12px;">' + (isAdmin ? '&#x1F6E1;' : '&#x1F6E1;') + '</div>' +
      '<h2 style="color:' + accentColor + ';font-family:var(--font-body);letter-spacing:2px;margin:0 0 8px;">' + title + '</h2>' +
      '<p style="color:var(--text-muted,#888);font-size:0.85rem;margin:0 0 24px;">' + subtitle + '</p>' +
      '<input type="password" id="authGateInput" placeholder="Password" style="width:100%;padding:12px;border:1px solid var(--border,#2a2a4a);border-radius:6px;background:var(--bg-input,#0f0f1e);color:var(--text,#e0e0e0);font-size:1rem;margin-bottom:12px;text-align:center;font-family:var(--font-data);" autocomplete="current-password">' +
      '<div id="authGateError" style="color:var(--danger,#dc3545);font-size:0.85rem;margin-bottom:12px;min-height:1.2em;"></div>' +
      '<button id="authGateBtn" style="width:100%;padding:12px;background:' + accentColor + ';color:#000;border:none;border-radius:6px;font-weight:900;font-size:1rem;cursor:pointer;text-transform:uppercase;letter-spacing:1px;">' + btnText + '</button>';

    overlay.appendChild(box);
    document.body.appendChild(overlay);

    var input = document.getElementById('authGateInput');
    var errEl = document.getElementById('authGateError');
    var btn = document.getElementById('authGateBtn');

    function tryAuth() {
      var pw = input.value;
      btn.disabled = true;
      btn.textContent = 'Checking...';
      fetch('/api/auth/check', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: pw, tier: apiTier })
      }).then(function(r) { return r.json(); }).then(function(result) {
        if (result.ok) {
          sessionStorage.setItem(sessionKey, 'true');
          overlay.remove();
          if (typeof announce === 'function') {
            announce(isAdmin ? 'Internal Affairs clearance granted.' : 'Badge accepted. Access granted.');
          }
          if (typeof opts.onSuccess === 'function') opts.onSuccess();
        } else {
          errEl.textContent = 'ACCESS DENIED';
          input.value = '';
          input.focus();
          box.style.animation = 'none';
          void box.offsetWidth; // Reflow
          box.style.animation = 'shake 0.4s ease';
        }
        btn.disabled = false;
        btn.textContent = btnText;
      }).catch(function() {
        errEl.textContent = 'Connection error';
        btn.disabled = false;
        btn.textContent = btnText;
      });
    }

    btn.onclick = tryAuth;
    input.onkeydown = function(e) { if (e.key === 'Enter') tryAuth(); };
    setTimeout(function() { input.focus(); }, 100);

    // Add shake animation CSS if not present
    if (!document.getElementById('authShakeCSS')) {
      var style = document.createElement('style');
      style.id = 'authShakeCSS';
      style.textContent = '@keyframes shake{0%,100%{transform:translateX(0)}25%{transform:translateX(-8px)}75%{transform:translateX(8px)}}';
      document.head.appendChild(style);
    }
  }).catch(function(e) {
    console.log('[AUTH] Could not fetch auth info, proceeding without gate:', e);
  });
}
