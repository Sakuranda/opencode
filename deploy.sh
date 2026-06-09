#!/usr/bin/env bash
# deploy.sh — build opencode and deploy to production servers
# Usage:
#   ./deploy.sh           # build + deploy to all servers
#   ./deploy.sh aliyun    # deploy to aliyun only
#   ./deploy.sh usserver  # deploy to usserver only
#   ./deploy.sh --no-build # skip build, re-deploy existing dist binary
set -euo pipefail

export PATH="$HOME/.bun/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="$SCRIPT_DIR/packages/opencode/dist/opencode-linux-x64-baseline/bin/opencode"
VERSION="$(grep '"version"' "$SCRIPT_DIR/packages/opencode/package.json" | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')"

# Parse args
TARGETS=("aliyun" "usserver")
SKIP_BUILD=false
for arg in "$@"; do
  case "$arg" in
    aliyun|usserver) TARGETS=("$arg") ;;
    --no-build) SKIP_BUILD=true ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

echo "=== opencode deploy ==="
echo "version : $VERSION"
echo "targets : ${TARGETS[*]}"
echo "commit  : $(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
echo ""

# ── Step 1: Build ────────────────────────────────────────────────────────────
if [ "$SKIP_BUILD" = false ]; then
  echo "[1/3] Building linux-x64-baseline binary..."
  BUILD_LOG="/tmp/oc-deploy-build.log"
  OPENCODE_BUILD_TARGET=linux-x64-baseline \
  OPENCODE_VERSION="$VERSION" \
    bun run "$SCRIPT_DIR/packages/opencode/script/build.ts" >"$BUILD_LOG" 2>&1
  echo "      ✓ build complete"
else
  echo "[1/3] Skipping build (--no-build)"
fi

if [ ! -f "$BINARY_PATH" ]; then
  echo "ERROR: binary not found at $BINARY_PATH"
  exit 1
fi

CHECKSUM=$(shasum -a 256 "$BINARY_PATH" | awk '{print $1}')
SIZE=$(ls -lh "$BINARY_PATH" | awk '{print $5}')
echo "      binary: $SIZE  sha256=${CHECKSUM:0:16}..."

# ── Step 2: Transfer ─────────────────────────────────────────────────────────
echo ""
echo "[2/3] Transferring binary to servers..."

transfer() {
  local target=$1
  case "$target" in
    aliyun)
      scp -i ~/.ssh/macbookprom2.pem -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
        "$BINARY_PATH" sakuranda@47.102.144.62:/tmp/opencode-new
      ;;
    usserver)
      scp -i ~/.ssh/macbookprom2.pem -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
        -P 55202 "$BINARY_PATH" root@70.39.197.158:/tmp/opencode-new
      ;;
  esac
  echo "      ✓ $target transferred"
}

pids=()
for t in "${TARGETS[@]}"; do
  transfer "$t" &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done

# ── Step 3: Deploy ───────────────────────────────────────────────────────────
echo ""
echo "[3/3] Replacing binary and restarting services..."

DEPLOY_CMD='
  set -e
  CHECKSUM=$(sha256sum /tmp/opencode-new | awk "{print \$1}")
  DATE=$(date +%Y%m%d)
  cp /usr/local/bin/opencode /usr/local/bin/opencode.bak-$DATE 2>/dev/null || true
  install -m 755 -o root -g root /tmp/opencode-new /usr/local/bin/opencode
  systemctl restart opencode
  sleep 2
  STATUS=$(systemctl is-active opencode)
  VERSION=$(opencode --version)
  echo "status=$STATUS version=$VERSION sha256=${CHECKSUM:0:16}..."
'

deploy() {
  local target=$1
  local result
  case "$target" in
    aliyun)
      result=$(printf 'hlyx0209\n' | ssh -o BatchMode=no aliyun \
        "sudo -S -p '' bash -c '$DEPLOY_CMD'" 2>/dev/null | grep -v "^\[sudo\]")
      ;;
    usserver)
      result=$(ssh usserver "bash -c '$DEPLOY_CMD'" 2>/dev/null)
      ;;
  esac
  echo "      ✓ $target — $result"
}

pids=()
for t in "${TARGETS[@]}"; do
  deploy "$t" &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done

echo ""
echo "=== deploy complete ==="
echo "Refresh browsers with Cmd+Shift+R to pick up new frontend assets."
