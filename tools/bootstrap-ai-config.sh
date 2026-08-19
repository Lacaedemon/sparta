#!/usr/bin/env bash
# Bootstrap Morrison-Lab/ai-config into .ai-config/ for Gemini CLI / Antigravity
# sessions. The checkout is gitignored and pinned by .ai-config-ref (committed).
# Claude Code uses the plugin marketplace instead (.claude/settings.json).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_FILE="$REPO_ROOT/.ai-config-ref"
DEST="$REPO_ROOT/.ai-config"
URL="https://github.com/Morrison-Lab/ai-config.git"

info() { printf 'bootstrap-ai-config: %s\n' "$*"; }
err() { printf 'bootstrap-ai-config: ERROR: %s\n' "$*" >&2; }

if [ ! -f "$REF_FILE" ]; then
  err "missing pin file $REF_FILE"
  exit 1
fi

PIN="$(tr -d '[:space:]' < "$REF_FILE")"
if [ -z "$PIN" ]; then
  err "$REF_FILE is empty"
  exit 1
fi

if [ -d "$DEST/.git" ]; then
  CURRENT="$(git -C "$DEST" rev-parse HEAD 2>/dev/null || true)"
  if [ "$CURRENT" = "$PIN" ]; then
    info "already at $PIN"
  else
    info "updating checkout from ${CURRENT:-unknown} to $PIN"
    git -C "$DEST" fetch --depth 1 origin "$PIN"
    git -C "$DEST" checkout --force "$PIN"
  fi
else
  info "cloning ai-config at $PIN"
  rm -rf "$DEST"
  if ! git clone --filter=blob:none --no-checkout "$URL" "$DEST"; then
    err "failed to clone $URL"
    exit 1
  fi
  git -C "$DEST" fetch --depth 1 origin "$PIN"
  git -C "$DEST" checkout --force "$PIN"
fi

if [ -f "$DEST/.gitmodules" ]; then
  info "initializing sembr-skills submodule"
  git -C "$DEST" submodule update --init --depth 1 shared/sembr-skills
fi

info "done ($(git -C "$DEST" rev-parse --short HEAD))"
