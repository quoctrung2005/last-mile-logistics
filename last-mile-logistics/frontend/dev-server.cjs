"use strict";

// Local static server + same-origin API proxy. No dependency, no token/body logging.
const http = require("node:http");
const https = require("node:https");
const fs = require("node:fs");
const path = require("node:path");
const root = __dirname;
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon" };
function fail(response, status, message, details = {}) {
  if (response.destroyed || response.writableEnded || response.socket?.destroyed) return;
  if (response.headersSent) { response.destroy(); return; }
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify({ message, ...details }));
}
// These POSTs use dispatch.js's 60s deadline, including response body download.
// Give the proxy 10s extra so the browser controls cancellation first.
function isPlanningRequest(method, pathname) {
  return method === "POST" && (/^\/api\/v1\/dispatch\/plans\/?$/i.test(pathname)
    || /^\/api\/v1\/dispatch\/plans\/[^/]+\/confirm\/?$/i.test(pathname)
    || /^\/api\/v1\/trips\/\d+\/optimize\/?$/i.test(pathname));
}
function createServer(backend = new URL(process.env.LASTMILE_API_URL || "http://localhost:5038"),
  { timeoutMs = 18000, planningTimeoutMs = 70000 } = {}) {
  if (!["http:", "https:"].includes(backend.protocol) || backend.username || backend.password) throw new Error("LASTMILE_API_URL phải là HTTP(S), không chứa thông tin đăng nhập.");
  if (![timeoutMs, planningTimeoutMs].every(value => Number.isFinite(value) && value > 0)) throw new RangeError("Thời gian chờ proxy phải là số dương hữu hạn.");
  return http.createServer((request, response) => {
  let url;
  try { url = new URL(request.url, "http://localhost"); } catch (_) { fail(response, 400, "URL không hợp lệ."); return; }
  if (url.pathname.startsWith("/api/")) {
    const target = new URL(url.pathname + url.search, backend);
    const transport = backend.protocol === "https:" ? https : http;
    const headers = { ...request.headers, host: backend.host };
    delete headers.connection;
    const writing = !["GET", "HEAD", "OPTIONS"].includes(request.method);
    let incoming, socket, timer, settled = false, connected = false;
    const onConnect = () => { connected = true; };
    const cleanup = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      request.unpipe(upstream);
      request.removeListener("aborted", cancel);
      response.removeListener("finish", finished);
      response.removeListener("close", closed);
      socket?.removeListener("connect", onConnect);
      incoming?.unpipe(response);
      // Keep error handlers attached: destroy/connection resets can deliver
      // asynchronous errors after cleanup. Their settled guard makes them no-ops.
    };
    const stopUpstream = () => {
      incoming?.destroy();
      upstream.destroy();
      socket?.destroy();
    };
    const cancel = () => {
      if (settled) return;
      cleanup(); stopUpstream(); response.destroy();
      // Closing HTTP transport does not undo a backend transaction already committed.
    };
    const finished = () => {
      if (settled) return;
      cleanup();
      // A fully delivered response is not a client cancellation. With agent:false,
      // a completed backend exchange closes its own connection normally.
      // Early backend responses may still leave an unfinished upload to stop.
      if (!incoming?.complete || !upstream.writableFinished) stopUpstream();
    };
    const closed = () => {
      if (response.writableFinished) finished();
      else cancel();
    };
    const reject = (status, message, code) => {
      if (settled) return;
      if (response.destroyed || response.writableEnded || response.socket?.destroyed || response.headersSent) { cancel(); return; }
      // A failed write may already have committed. Never replay it.
      const resultUnknown = writing && connected;
      if (resultUnknown) message += " Chưa xác định được kết quả thao tác. Hãy tải lại dữ liệu để kiểm tra trước khi gửi lại.";
      cleanup(); stopUpstream();
      fail(response, status, message, { code, resultUnknown });
    };
    const timedOut = () => reject(504, connected
      ? "Backend xử lý yêu cầu quá thời gian chờ của proxy."
      : "Quá thời gian chờ kết nối backend. Hãy kiểm tra địa chỉ API và kết nối mạng.", "UPSTREAM_TIMEOUT");
    // Own this connection: cleanup must never close a socket reused by another request.
    const upstream = transport.request(target, { method: request.method, headers, agent: false }, result => {
      incoming = result;
      result.on("error", () => reject(502, "Kết nối backend bị gián đoạn khi đọc phản hồi.", "UPSTREAM_RESPONSE_ERROR"));
      result.on("aborted", () => reject(502, "Kết nối backend bị gián đoạn khi đọc phản hồi.", "UPSTREAM_RESPONSE_ERROR"));
      if (settled || response.destroyed || response.writableEnded || response.socket?.destroyed) {
        result.destroy(); cancel(); return;
      }
      // Never expose an upstream redirect to fetch: it can cross origin and strip Authorization.
      if (result.statusCode >= 300 && result.statusCode < 400) {
        reject(502, "Backend chuyển hướng API. Hãy đặt LASTMILE_API_URL tới URL đích trực tiếp; HTTPS cần chứng chỉ được tin cậy.", "UPSTREAM_REDIRECT");
        return;
      }
      response.writeHead(result.statusCode, result.headers); result.pipe(response);
    });
    upstream.on("socket", value => {
      socket = value;
      if (settled) { value.destroy(); return; }
      if (value.connecting) value.once("connect", onConnect);
      else onConnect();
    });
    upstream.on("error", error => {
      if (error.code === "ETIMEDOUT") { timedOut(); return; }
      reject(502, connected ? "Kết nối backend bị gián đoạn khi xử lý yêu cầu."
        : "Không thể kết nối backend. Hãy khởi chạy API hoặc kiểm tra LASTMILE_API_URL.",
      connected ? "UPSTREAM_CONNECTION_LOST" : "UPSTREAM_UNAVAILABLE");
    });
    // An absolute deadline also bounds DNS/connect and slowly streamed bodies.
    timer = setTimeout(timedOut, isPlanningRequest(request.method, url.pathname) ? planningTimeoutMs : timeoutMs);
    request.on("aborted", cancel);
    request.on("error", cancel);
    response.on("finish", finished);
    // IncomingMessage 'aborted' covers incomplete uploads only. ServerResponse
    // 'close' also covers a browser leaving after upload or during the download.
    response.on("close", closed);
    response.on("error", cancel);
    request.pipe(upstream); return;
  }
  if (!["GET", "HEAD"].includes(request.method)) { fail(response, 405, "Phương thức không được hỗ trợ."); return; }
  let name;
  try { name = decodeURIComponent(url.pathname); } catch (_) { fail(response, 400, "URL không hợp lệ."); return; }
  const file = path.resolve(root, "." + (name === "/" ? "/index.html" : name));
  const relative = path.relative(root, file);
  const type = types[path.extname(file).toLowerCase()];
  if (relative.startsWith("..") || path.isAbsolute(relative) || !type || relative.split(/[\\/]/).some(part => part.startsWith("."))) {
    fail(response, 404, "Không tìm thấy file."); return;
  }
  fs.stat(file, (error, stat) => {
    if (error || !stat.isFile()) { fail(response, 404, "Không tìm thấy file."); return; }
    response.writeHead(200, { "Content-Type": type, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" });
    if (request.method === "HEAD") { response.end(); return; }
    const stream = fs.createReadStream(file); stream.on("error", () => response.destroy()); stream.pipe(response);
  });
  });
}

if (require.main === module) {
  const server = createServer();
  server.listen(Number(process.env.FRONTEND_PORT || 5500), "127.0.0.1", () => console.log("Frontend local: http://localhost:" + server.address().port));
}
module.exports = { createServer };
