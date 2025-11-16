FROM perl:5.42-slim
LABEL maintainer="dave@davecross.co.uk"

WORKDIR /app

# System deps: compiler, headers, SQLite, expat (for XML::Parser), curl/git for cpanm
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    libsqlite3-0 \
    libsqlite3-dev \
    libexpat1-dev \
    unzip \
 && rm -rf /var/lib/apt/lists/*

# Install cpanm
RUN curl -fsSL https://cpanmin.us | perl - App::cpanminus

# Copy dependency manifests first for better caching
COPY cpanfile* ./

# Install application dependencies via cpanm (using cpanfile)
RUN set -euo pipefail; \
    echo "Installing CPAN dependencies with cpanm…"; \
    cpanm --notest --installdeps . \
  || { \
       echo "cpanm failed. Dumping build logs…"; \
       if [ -d /root/.cpanm/work ]; then \
         NEWEST="$(ls -1td /root/.cpanm/work/* 2>/dev/null | head -1)"; \
         if [ -n "$NEWEST" ] && [ -f "$NEWEST/build.log" ]; then \
           echo "==== Newest log: $NEWEST/build.log ===="; \
           sed -n '1,200p' "$NEWEST/build.log"; \
           echo "==== tail ===="; tail -n 100 "$NEWEST/build.log"; \
         fi; \
         echo "==== All build.log files ===="; \
         find /root/.cpanm/work -type f -name build.log -print -exec sh -c 'echo \"--- {} ---\"; tail -n 80 \"{}\"' \; ; \
       else \
         echo "No /root/.cpanm/work directory found."; \
       fi; \
       exit 1; \
     }

# Now copy the rest of the app
COPY . .

# Ensure the SQLite file exists and is read-only inside the image
RUN test -f data/los.sqlite && chmod 444 data/los.sqlite

# Runtime env
ENV SUCC_DSN="dbi:SQLite:dbname=/app/data/los.sqlite;mode=ro;immutable=1" \
    PLACK_ENV=production \
    PORT=8080

EXPOSE 8080

# Slight hardening: run as non-root
RUN useradd -r -s /usr/sbin/nologin appuser && chown -R appuser:appuser /app
USER appuser

# Preload app; Cloud Run will set PORT
CMD ["/bin/sh","-lc", "exec starman \
  --listen :${PORT:-8080} \
  --preload-app \
  --max-requests 1000 \
  Succession/bin/app.psgi"]

