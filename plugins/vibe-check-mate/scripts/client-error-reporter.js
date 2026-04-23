/*! vibe-check-mate client error reporter — forwards window errors to the
 *  local receiver so .check-runtime/runtime.log captures both server and
 *  client errors uniformly.
 *
 *  Loads only on localhost / 127.0.0.1 / [::1].
 *  Config via window.__VIBE_CHECK_ENDPOINT__ (default http://localhost:9876).
 */
(() => {
  if (typeof window === 'undefined') return;
  const host = window.location?.hostname;
  if (host !== 'localhost' && host !== '127.0.0.1' && host !== '[::1]') return;

  const endpoint = window.__VIBE_CHECK_ENDPOINT__ || 'http://localhost:9876';

  const send = (kind, data) => {
    try {
      const body = JSON.stringify({
        kind,
        message: data?.message || (data ? String(data) : 'unknown'),
        stack: data?.stack || null,
        file: data?.filename || null,
        line: data?.lineno || null,
        col: data?.colno || null,
        url: window.location?.href,
        ts: Date.now(),
      });

      if (navigator.sendBeacon) {
        const blob = new Blob([body], { type: 'application/json' });
        navigator.sendBeacon(endpoint, blob);
        return;
      }
      fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body,
        keepalive: true,
      }).catch(() => {
        /* best-effort — swallow network error */
      });
    } catch {
      /* best-effort — swallow serialization error */
    }
  };

  window.addEventListener('error', (e) => {
    const err = e.error || e;
    send('error', {
      message: err.message || e.message,
      stack: err.stack,
      filename: e.filename,
      lineno: e.lineno,
      colno: e.colno,
    });
  });

  window.addEventListener('unhandledrejection', (e) => {
    const reason = e.reason;
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
