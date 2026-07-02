FROM node:24@sha256:fdddfb3e688158251943d52eba361de991548f6814007acba4917ae6b512d6be

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

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
RUN mkdir -p /workspace /home/node/.claude /home/node/.config/gh && \
  chown -R node:node /workspace /home/node/.claude /home/node/.config

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
ARG GH_VERSION=2.95.0
ARG GH_SHA256_AMD64=25d1e4729e8808c9ed3d613e96ebd3f3e44446f2d368c89d878a71a36ddb3d8c
ARG GH_SHA256_ARM64=d41e0b3b6218e5741c8bb4db39b16e53a59e0e06299a8489bd38f623ef7ebaae
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

# Download and SHA256-verify gitleaks. Baked into the image so the pre-commit
# hook can run it as `language: system` — building it from source would require
# opening the firewall to the Go toolchain and module proxy (go.dev,
# dl.google.com, proxy.golang.org, sum.golang.org).
ARG GITLEAKS_VERSION=8.24.2
ARG GITLEAKS_SHA256_AMD64=fa0500f6b7e41d28791ebc680f5dd9899cd42b58629218a5f041efa899151a8e
ARG GITLEAKS_SHA256_ARM64=574a6d52573c61173add7ddb5e3cc68c0e82cb0735818a1eeb9a0a2de1643fbc
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    amd64) GL_ARCH="x64"; EXPECTED_SHA256="$GITLEAKS_SHA256_AMD64" ;; \
    arm64) GL_ARCH="arm64"; EXPECTED_SHA256="$GITLEAKS_SHA256_ARM64" ;; \
    *) echo "ERROR: Unsupported architecture: $ARCH" && exit 1 ;; \
  esac && \
  wget "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" -O gitleaks.tar.gz && \
  echo "${EXPECTED_SHA256}  gitleaks.tar.gz" | sha256sum -c - && \
  tar -xzf gitleaks.tar.gz -C /usr/local/bin gitleaks && \
  rm gitleaks.tar.gz

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

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

# Install Claude
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}


# Copy and set up firewall script
COPY .devcontainer/init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
