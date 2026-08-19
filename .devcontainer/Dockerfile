# Build gitleaks from source on a patched Go toolchain. Upstream release
# binaries are currently compiled with go1.24.11, whose stdlib carries
# CVE-2025-68121 (crypto/tls, CRITICAL — fixed in 1.24.13/1.25.7/1.26.0-rc.3),
# so they trip the Trivy container-scan gate. `go install` verifies the module
# against the Go checksum database (sum.golang.org), which replaces the
# release-tarball sha256 pin. Revisit pinning a release binary again once
# upstream ships one built on a fixed Go.
FROM golang:1.26.6 AS gitleaks-build
ARG GITLEAKS_VERSION=8.30.1
RUN CGO_ENABLED=0 go install "github.com/zricethezav/gitleaks/v8@v${GITLEAKS_VERSION}"

FROM node:24@sha256:934240a162082fd8b8a2f90cd5114446443f1eba1c5378f6687167ca405e6584

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Replace the npm bundled in the base image. node:24 currently ships an npm
# whose vendored node-tar is 7.5.15, carrying CVE-2026-59873 (DoS via crafted
# gzip bomb, CRITICAL, fixed in 7.5.19) at
# /usr/local/lib/node_modules/npm/node_modules/tar — the sole CRITICAL failing
# the container-scan gate since 2026-07-27. A global npm install overwrites
# that exact path.
#
# 11.19.0 rather than 12.0.2: both declare `tar: ^7.5.19`, but npm 12 requires
# node ^24.15.0 and is a major bump for every derivative's lockfiles, while
# 11.19.0 keeps engines at `^20.17.0 || >=22.9.0`. Same fix, no major.
# Remove this once the pinned node:24 digest ships npm >= 11.19.0 itself.
# Dependabot digest bumps do not imply that — the pending 5711a0d bump only
# moves tar to 7.5.16.
ARG NPM_VERSION=11.19.0
RUN npm install -g "npm@${NPM_VERSION}" && npm --version

# Install basic development tools and iptables/ipset.
# `apt-get upgrade` pulls patched Debian security packages into the image so the
# container-scan (Trivy) gate isn't tripped by base-image CVEs that Debian has
# already fixed. The base digest is pinned and refreshed via Dependabot.
RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends \
  less \
  git \
  python3 \
  python3-pip \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install a modern pre-commit version at build time to avoid runtime PyPI access.
RUN python3 -m pip install --break-system-packages "pre-commit>=3.7.0"

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions.
# /home/node/.config/gh must exist node-owned in the image so the gh-config
# named volume inherits that ownership on first mount (gh stores its browser
# OAuth token there — never in env vars or repo files).
RUN mkdir -p /workspace /home/node/.claude /home/node/.config/gh /home/node/.npm-global && \
  chown -R node:node /workspace /home/node/.claude /home/node/.config /home/node/.npm-global

WORKDIR /workspace

# Download and SHA256-verify git-delta before installing
ARG GIT_DELTA_VERSION=0.18.2
ARG GIT_DELTA_SHA256_AMD64=1658c7b61825d411b50734f34016101309e4b6e7f5799944cf8e4ac542cebd7f
ARG GIT_DELTA_SHA256_ARM64=937781aa7788e1510858743fff6c9a8b4a69fe0a22a7c8a69493e633227939a9
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" -O git-delta.deb && \
  case "$ARCH" in \
    amd64) EXPECTED_SHA256="$GIT_DELTA_SHA256_AMD64" ;; \
    arm64) EXPECTED_SHA256="$GIT_DELTA_SHA256_ARM64" ;; \
    *) echo "ERROR: Unsupported architecture: $ARCH" && exit 1 ;; \
  esac && \
  echo "${EXPECTED_SHA256}  git-delta.deb" | sha256sum -c - && \
  dpkg -i git-delta.deb && \
  rm git-delta.deb

# Download and SHA256-verify gh. Debian bookworm's apt package is 2.23.0
# (2023), which predates `gh project` (needs >= 2.31) — the Kanban board
# scripts (bootstrap-project.sh, board.sh) hard-require it.
#
# GH_VERSION is not tracked by Dependabot (it is an ARG + wget, not a FROM), so
# it drifts silently and must be bumped by hand. When bumping, check what the
# release binary was actually compiled with rather than assuming the newest tag
# is clean — 2.96.0 shipped after 2.95.0 but was still built on the unpatched
# Go 1.26.4 and carried the same stdlib CVEs:
#   go.mod at the tag must show `toolchain go1.26.5` or newer, and
#   `strings gh | grep -m1 '^go1\.'` on the extracted binary must agree.
ARG GH_VERSION=2.97.0
ARG GH_SHA256_AMD64=a2c9b8497e1f85b1ad0dfcb78b5a622e098801b8e461e459e88e1ee12f018112
ARG GH_SHA256_ARM64=73ea440ecad9c9e284429997ee6f93577bc6f7bc6fba357ef62c53ad8fb641a5
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    amd64) EXPECTED_SHA256="$GH_SHA256_AMD64" ;; \
    arm64) EXPECTED_SHA256="$GH_SHA256_ARM64" ;; \
    *) echo "ERROR: Unsupported architecture: $ARCH" && exit 1 ;; \
  esac && \
  wget "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" -O gh.tar.gz && \
  echo "${EXPECTED_SHA256}  gh.tar.gz" | sha256sum -c - && \
  tar -xzf gh.tar.gz --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_${ARCH}/bin/gh" && \
  rm gh.tar.gz

# gitleaks: built from source in the gitleaks-build stage above (see the
# comment there for why a release binary isn't used). Baked into the image so
# the pre-commit hook can run it as `language: system` — the runtime firewall
# blocks the Go toolchain downloads the default golang hook would need. Keep
# GITLEAKS_VERSION in sync with the gitleaks rev in .pre-commit-config.yaml.
COPY --from=gitleaks-build /go/bin/gitleaks /usr/local/bin/gitleaks

# Set up non-root user
USER node

# Install global packages
# The npm prefix lives under /home/node so it survives devcontainer uid
# remapping (updateRemoteUserUID re-chowns the home dir only) — required for
# Claude Code auto-update to work at runtime without sudo.
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH=$PATH:/home/node/.npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Download, SHA256-verify, then install zsh theme.
# Run as root: zsh-in-docker's dependency step calls `sudo` when it isn't root,
# which fails in a non-interactive build (no passwordless sudo yet). We target
# HOME=/home/node so the theme installs into the node user's home, then restore
# ownership before dropping back to the node user.
USER root
ARG ZSH_IN_DOCKER_VERSION=1.2.0
ARG ZSH_IN_DOCKER_SHA256=f74e5b08c295b6c3886654bb63c688e5ea16c58a4209435c4ddbab2c42fe9b41
RUN wget "https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh" -O /tmp/zsh-in-docker.sh && \
  echo "${ZSH_IN_DOCKER_SHA256}  /tmp/zsh-in-docker.sh" | sha256sum -c - && \
  HOME=/home/node sh /tmp/zsh-in-docker.sh -- \
    -p git \
    -p fzf \
    -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "source /usr/share/doc/fzf/examples/completion.zsh" \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    -x && \
  chown -R node:node /home/node && \
  rm /tmp/zsh-in-docker.sh
USER node

# Pre-approve Claude Code's postinstall script so global installs — including
# runtime auto-updates — run without npm's allow-scripts warning. Unpinned
# (package name, not pkg@version) so future versions stay covered.
RUN printf 'allow-scripts[]=@anthropic-ai/claude-code\n' >> /home/node/.npmrc

# Install Claude
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}


# Copy and set up firewall script
COPY .devcontainer/init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
