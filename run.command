#!/bin/bash
# macOS launcher (stable, avoids Conda/Anaconda PATH issues)
# - Uses a project-local venv at .venv (created on first run)
# - Installs deps from requirements.txt (root or backend)
# - Starts the app from backend/ so imports like "from services..." work

set -Eeuo pipefail

pause() { echo ""; read -n 1 -s -r -p "Press any key to exit..."; echo ""; }
trap 'echo ""; echo "[ERROR] Failed: ${BASH_COMMAND}"; pause' ERR

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$ROOT/backend"
VENV="$ROOT/.venv"
PY="$VENV/bin/python"

HOST="127.0.0.1"
PORT="8000"
URL="http://${HOST}:${PORT}/"

echo "[INFO] Project root: $ROOT"
echo "[INFO] Backend dir : $BACKEND"

if [[ ! -d "$BACKEND" ]]; then
  echo "[ERROR] Missing backend folder."
  pause; exit 1
fi
if [[ ! -f "$BACKEND/app.py" ]]; then
  echo "[ERROR] Missing backend/app.py"
  pause; exit 1
fi

# Prefer macOS system python to create venv (avoid conda)
SYS_PY="/usr/bin/python3"
if [[ ! -x "$SYS_PY" ]]; then
  if command -v python3 >/dev/null 2>&1; then SYS_PY="$(command -v python3)"; fi
fi
if [[ -z "${SYS_PY:-}" ]]; then
  echo "[ERROR] Python 3 not found. Install Python 3 first."
  pause; exit 1
fi

# Create venv if missing
if [[ ! -x "$PY" ]]; then
  echo "[INFO] Creating venv: $VENV"
  "$SYS_PY" -m venv "$VENV"
fi

echo "[INFO] Using venv python: $PY"
"$PY" -c "import sys; print('[INFO] Python:', sys.version.split()[0], '|', sys.executable)"

# Pick requirements file
REQ=""
if [[ -f "$BACKEND/requirements.txt" ]]; then
  REQ="$BACKEND/requirements.txt"
elif [[ -f "$ROOT/requirements.txt" ]]; then
  REQ="$ROOT/requirements.txt"
fi

if [[ -n "$REQ" ]]; then
  echo "[INFO] Installing deps: $REQ"
  "$PY" -m pip install -r "$REQ"
else
  echo "[WARN] No requirements.txt found (root or backend)."
fi

# If AI tutor imports OpenAI at import-time, ensure openai exists
"$PY" -c "import openai" >/dev/null 2>&1 || {
  echo "[INFO] Installing openai (AI tutor dependency)..."
  "$PY" -m pip install openai
}

# Data check (warning only)
if [[ ! -f "$BACKEND/data/passages.json" ]]; then
  echo "[WARN] Missing backend/data/passages.json"
  echo "[WARN] The app may require it to run exams."
fi

# Port check (best effort)
if command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[ERROR] Port $PORT is already in use."
    echo "[ERROR] Stop the other process or change PORT in run.command."
    pause; exit 1
  fi
fi

# Start from backend/ so imports like "routes" / "services" resolve
cd "$BACKEND"
echo "[INFO] Starting: $URL"
( sleep 1; open "$URL" ) >/dev/null 2>&1 || true
exec "$PY" -m uvicorn app:app --reload --host "$HOST" --port "$PORT"
