# ---- build stage: install deps with Carton
FROM perl:5.42-slim AS build
LABEL maintainer=dave@davecross.co.uk
WORKDIR /app

# System build deps (kept only in build stage)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*

# Carton + Starman available in build stage
RUN curl -fsSL https://cpanmin.us | perl - App::cpanminus && cpanm --notest Carton Starman inc::latest

# Copy just dep manifests first for better layer caching
COPY cpanfile*  ./
RUN set -euo pipefail; \
    echo "Installing deps with Carton…"; \
    CARTON_PATH=/app/local \
    carton install --deployment --path /app/local --without development --without test \
  || { \
       echo "Carton failed. Dumping cpanm build logs…"; \
       if [ -d /root/.cpanm/work ]; then \
         # show newest log first, then all logs (handy when multiple dists fail)
         NEWEST="$(ls -1td /root/.cpanm/work/* 2>/dev/null | head -1)"; \
         if [ -n "$NEWEST" ] && [ -f "$NEWEST/build.log" ]; then \
           echo "==== Newest log: $NEWEST/build.log ===="; \
           sed -n '1,200p' "$NEWEST/build.log"; \
           echo "==== tail ===="; tail -n 100 "$NEWEST/build.log"; \
         fi; \
         echo "==== All build.log files ===="; \
         find /root/.cpanm/work -type f -name build.log -print -exec sh -c 'echo "--- {} ---"; tail -n 80 "{}"' \; ; \
         echo "==== Common clues (missing headers/libs) ===="; \
         grep -R --line-number -E "fatal error:|cannot find|not found|No such file or directory" /root/.cpanm/work || true; \
       else \
         echo "No /root/.cpanm/work directory found."; \
       fi; \
       exit 1; \
     }

# Now copy the rest of the app
COPY . .

# Ensure the SQLite file exists and is read-only inside the image
RUN test -f data/los.sqlite && chmod 444 data/los.sqlite

# ---- runtime stage: small, no build tools
FROM perl:5.42-slim AS runtime
WORKDIR /app

# Minimal runtime libs (SQLite client lib only)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 \
 && rm -rf /var/lib/apt/lists/*

# Copy app and installed local libs from build stage
COPY --from=build /app /app

# Honour Cloud Run's PORT (default to 8080 locally)
ENV SUCC_DSN="dbi:SQLite:dbname=/app/data/los.sqlite;mode=ro;immutable=1" \
    PLACK_ENV=production \
    PORT=8080 \
    PATH="/app/local/bin:${PATH}" \
    PERL5LIB=/app/local/lib/perl5

EXPOSE 8080

# Slight hardening: run as non-root
RUN useradd -r -s /usr/sbin/nologin appuser && chown -R appuser:appuser /app
USER appuser

# Preload app, sensible worker count, Cloud Run will set PORT
CMD ["/bin/sh","-lc", "exec starman \
  --listen :${PORT:-8080} \
  --preload-app \
  --max-requests 1000 \
  Succession/bin/app.psgi"]
