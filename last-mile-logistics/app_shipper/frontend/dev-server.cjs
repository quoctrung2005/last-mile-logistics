"use strict";

// Local static server + same-origin API proxy. No dependency, no token/body logging.
const http = require("node:http");
const https = require("node:https");
const fs = require("node:fs");
const path = require("node:path");
const root = __dirname;
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon" };
function fail(response, status, message) {
  if (response.headersSent) { response.destroy(); return; }
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify({ message }));
}
function createServer(backend = new URL(process.env.LASTMILE_API_URL || "http://localhost:5038")) {
  if (!["http:", "https:"].includes(backend.protocol) || backend.username || backend.password) throw new Error("LASTMILE_API_URL phải là HTTP(S), không chứa thông tin đăng nhập.");
  return http.createServer((request, response) => {
  let url;
  try { url = new URL(request.url, "http://localhost"); } catch (_) { fail(response, 400, "URL không hợp lệ."); return; }
  if (url.pathname.startsWith("/api/")) {
    const target = new URL(url.pathname + url.search, backend);
    const transport = backend.protocol === "https:" ? https : http;
    const headers = { ...request.headers, host: backend.host };
    delete headers.connection;
    const upstream = transport.request(target, { method: request.method, headers }, result => {
      // Never expose an upstream redirect to fetch: it can cross origin and strip Authorization.
      if (result.statusCode >= 300 && result.statusCode < 400) {
        result.resume();
        fail(response, 502, "Backend chuyển hướng API. Hãy đặt LASTMILE_API_URL tới URL đích trực tiếp; HTTPS cần chứng chỉ được tin cậy.");
        return;
      }
      response.writeHead(result.statusCode, result.headers); result.pipe(response);
      result.on("error", () => response.destroy());
    });
    upstream.setTimeout(18000, () => upstream.destroy());
    upstream.on("error", () => fail(response, 502, "Không thể kết nối backend. Hãy khởi chạy API hoặc kiểm tra LASTMILE_API_URL."));
    request.on("aborted", () => upstream.destroy());
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
