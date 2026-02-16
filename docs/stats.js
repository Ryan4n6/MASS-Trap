/**
 * M.A.S.S. Trap — Stats Loader (The Special K Report Engine)
 *
 * Fetches docs/stats.json once, then auto-populates any element on the page
 * that has a `data-stat` attribute. Uses dot notation for nested values.
 *
 * Usage in HTML:
 *   <span data-stat="codebase.total_lines"></span>           → "35,173"
 *   <span data-stat="git.total_commits"></span>              → "46"
 *   <span data-stat="economics.cocomo_cost_usd" data-stat-prefix="$"></span>  → "$806,902"
 *   <span data-stat="firmware.version"></span>               → "2.6.0-beta"
 *   <span data-stat="fun_facts" data-stat-random="true"></span>  → random fun fact
 *   <span data-stat="ai_collaboration.session_total_mb" data-stat-suffix="MB"></span>
 *
 * Attributes:
 *   data-stat="dotted.path"        — path into stats.json
 *   data-stat-prefix="$"           — prepend string
 *   data-stat-suffix=" lines"      — append string
 *   data-stat-format="number"      — apply thousands separator (default for numbers)
 *   data-stat-format="raw"         — no formatting
 *   data-stat-random="true"        — pick random element from array
 *   data-stat-fallback="N/A"       — show if value not found
 *
 * Include once per page:
 *   <script src="stats.js" defer></script>
 *
 * That's it. Stats populate on DOMContentLoaded. Zero config.
 * If it wasn't documented, it didn't happen. — Agent J
 */
(function() {
  'use strict';

  var STATS_URL = 'stats.json';
  var CACHE_KEY = 'mass_stats_cache';
  var CACHE_TTL = 300000; // 5 minutes

  function resolve(obj, path) {
    if (!obj || !path) return undefined;
    var parts = path.split('.');
    var val = obj;
    for (var i = 0; i < parts.length; i++) {
      if (val === undefined || val === null) return undefined;
      val = val[parts[i]];
    }
    return val;
  }

  function formatNumber(n) {
    if (typeof n !== 'number') return String(n);
    if (n !== Math.floor(n)) return n.toLocaleString(undefined, {maximumFractionDigits: 1});
    return n.toLocaleString();
  }

  function populate(stats) {
    var els = document.querySelectorAll('[data-stat]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var path = el.getAttribute('data-stat');
      var val = resolve(stats, path);

      if (val === undefined) {
        el.textContent = el.getAttribute('data-stat-fallback') || '';
        continue;
      }

      // Array: pick random if requested, otherwise show length
      if (Array.isArray(val)) {
        if (el.getAttribute('data-stat-random') === 'true') {
          val = val[Math.floor(Math.random() * val.length)];
        } else {
          val = val.length;
        }
      }

      // Format
      var fmt = el.getAttribute('data-stat-format') || (typeof val === 'number' ? 'number' : 'raw');
      var display = (fmt === 'number') ? formatNumber(val) : String(val);

      // Prefix / suffix
      var prefix = el.getAttribute('data-stat-prefix') || '';
      var suffix = el.getAttribute('data-stat-suffix') || '';

      el.textContent = prefix + display + suffix;

      // Add a title tooltip with the raw value for nerds
      if (typeof val === 'number' && val > 999) {
        el.title = val.toString();
      }
    }

    // Dispatch event so other scripts can hook in
    window.dispatchEvent(new CustomEvent('mass-stats-loaded', { detail: stats }));
  }

  function loadStats() {
    // Try cache first
    try {
      var cached = sessionStorage.getItem(CACHE_KEY);
      if (cached) {
        var parsed = JSON.parse(cached);
        if (parsed._ts && (Date.now() - parsed._ts) < CACHE_TTL) {
          populate(parsed.data);
          return;
        }
      }
    } catch(e) {}

    // Fetch fresh
    var xhr = new XMLHttpRequest();
    xhr.open('GET', STATS_URL, true);
    xhr.onload = function() {
      if (xhr.status === 200) {
        try {
          var stats = JSON.parse(xhr.responseText);
          populate(stats);
          // Cache it
          try {
            sessionStorage.setItem(CACHE_KEY, JSON.stringify({ _ts: Date.now(), data: stats }));
          } catch(e) {}
        } catch(e) {
          // JSON parse failed, try as-is
        }
      }
    };
    xhr.onerror = function() {
      // Silently fail — page still works, just no dynamic stats
    };
    xhr.send();
  }

  // Also expose globally so other scripts can access stats
  window.MASS_STATS = null;
  window.addEventListener('mass-stats-loaded', function(e) {
    window.MASS_STATS = e.detail;
  });

  // Auto-load on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', loadStats);
  } else {
    loadStats();
  }
})();
