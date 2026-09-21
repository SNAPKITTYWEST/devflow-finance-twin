// SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
// Copyright (c) 2026 SNAPKITTYWEST. All rights reserved.

import { getToken, isExpired, authHeader } from "./jwt.js";
import { redirectToIdP } from "./saml.js";

/**
 * Check whether the user holds a valid (non-expired) JWT.
 * @returns {boolean}
 */
export function checkAuth() {
  const token = getToken();
  if (!token) return false;
  return !isExpired(token);
}

/**
 * Require authentication. If no valid JWT exists, redirect to the
 * SAML Identity Provider for SSO login.
 * @param {string} idpUrl - the IdP SSO endpoint URL
 * @returns {boolean} true if already authenticated, false if redirecting
 */
export function requireAuth(idpUrl) {
  if (checkAuth()) return true;
  redirectToIdP(idpUrl);
  return false;
}

/**
 * Inject the JWT Authorization header into a fetch options object.
 * Merges the Bearer token header with any existing headers.
 * @param {object} [fetchOptions={}] - the fetch init object
 * @returns {object} modified fetch options with Authorization header
 */
export function injectAuthHeaders(fetchOptions = {}) {
  const auth = authHeader();
  if (!auth.Authorization) return fetchOptions;

  const existing = fetchOptions.headers || {};
  fetchOptions.headers = Object.assign({}, existing, auth);
  return fetchOptions;
}
