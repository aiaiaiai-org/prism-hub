# syntax=docker/dockerfile:1
# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

# The signal binaries the hub runs as subprocesses: the collector reads channels, the runtime reads
# and fuses. Pinned to a commit, so a rebuild of this commit runs the same reader.
FROM rust:1.94-slim-bookworm AS signal
ARG PRISM_SIGNAL_REV=4ef6b9ff09f1cb192fa9b4c47d7fd3e9d20a8ac0
RUN apt-get update \
    && apt-get install --yes --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN cargo install --locked --root /out \
    --git https://github.com/aiaiaiai-org/prism-signal --rev "${PRISM_SIGNAL_REV}" \
    prism-signal-collect prism-signal-runtime

# Porter renders what the hub queues. It is a plain Ruby program with no gems.
FROM ruby:4.0.6-slim AS porter
ARG PRISM_PORTER_REV=569658967760b250fa67db4dad55cbee45bf3e37
RUN apt-get update \
    && apt-get install --yes --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git init /opt/prism-porter \
    && git -C /opt/prism-porter fetch --depth 1 https://github.com/aiaiaiai-org/prism-porter "${PRISM_PORTER_REV}" \
    && git -C /opt/prism-porter checkout --detach FETCH_HEAD \
    && rm -rf /opt/prism-porter/.git

# The hub's gems.
FROM ruby:4.0.6-slim AS gems
RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/usr/local/bundle
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 \
    && rm -rf /usr/local/bundle/ruby/*/cache

FROM ruby:4.0.6-slim
# postgresql-client is for `db:prepare` loading db/structure.sql into an empty database.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends libpq5 postgresql-client ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --uid 1927 hub

WORKDIR /app
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/usr/local/bundle \
    PORT=1927 \
    # TLS ends at the edge (Caddy); inside the network the hub speaks plain HTTP, and the health
    # check must not be redirected.
    RAILS_FORCE_SSL=false \
    RAILS_LOG_LEVEL=info \
    PRISM_PORTER_COMMAND_JSON='["ruby","-I/opt/prism-porter/lib","/opt/prism-porter/bin/prism-porter"]' \
    PRISM_SIGNAL_COLLECT_COMMAND_JSON='["/usr/local/bin/prism-signal-collect"]' \
    PRISM_SIGNAL_RUNTIME_COMMAND_JSON='["/usr/local/bin/prism-signal-runtime","--json"]'

COPY --from=signal /out/bin/prism-signal-collect /out/bin/prism-signal-runtime /usr/local/bin/
COPY --from=porter /opt/prism-porter /opt/prism-porter
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --chown=hub:hub . .

USER hub
EXPOSE 1927

# GET /healthz answers on 1927 without a credential.
ENTRYPOINT ["bin/prism-hub-container"]
