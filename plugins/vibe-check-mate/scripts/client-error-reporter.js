/*! vibe-check-mate client runtime reporter — forwards window errors and
 *  network evidence to the local receiver so .check-runtime/runtime.log
 *  captures server, client, and API failure context uniformly.
 *
 *  Loads only on localhost / 127.0.0.1 / [::1].
 *  Config via window.__VIBE_CHECK_ENDPOINT__ or client-error-endpoint.json
 *  next to this script (default http://localhost:9876).
 */
(() => {
  if (typeof window === "undefined") return;
  const host = window.location?.hostname;
  if (host !== "localhost" && host !== "127.0.0.1" && host !== "[::1]") return;

  let endpoint = window.__VIBE_CHECK_ENDPOINT__ || "http://localhost:9876";
  const nativeFetch = typeof window.fetch === "function" ? window.fetch.bind(window) : null;
  const scriptSrc = document.currentScript?.src || "/client-error-reporter.js";
  const endpointConfigUrl = new URL("client-error-endpoint.json", scriptSrc).href;
  const endpointReady =
    window.__VIBE_CHECK_ENDPOINT__ || !nativeFetch
      ? Promise.resolve()
      : nativeFetch(`${endpointConfigUrl}?t=${Date.now()}`, { cache: "no-store" })
          .then((response) => (response.ok ? response.json() : null))
          .then((config) => {
            if (config?.endpoint) endpoint = String(config.endpoint);
          })
          .catch(() => {
            /* best-effort — fall back to default endpoint */
          });
  const slowMs = Number(window.__VIBE_NETWORK_SLOW_MS__ || 1000);
  const maxBodyChars = Number(window.__VIBE_NETWORK_MAX_BODY_CHARS__ || 4000);
  const sensitiveKeyPattern =
    /(authorization|cookie|set-cookie|token|access_token|refresh_token|id_token|jwt|secret|password|passwd|api[-_]?key|apikey|credential|session|csrf|xsrf)/i;

  const redactString = (value) => {
    if (value == null) return value;
    let text = String(value);
    text = text.replace(/(Bearer\s+)[A-Za-z0-9._~+/=-]+/gi, "$1[REDACTED]");
    text = text.replace(/([?&][^=]*(?:token|secret|password|api[-_]?key|session|csrf|xsrf)[^=]*=)[^&\s]+/gi, "$1[REDACTED]");
    text = text.replace(/((?:token|secret|password|api[-_]?key|session|csrf|xsrf)["']?\s*[:=]\s*["']?)[^"'&\s,}]+/gi, "$1[REDACTED]");
    if (text.length > maxBodyChars) {
      return `${text.slice(0, maxBodyChars)}...[TRUNCATED ${text.length - maxBodyChars} chars]`;
    }
    return text;
  };

  const redactValue = (value, key = "") => {
    if (sensitiveKeyPattern.test(key)) return "[REDACTED]";
    if (value == null) return value;
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
      return redactString(value);
    }
    if (Array.isArray(value)) return value.map((item) => redactValue(item, key));
    if (typeof value === "object") {
      const output = {};
      for (const [childKey, childValue] of Object.entries(value)) {
        output[childKey] = redactValue(childValue, childKey);
      }
      return output;
    }
    return redactString(value);
  };

  const serializeBody = (body) => {
    try {
      if (body == null) return null;
      if (typeof body === "string") return redactString(body);
      if (body instanceof URLSearchParams) return redactString(body.toString());
      if (body instanceof FormData) {
        const fields = {};
        for (const [key, value] of body.entries()) {
          fields[key] = value instanceof File ? `[File name=${value.name} size=${value.size}]` : redactValue(value, key);
        }
        return JSON.stringify(fields);
      }
      if (body instanceof Blob) return `[Blob type=${body.type || "unknown"} size=${body.size}]`;
      if (body instanceof ArrayBuffer) return `[ArrayBuffer byteLength=${body.byteLength}]`;
      if (ArrayBuffer.isView(body)) return `[TypedArray byteLength=${body.byteLength}]`;
      return redactValue(body);
    } catch {
      return "[Unserializable body]";
    }
  };

  const headersToObject = (headers) => {
    const output = {};
    try {
      if (!headers) return output;
      const normalized = new Headers(headers);
      for (const [key, value] of normalized.entries()) {
        output[key] = redactValue(value, key);
      }
    } catch {
      /* best-effort — ignore malformed headers */
    }
    return output;
  };

  const send = (kind, data) => {
    try {
      const body = JSON.stringify({
        kind,
        message: data?.message || (data ? String(data) : "unknown"),
        stack: data?.stack || null,
        file: data?.filename || null,
        line: data?.lineno || null,
        col: data?.colno || null,
        url: window.location?.href,
        ts: Date.now(),
        network: data?.network || null,
      });

      endpointReady.then(() => {
        if (navigator.sendBeacon) {
          const blob = new Blob([body], { type: "application/json" });
          navigator.sendBeacon(endpoint, blob);
          return;
        }
        if (!nativeFetch) return;
        nativeFetch(endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body,
          keepalive: true,
        }).catch(() => {
          /* best-effort — swallow network error */
        });
      });
    } catch {
      /* best-effort — swallow serialization error */
    }
  };

  const shouldReportNetwork = (status, duration, failed) => failed || status >= 400 || duration >= slowMs;

  const reportNetwork = (network) => {
    send(network.failed ? "network-error" : "network", { message: network.message || "network event", network });
  };

  const originalFetch = window.fetch;
  if (typeof originalFetch === "function") {
    window.fetch = async (...args) => {
      const startedAt = Date.now();
      const input = args[0];
      const init = args[1] || {};
      const request = input instanceof Request ? input : null;
      const method = (init.method || request?.method || "GET").toUpperCase();
      const url = redactString(request?.url || String(input));
      const requestBody = serializeBody(init.body ?? null);
      const requestHeaders = headersToObject(init.headers || request?.headers);

      try {
        const response = await originalFetch.apply(window, args);
        const duration = Date.now() - startedAt;
        if (shouldReportNetwork(response.status, duration, false)) {
          reportNetwork({
            transport: "fetch",
            method,
            url,
            status: response.status,
            ok: response.ok,
            duration_ms: duration,
            request_headers: requestHeaders,
            request_body: requestBody,
            response_type: response.type,
            page_url: window.location?.href,
          });
        }
        return response;
      } catch (error) {
        const duration = Date.now() - startedAt;
        reportNetwork({
          transport: "fetch",
          method,
          url,
          status: 0,
          ok: false,
          failed: true,
          duration_ms: duration,
          request_headers: requestHeaders,
          request_body: requestBody,
          message: error?.message || String(error),
          page_url: window.location?.href,
        });
        throw error;
      }
    };
  }

  const OriginalXHR = window.XMLHttpRequest;
  if (typeof OriginalXHR === "function") {
    window.XMLHttpRequest = function XMLHttpRequestWithVibeCheck() {
      const xhr = new OriginalXHR();
      const meta = {
        method: "GET",
        url: "",
        request_headers: {},
        request_body: null,
        started_at: 0,
      };

      const originalOpen = xhr.open;
      xhr.open = function open(method, url, ...rest) {
        meta.method = String(method || "GET").toUpperCase();
        meta.url = redactString(url || "");
        return originalOpen.call(xhr, method, url, ...rest);
      };

      const originalSetRequestHeader = xhr.setRequestHeader;
      xhr.setRequestHeader = function setRequestHeader(key, value) {
        meta.request_headers[key] = redactValue(value, key);
        return originalSetRequestHeader.call(xhr, key, value);
      };

      const originalSend = xhr.send;
      xhr.send = function sendXhr(body) {
        meta.started_at = Date.now();
        meta.request_body = serializeBody(body);
        return originalSend.call(xhr, body);
      };

      const finalize = (failed, message) => {
        const duration = meta.started_at ? Date.now() - meta.started_at : 0;
        const status = xhr.status || 0;
        if (shouldReportNetwork(status, duration, failed)) {
          reportNetwork({
            transport: "xhr",
            method: meta.method,
            url: meta.url,
            status,
            ok: status >= 200 && status < 400,
            failed,
            duration_ms: duration,
            request_headers: meta.request_headers,
            request_body: meta.request_body,
            message,
            page_url: window.location?.href,
          });
        }
      };

      xhr.addEventListener("loadend", () => finalize(false, "xhr completed"));
      xhr.addEventListener("error", () => finalize(true, "xhr network error"));
      xhr.addEventListener("timeout", () => finalize(true, "xhr timeout"));
      xhr.addEventListener("abort", () => finalize(true, "xhr aborted"));

      return xhr;
    };
  }

  window.addEventListener("error", (e) => {
    const err = e.error || e;
    send("error", {
      message: err.message || e.message,
      stack: err.stack,
      filename: e.filename,
      lineno: e.lineno,
      colno: e.colno,
    });
  });

  window.addEventListener("unhandledrejection", (e) => {
    const reason = e.reason;
    if (reason && typeof reason === "object") {
      send("unhandledrejection", {
        message: reason.message || String(reason),
        stack: reason.stack || null,
      });
    } else {
      send("unhandledrejection", { message: String(reason) });
    }
  });
})();
