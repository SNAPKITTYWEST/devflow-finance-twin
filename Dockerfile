# Devflow Finance Twin — Production Dockerfile
# Multi-stage build for minimal attack surface
# SPDX-License-Identifier: AGPL-3.0-or-later

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM python:3.12.8-slim AS builder

WORKDIR /build

# Install only production dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM python:3.12.8-slim AS runtime

# Security: remove pip, reduce image
RUN pip install --no-cache-dir pip && \
    pip uninstall -y pip setuptools wheel 2>/dev/null; \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache

# Security: non-root user
RUN groupadd -r devflow && useradd -r -g devflow -d /app -s /sbin/nologin devflow

WORKDIR /app

# Copy installed dependencies
COPY --from=builder /install /usr/local

# Copy application source
COPY src/ ./src/
COPY wasm/ ./wasm/
COPY compile_wasm.js .

# Set ownership
RUN chown -R devflow:devflow /app

# Security: drop to non-root
USER devflow

# Environment
ENV PYTHONPATH=/app/src \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Healthcheck: verify WORM integrity on a test ledger
HEALTHCHECK --interval=60s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "\
import sys; sys.path.insert(0, '/app/src'); \
from worm import WormStorageEngine; \
from twin import FinanceTwinEngine; \
s = WormStorageEngine('/tmp/health.worm'); \
t = FinanceTwinEngine(s); \
v, e = t.verify_ledger_consistency(); \
exit(0 if v else 1)" || exit 1

ENTRYPOINT ["python", "src/cli.py"]
