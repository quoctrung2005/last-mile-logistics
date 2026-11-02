"use strict";

(function () {
  const REMEMBERED_USERNAME_KEY = "tvd.rememberedUsername";

  async function login(username, password) {
    const result = await window.ApiClient.request("/api/v1/auth/login", {
      method: "POST",
      authenticated: false,
      body: JSON.stringify({ username, password })
    }, false);
    window.ApiClient.storeTokens(result);
    return result.user;
  }

  async function getCurrentUser() {
    return window.ApiClient.request("/api/v1/auth/me");
  }

  async function getPermissions(user, signal) {
    const result = await window.ApiClient.request("/api/v1/auth/permissions", { signal });
    if (!result || String(result.accountId) !== String(user.accountId) || !Array.isArray(result.permissions)
      || result.permissions.some(code => typeof code !== "string")) throw new Error("Không đọc được quyền thao tác của tài khoản.");
    return { known: true, codes: new Set(result.permissions) };
  }

  async function logout() {
    const refreshToken = window.ApiClient.getRefreshToken();
    try {
      if (refreshToken) {
        await window.ApiClient.request("/api/v1/auth/logout", {
          method: "POST",
          authenticated: false,
          body: JSON.stringify({ refreshToken, allSessions: false })
        }, false);
      }
    } finally {
      window.ApiClient.clearTokens();
    }
  }

  function rememberedUsername() {
    return localStorage.getItem(REMEMBERED_USERNAME_KEY) || "";
  }

  function rememberUsername(username, remember) {
    if (remember && username) {
      localStorage.setItem(REMEMBERED_USERNAME_KEY, username);
    } else {
      localStorage.removeItem(REMEMBERED_USERNAME_KEY);
    }
  }

  window.Auth = Object.freeze({
    login,
    getCurrentUser,
    getPermissions,
    logout,
    rememberedUsername,
    rememberUsername
  });
}());
