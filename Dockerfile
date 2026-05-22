# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG GLAB_VERSION=1.97.0

ENV HOME=/home/repolens \
    PATH=/home/repolens/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    REPOLENS_PROJECT_DIR=/project \
    REPOLENS_AGENT=opencode \
    REPOLENS_MODE=audit

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      coreutils \
      curl \
      git \
      jq \
      nodejs \
      npm \
      tar \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# Install GitLab CLI (glab) from official release packages.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) glab_arch="amd64" ;; \
      arm64) glab_arch="arm64" ;; \
      *) echo "Unsupported TARGETARCH for glab: ${TARGETARCH:-unset}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/glab.deb "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${glab_arch}.deb"; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/glab.deb; \
    rm -f /tmp/glab.deb; \
    rm -rf /var/lib/apt/lists/*
    

# Install opencode. The npm package is opencode-ai; the binary is opencode.
RUN npm install -g opencode-ai \
 && npm cache clean --force

RUN useradd --create-home --home-dir /home/repolens --shell /bin/bash repolens;

WORKDIR /opt/repolens
COPY --chown=repolens:repolens . /opt/repolens

RUN chmod +x /opt/repolens/repolens.sh /opt/repolens/scripts/run-gitlab-opencode.sh; \
    mkdir /project; \
    chown repolens:repolens /opt/repolens; \
    chown repolens:repolens /project;

RUN chown repolens:repolens /home/repolens/.config -R; \
    chown repolens:repolens /home/repolens/.config/opencode -R; \
    chown repolens:repolens /home/repolens/.local -R;



USER repolens
ENTRYPOINT ["/opt/repolens/scripts/run-gitlab-opencode.sh"]
