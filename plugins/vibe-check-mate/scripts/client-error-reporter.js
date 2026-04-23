/*! vibe-check-mate client error reporter — forwards window errors to the
 *  local receiver so .check-runtime/runtime.log captures both server and
 *  client errors uniformly.
 *
 *  Loads only on localhost / 127.0.0.1 / [::1].
 *  Config via window.__VIBE_CHECK_ENDPOINT__ (default http://localhost:9876).
 */
(function () {
  if (typeof window === 'undefined') return;
  var host = window.location && window.location.hostname;
  if (host !== 'localhost' && host !== '127.0.0.1' && host !== '[::1]') return;

  var endpoint = window.__VIBE_CHECK_ENDPOINT__ || 'http://localhost:9876';

  function send(kind, data) {
    try {
      var body = JSON.stringify({
        kind: kind,
        message: (data && (data.message || String(data))) || 'unknown',
        stack: (data && data.stack) || null,
        file: (data && data.filename) || null,
        line: (data && data.lineno) || null,
        col: (data && data.colno) || null,
        url: window.location && window.location.href,
        ts: Date.now(),
      });

      if (navigator.sendBeacon) {
        var blob = new Blob([body], { type: 'application/json' });
        navigator.sendBeacon(endpoint, blob);
        return;
      }
      fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body,
        keepalive: true,
      }).catch(function () {});
    } catch (_) {}
  }

  window.addEventListener('error', function (e) {
    var err = e.error || e;
    send('error', {
      message: err.message || e.message,
      stack: err.stack,
      filename: e.filename,
      lineno: e.lineno,
      colno: e.colno,
    });
  });

  window.addEventListener('unhandledrejection', function (e) {
    var reason = e.reason;
    if (reason && typeof reason === 'object') {
      send('unhandledrejection', {
        message: reason.message || String(reason),
        stack: reason.stack || null,
      });
    } else {
      send('unhandledrejection', { message: String(reason) });
    }
  });
})();
