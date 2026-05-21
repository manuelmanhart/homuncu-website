#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PI_DIR="$PROJECT_ROOT/homuncu-pi"
DL_DIR="$SCRIPT_DIR"

if [ ! -d "$PI_DIR" ]; then
  echo "[ERROR] homuncu-pi directory not found at $PI_DIR"
  echo "       Set HOMUNCU_PI_DIR in .env to override."
  exit 1
fi

ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

if [ -n "$HOMUNCU_PI_DIR" ]; then
  PI_DIR="$HOMUNCU_PI_DIR"
fi

VERSION=$(cat "$PI_DIR/VERSION" | tr -d '[:space:]')
# --- Read version ---
# --- Determine channel ---
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  CHANNEL="stable"
  ARCHIVE_NAME="homuncu-pi-${VERSION}.tar.gz"
  echo "[INFO] Detected stable release"
else
  CHANNEL="dev"
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  ARCHIVE_NAME="homuncu-pi-${VERSION}-${TIMESTAMP}.tar.gz"
  echo "[INFO] Detected dev build  (timestamp: $TIMESTAMP)"
  VERSION=$(echo "${VERSION}-${TIMESTAMP}")
fi

echo "[INFO] Homuncu PI version: $VERSION"

# --- Build archive ---
TARGET_DIR="$DL_DIR/$CHANNEL"
mkdir -p "$TARGET_DIR"
ARCHIVE_PATH="$TARGET_DIR/$ARCHIVE_NAME"

echo "[INFO] Building $ARCHIVE_NAME ..."

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/homuncu-pi"

if command -v git &>/dev/null && [ -d "$PI_DIR/.git" ]; then
  cd "$PI_DIR"
  git archive --format=tar HEAD | tar -x -C "$TEMP_DIR/homuncu-pi"
  echo "[INFO] Created from git HEAD"
else
  cd "$PI_DIR"
  if [ -d "$PI_DIR/.git" ]; then
    echo "[WARN] git found but no .git? creating from directory..."
  fi
  tar -c -f - \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='venv' \
    --exclude='*.pyc' \
    --exclude='.DS_Store' \
    . | tar -x -C "$TEMP_DIR/homuncu-pi"
  echo "[INFO] Created from directory"
fi

# Append timestamp to VERSION inside archive for dev builds
if [ "$CHANNEL" == "dev" ]; then
  echo "${VERSION}" > "$TEMP_DIR/homuncu-pi/VERSION"
fi

tar -czf "$ARCHIVE_PATH" -C "$TEMP_DIR" homuncu-pi

# --- Checksum (relative filename inside, so archive can be moved) ---
cd "$TARGET_DIR"
sha256sum "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
echo "[INFO] SHA256: $(cut -d' ' -f1 < "$ARCHIVE_NAME.sha256")"

# --- Write VERSION file (clean version without timestamp) ---
echo "$VERSION" > "$TARGET_DIR/VERSION"

# --- Update root VERSION only for stable ---
if [ "$CHANNEL" == "stable" ]; then
  echo "$VERSION" > "$DL_DIR/VERSION"
  echo "[INFO] Root VERSION updated to $VERSION"
fi

echo "[INFO] Archive:  $ARCHIVE_PATH"
echo "[INFO] VERSION:  $(cat "$TARGET_DIR/VERSION")"

# --- Upload via SCP ---
if [ -n "$HOMUNCU_SERVER" ] && [ -n "$HOMUNCU_REMOTE_DIR" ]; then
  REMOTE_PATH="${HOMUNCU_SERVER}:${HOMUNCU_REMOTE_DIR}"
  echo "[INFO] Uploading to $REMOTE_PATH ..."

  ssh "$HOMUNCU_SERVER" "mkdir -p ${HOMUNCU_REMOTE_DIR}/${CHANNEL}"

  scp "$ARCHIVE_PATH"            "${REMOTE_PATH}/${CHANNEL}/"
  scp "$ARCHIVE_PATH.sha256"     "${REMOTE_PATH}/${CHANNEL}/"
  scp "$TARGET_DIR/VERSION"      "${REMOTE_PATH}/${CHANNEL}/"

  if [ "$CHANNEL" == "stable" ]; then
    scp "$DL_DIR/VERSION"        "${REMOTE_PATH}/"
  fi

  echo "[INFO] Upload finished."
else
  echo "[WARN] HOMUNCU_SERVER and/or HOMUNCU_REMOTE_DIR not set."
  echo "       Create a .env file in $SCRIPT_DIR:"
  echo "       HOMUNCU_SERVER=\"user@host\""
  echo "       HOMUNCU_REMOTE_DIR=\"/path/on/server\""
  echo "       # HOMUNCU_PI_DIR=\"/path/to/homuncu-pi\"      # optional override"
fi
