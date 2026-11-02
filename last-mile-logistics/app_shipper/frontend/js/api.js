"use strict";

(function () {
  const SESSION_KEY = "tvd.session";
  const LEGACY_ACCESS_KEY = "tvd.accessToken";
  const LEGACY_REFRESH_KEY = "tvd.refreshToken";
  let refreshRequest = null;
  let sessionGeneration = 0;

  function tokenText(value, access) {
    if (typeof value !== "string") return null;
    const token = value.trim().replace(/^(?:Bearer\s+)+/i, "");
    const pattern = access ? /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/ : /^[A-Za-z0-9_-]{43}$/;
    return pattern.test(token) ? token : null;
  }

  function jwtExpiry(token) {
    try {
      const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
      return Number.isFinite(payload.exp) ? payload.exp * 1000 : null;
    } catch (_) { return null; }
  }

  function getSession() {
    try {
      const saved = sessionStorage.getItem(SESSION_KEY);
      if (saved) {
        const session = JSON.parse(saved);
        return session && tokenText(session.accessToken, true) && tokenText(session.refreshToken, false)
          ? { ...session, accessToken: tokenText(session.accessToken, true), refreshToken: tokenText(session.refreshToken, false) } : null;
      }
      // Migrate existing tabs once; all subsequent reads/writes use one atomic record.
      const accessToken = tokenText(sessionStorage.getItem(LEGACY_ACCESS_KEY), true);
      const refreshToken = tokenText(sessionStorage.getItem(LEGACY_REFRESH_KEY), false);
      if (!accessToken || !refreshToken) return null;
      const expiry = jwtExpiry(accessToken);
      const session = { accessToken, refreshToken, expiresAt: expiry ? new Date(expiry).toISOString() : null, user: null };
      sessionStorage.setItem(SESSION_KEY, JSON.stringify(session));
      sessionStorage.removeItem(LEGACY_ACCESS_KEY);
      sessionStorage.removeItem(LEGACY_REFRESH_KEY);
      return session;
    } catch (_) { return null; }
  }

  function getAccessToken() { return getSession()?.accessToken || null; }
  function getRefreshToken() { return getSession()?.refreshToken || null; }

  function saveSession(tokens) {
    const accessToken = tokenText(tokens?.accessToken, true);
    const refreshToken = tokenText(tokens?.refreshToken, false);
    // AuthTokenService emits UTC ISO with Z. Require an explicit timezone, never add hours manually.
    const expiry = typeof tokens?.expiresAt === "string" && /(?:Z|[+-]\d{2}:\d{2})$/i.test(tokens.expiresAt)
      ? Date.parse(tokens.expiresAt) : NaN;
    const user = tokens?.user;
    if (!accessToken || !refreshToken || !Number.isFinite(expiry) || !user || Array.isArray(user)
      || !Number.isSafeInteger(Number(user.accountId)) || Number(user.accountId) <= 0
      || typeof user.username !== "string" || typeof user.role !== "string") {
      throw new Error("Phản hồi xác thực không có token, thời hạn hoặc tài khoản hợp lệ.");
    }
    sessionStorage.setItem(SESSION_KEY, JSON.stringify({ accessToken, refreshToken, expiresAt: new Date(expiry).toISOString(), user }));
    sessionStorage.removeItem(LEGACY_ACCESS_KEY);
    sessionStorage.removeItem(LEGACY_REFRESH_KEY);
  }

  function storeTokens(tokens) {
    saveSession(tokens);
    sessionGeneration += 1;
  }

  function clearTokens() {
    sessionGeneration += 1;
    sessionStorage.removeItem(SESSION_KEY);
    sessionStorage.removeItem(LEGACY_ACCESS_KEY);
    sessionStorage.removeItem(LEGACY_REFRESH_KEY);
  }

  async function readResponse(response) {
    const body = await response.text();
    if (!body) return null;
    try { return JSON.parse(body); } catch (_) { return body; }
  }

  async function request(path, options, allowRefresh) {
    const settings = options || {};
    const generation = sessionGeneration;
    const authRoute = /^\/api\/v1\/auth\/(login|refresh|logout)\/?(?:\?|$)/.test(path);
    const authenticated = settings.authenticated !== false && !authRoute;
    const sentToken = authenticated ? getAccessToken() : null;
    const url = window.APP_CONFIG.API_BASE_URL + path;
    const headers = new Headers(settings.headers || {});
    headers.set("Accept", "application/json");

    if (settings.body && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }
    headers.delete("Authorization");
    if (sentToken) headers.set("Authorization", "Bearer " + sentToken);

    let response;
    const timeout = new AbortController();
    const timer = setTimeout(() => timeout.abort(), 20000);
    const abort = () => timeout.abort();
    if (settings.signal) {
      if (settings.signal.aborted) timeout.abort();
      settings.signal.addEventListener("abort", abort, { once: true });
    }
    try {
      response = await fetch(url, {
        method: settings.method || "GET",
        headers,
        body: settings.body,
        signal: timeout.signal,
        redirect: "error"
      });
    } catch (error) {
      if (settings.signal && settings.signal.aborted) {
        throw error;
      }
      const failure = new Error(timeout.signal.aborted
        ? "Máy chủ phản hồi quá lâu. Vui lòng thử lại."
        : "Không thể kết nối máy chủ. Hãy kiểm tra backend, địa chỉ API và cấu hình CORS.");
      failure.url = url;
      failure.networkError = true;
      throw failure;
    } finally {
      clearTimeout(timer);
      if (settings.signal) settings.signal.removeEventListener("abort", abort);
    }

    const data = await readResponse(response);
    if (response.status === 401 && authenticated && allowRefresh !== false && generation === sessionGeneration) {
      // A delayed 401 can arrive after another request has already rotated both tokens.
      // Retry with that token instead of rotating the new refresh token a second time.
      if (getAccessToken() && getAccessToken() !== sentToken) return request(path, settings, false);
      try {
        if (await refreshTokens()) {
          if (generation !== sessionGeneration) throw new Error("Phiên đăng nhập đã thay đổi. Vui lòng thử lại.");
          if (settings.signal?.aborted) throw new DOMException("Request aborted", "AbortError");
          return request(path, settings, false);
        }
      } catch (error) {
        error.failedRequest = { url: response.url || url, status: response.status, data };
        throw error;
      }
    }
    if (!response.ok) {
      const defaults = { 400: "Dữ liệu không hợp lệ.", 401: authenticated ? "Máy chủ từ chối xác thực. Vui lòng thử lại hoặc đăng nhập lại." : "Thông tin xác thực không hợp lệ.", 403: "Bạn không có quyền thực hiện thao tác này.",
        404: "Không tìm thấy dữ liệu trong phạm vi được phép.", 409: "Dữ liệu đã thay đổi hoặc trạng thái không cho phép thao tác.",
        422: "Không thể xử lý yêu cầu với dữ liệu hiện tại.", 429: "Quá nhiều yêu cầu. Vui lòng thử lại sau.",
        500: "Máy chủ gặp lỗi. Vui lòng thử lại sau.", 502: "Không thể kết nối backend.", 503: "Máy chủ tạm thời không sẵn sàng." };
      const details = data && data.errors && typeof data.errors === "object"
        ? Object.values(data.errors).flat().filter(value => typeof value === "string").join(" ") : "";
      const message = data && (data.message || data.detail || data.title);
      const error = new Error((response.status === 403 ? defaults[403] : typeof message === "string" ? message : defaults[response.status]
        || "Yêu cầu không thành công.") + (details ? " " + details : "") + " (HTTP " + response.status + ")");
      error.status = response.status;
      error.data = data;
      error.url = response.url || url;
      throw error;
    }
    if ((data === null || typeof data === "string") && response.status !== 204) {
      const error = new Error("API " + path.split("?")[0] + " không trả JSON hợp lệ (HTTP " + response.status
        + "; Content-Type: " + (response.headers.get("content-type") || "không có") + ").");
      error.status = 502;
      error.httpStatus = response.status;
      error.invalidResponse = true;
      error.url = response.url || url;
      error.data = data;
      throw error;
    }
    return data;
  }

  function validatePage(data, path, idFields) {
    const invalid = [];
    if (!data || typeof data !== "object" || Array.isArray(data)) invalid.push("JSON gốc phải là object");
    else {
      if (!Array.isArray(data.items)) invalid.push("items phải là mảng (kể cả khi rỗng)");
      if (!Number.isSafeInteger(data.totalItems) || data.totalItems < 0) invalid.push("totalItems phải là số nguyên không âm");
      if (!Number.isInteger(data.page) || data.page < 1 || data.page > 100000) invalid.push("page phải từ 1 đến 100000");
      if (!Number.isInteger(data.pageSize) || data.pageSize < 1 || data.pageSize > 100) invalid.push("pageSize phải từ 1 đến 100");
      if (Array.isArray(data.items) && data.items.some(item => !item || typeof item !== "object" || Array.isArray(item)
        || (idFields || []).some(key => !Number.isSafeInteger(item[key]) || item[key] <= 0))) invalid.push("dòng dữ liệu thiếu ID bắt buộc hoặc ID không hợp lệ");
    }
    if (invalid.length) throw new Error("API danh sách trả dữ liệu không hợp lệ: " + path.split("?")[0] + ". " + invalid.join("; ") + ".");
    return data;
  }

  async function refreshTokens() {
    const refreshToken = getRefreshToken();
    if (!refreshToken) {
      return false;
    }
    const generation = sessionGeneration;
    if (!refreshRequest || refreshRequest.generation !== generation) {
      const pending = { generation, promise: null };
      pending.promise = request("/api/v1/auth/refresh", {
        method: "POST",
        authenticated: false,
        body: JSON.stringify({ refreshToken })
      }, false).then(function (tokens) {
        if (generation !== sessionGeneration) throw new Error("Phiên đăng nhập đã thay đổi. Vui lòng thử lại.");
        saveSession(tokens);
        return true;
      }).catch(function (error) {
        const invalidDto = error.status === 400 && error.data?.errors
          && Object.keys(error.data.errors).some(key => key.toLowerCase() === "refreshtoken");
        // Backend confirms expired/revoked refresh tokens with 401. Generic 400/403 are not expiry.
        if (generation === sessionGeneration && (error.status === 401 || invalidDto)) {
          clearTokens();
          error.sessionExpired = true;
          error.message = "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
          window.dispatchEvent(new CustomEvent("auth:expired"));
        }
        throw error;
      }).finally(function () {
        if (refreshRequest === pending) refreshRequest = null;
      });
      refreshRequest = pending;
    }
    return refreshRequest.promise;
  }

  window.ApiClient = Object.freeze({
    request,
    validatePage,
    getAccessToken,
    getRefreshToken,
    getSession,
    storeTokens,
    clearTokens
  });
}());
