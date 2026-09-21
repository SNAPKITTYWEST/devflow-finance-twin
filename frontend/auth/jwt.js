// SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
// Copyright (c) 2026 SNAPKITTYWEST. All rights reserved.

const TOKEN_KEY = "jwt_token";
const _refreshCallbacks = [];

/**
 * Decode a JWT payload from a base64url-encoded token.
 * @param {string} token
 * @returns {object} parsed JSON payload
 */
export function parseJwt(token) {
  const base64Url = token.split(".")[1];
  if (!base64Url) throw new Error("Invalid JWT: missing payload segment");
  const base64 = base64Url.replace(/-/g, "+").replace(/_/g, "/");
  const json = decodeURIComponent(
    atob(base64)
      .split("")
      .map((c) => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2))
      .join("")
  );
  return JSON.parse(json);
}

/**
 * Check whether a JWT token has expired.
 * @param {string} token
 * @returns {boolean} true if expired
 */
export function isExpired(token) {
  try {
    const payload = parseJwt(token);
    if (!payload.exp) return false;
    return payload.exp < Date.now() / 1000;
  } catch {
    return true;
  }
}

/**
 * Retrieve the stored JWT from sessionStorage.
 * @returns {string|null}
 */
export function getToken() {
  return sessionStorage.getItem(TOKEN_KEY);
}

/**
 * Store a JWT in sessionStorage.
 * @param {string} token
 */
export function setToken(token) {
  sessionStorage.setItem(TOKEN_KEY, token);
}

/**
 * Remove the stored JWT from sessionStorage.
 */
export function clearToken() {
  sessionStorage.removeItem(TOKEN_KEY);
}

/**
 * Build an Authorization header object for fetch requests.
 * @returns {object} header object with Bearer token, or empty object
 */
export function authHeader() {
  const token = getToken();
  if (token) {
    return { Authorization: "Bearer " + token };
  }
  return {};
}

/**
 * Register a callback to be invoked on token refresh.
 * @param {function} callback
 */
export function onTokenRefresh(callback) {
  if (typeof callback === "function") {
    _refreshCallbacks.push(callback);
  }
}

/**
 * Invoke all registered token-refresh callbacks.
 */
export function refreshToken() {
  for (const cb of _refreshCallbacks) {
    try {
      cb();
    } catch (err) {
      console.error("Token refresh callback error:", err);
    }
  }
}
