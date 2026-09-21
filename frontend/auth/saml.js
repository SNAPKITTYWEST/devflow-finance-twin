// SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
// Copyright (c) 2026 SNAPKITTYWEST. All rights reserved.

import { setToken, clearToken } from "./jwt.js";

/**
 * Build a minimal SAML AuthnRequest XML string.
 * @returns {string}
 */
function buildAuthnRequest() {
  const id = "_" + crypto.randomUUID().replace(/-/g, "");
  const issueInstant = new Date().toISOString();
  return (
    '<samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"' +
    ' xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"' +
    ' ID="' + id + '"' +
    ' Version="2.0"' +
    ' IssueInstant="' + issueInstant + '"' +
    ' ProtocolBinding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST">' +
    "<saml:Issuer>VisualWorkplace</saml:Issuer>" +
    "</samlp:AuthnRequest>"
  );
}

/**
 * Redirect to the SAML Identity Provider for SSO login.
 * Encodes a minimal AuthnRequest as a base64 SAMLRequest query parameter.
 * @param {string} idpUrl - the IdP SSO endpoint URL
 */
export function redirectToIdP(idpUrl) {
  const xml = buildAuthnRequest();
  const encoded = btoa(xml);
  const separator = idpUrl.includes("?") ? "&" : "?";
  window.location.href = idpUrl + separator + "SAMLRequest=" + encodeURIComponent(encoded);
}

/**
 * Handle the SAML callback after IdP authentication.
 * Looks for a SAMLResponse in the URL search params or hash,
 * extracts it, and attempts to find and store a JWT token.
 * @returns {string|null} the extracted token, or null
 */
export function handleCallback() {
  const params = new URLSearchParams(window.location.search || window.location.hash.replace(/^#/, "?"));
  const samlResponse = params.get("SAMLResponse");
  if (!samlResponse) return null;

  try {
    const decoded = atob(samlResponse);
    // Attempt to extract a JWT-like token from the decoded response.
    // In a real implementation the IdP callback sets the token directly;
    // here we look for a Bearer token pattern or fall back to the raw value.
    const jwtMatch = decoded.match(/eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/);
    if (jwtMatch) {
      setToken(jwtMatch[0]);
      return jwtMatch[0];
    }
  } catch {
    // decoding failed -- not a valid base64 response
  }

  // Check if a token was set directly as a query param (common in dev/test)
  const directToken = params.get("token");
  if (directToken) {
    setToken(directToken);
    return directToken;
  }

  return null;
}

/**
 * Perform SAML Single Logout.
 * Clears the local JWT and redirects to the SLO endpoint.
 * @param {string} sloUrl - the IdP Single Logout URL
 */
export function logout(sloUrl) {
  clearToken();
  window.location.href = sloUrl;
}
