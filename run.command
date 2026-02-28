#!/bin/bash
# Verraco launcher for macOS (robust against Conda/Anaconda PATH issues)
# - Creates/uses a local venv at .venv
# - Installs backend requirements (and openai) into the venv
# - Starts Uvicorn reliably from project root

set -Eeuo pipefail

pause() {
  echo ""
  read -n 1 -s -r -p "Press any key to exit..."
  echo ""
}

on_error() {
  local code=$?
  echo ""
  echo "[ERROR] Launcher failed (exit code: $code)."
  echo "[ERROR] Last command: ${BASH_COMMAND}"
  pause
  exit "$code"
}
trap on_error ERR

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$ROOT/backend"
VENV_DIR="$ROOT/.venv"
VENV_PY="$VENV_DIR/bin/python"
VENV_UVICORN="$VENV_DIR/bin/uvicorn"

HOST="127.0.0.1"
PORT="8000"
URL="http://${HOST}:${PORT}/"

echo "[INFO] Project root : $ROOT"
echo "[INFO] Backend dir  : $BACKEND"

if [[ ! -d "$BACKEND" ]]; then
  echo "[ERROR] Missing backend directory: $BACKEND"
  pause
  exit 1
fi

if [[ ! -f "$BACKEND/app.py" ]]; then
  echo "[ERROR] Missing backend/app.py"
  pause
  exit 1
fi

# Prefer macOS system Python to avoid Conda hijacking python3.
SYS_PY=""
if [[ -x "/usr/bin/python3" ]]; then
  SYS_PY="/usr/bin/python3"
elif command -v python3 >/dev/null 2>&1; then
  SYS_PY="$(command -v python3)"
else
  echo "[ERROR] Python 3 not found. Install Python 3 first."
  pause
  exit 1
fi

echo "[INFO] System Python: $SYS_PY"
"$SYS_PY" -c "import sys; print('[INFO] Version      :', sys.version.split()[0]); print('[INFO] Executable   :', sys.executable)"

# Create venv if missing.
if [[ ! -x "$VENV_PY" ]]; then
  echo "[WARN] .venv not found. Creating venv at: $VENV_DIR"
  "$SYS_PY" -m venv "$VENV_DIR"
fi

echo "[INFO] Venv Python  : $VENV_PY"
"$VENV_PY" -c "import sys; print('[INFO] Venv version :', sys.version.split()[0]); print('[INFO] Venv exe     :', sys.executable)"

# Ensure pip works in venv.
"$VENV_PY" -m pip --version >/dev/null 2>&1 || {
  echo "[ERROR] pip is not available in the venv."
  echo "[ERROR] Try: $VENV_PY -m ensurepip --upgrade"
  pause
  exit 1
}

# Install requirements into venv.
REQ="$BACKEND/requirements.txt"
if [[ -f "$REQ" ]]; then
  echo "[INFO] Installing backend dependencies from: $REQ"
  "$VENV_PY" -m pip install -r "$REQ"
else
  echo "[WARN] No backend/requirements.txt found. Skipping."
fi

# Your app imports OpenAI SDK at import-time (AI tutor).
echo "[INFO] Ensuring openai SDK is installed..."
"$VENV_PY" -m pip install openai

# Import check with traceback (actionable errors)
echo "[INFO] Import check (backend.app)..."
"$VENV_PY" -c "import traceback
try:
  import backend.app
  print('backend.app import ok')
except Exception:
  traceback.print_exc()
  raise"

# Optional data existence check
if [[ ! -f "$BACKEND/data/passages.json" ]]; then
  echo "[WARN] Missing $BACKEND/data/passages.json"
  echo "[WARN] If your app needs it, copy your passages.json there."
fi

# Port check (best effort)
if command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[ERROR] Port $PORT is already in use."
    echo "[ERROR] Stop the other process or change PORT in run.command."
    pause
    exit 1
  fi
fi

echo ""
echo "[INFO] Starting server: $URL"
echo "[INFO] Press Ctrl+C to stop."
echo ""

( sleep 1; open "$URL" ) >/dev/null 2>&1 || true

cd "$ROOT"
exec "$VENV_UVICORN" backend.app:app --reload --host "$HOST" --port "$PORT"
