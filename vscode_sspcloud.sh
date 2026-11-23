#!/bin/bash
#
# setup_venv.sh - Create a Python virtual environment with all project
#                 dependencies including the GAMS Python API.
#
# Prerequisites:
#   - GAMS 54.7 already installed (run ./install_gams.sh first if not)
#   - Python 3.10+ available
#
# Usage:
#   chmod +x setup_venv.sh
#   ./setup_venv.sh
#

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
VENV_DIR=".venv"
GAMS_VERSION="54.7"
GAMS_INSTALL_DIR="${HOME}/gams547"
GAMS_BIN_DIR="${GAMS_INSTALL_DIR}/gams54.7_linux_x64_64_sfx"

GAMS_PIP_VERSION="54.7"     # pip package 'gams' version matching GAMS 54.7

# ─── Step 1: Check prerequisites ─────────────────────────────────────────────
echo "=============================================="
echo "  Project Python Environment Setup"
echo "=============================================="

# Check Python
PYTHON_BIN=""
for candidate in python3.12 python3.11 python3.10 python3 python; do
    if command -v "$candidate" &>/dev/null; then
        ver=$("$candidate" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        major="${ver%%.*}"
        minor="${ver##*.}"
        if [ "$major" -ge 3 ] && [ "$minor" -ge 10 ]; then
            PYTHON_BIN="$candidate"
            break
        fi
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo "ERROR: Python 3.10+ not found."
    echo "  Install Python 3.10+ and try again."
    exit 1
fi

echo ""
echo "[1/5] Python: $PYTHON_BIN ($($PYTHON_BIN --version 2>&1))"

# Check that ensurepip is available (required by venv)
if ! "$PYTHON_BIN" -m ensurepip --version &>/dev/null; then
    echo ""
    echo "  ensurepip is not available. Attempting to install python3-venv..."
    if command -v apt-get &>/dev/null; then
        PYTHON_VER_FULL=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        PKG="python${PYTHON_VER_FULL}-venv"
        if sudo apt-get install -y "$PKG" 2>/dev/null; then
            echo "  Installed $PKG."
        else
            echo "  ERROR: Failed to install $PKG automatically."
            echo "  Please run manually:  sudo apt install $PKG"
            exit 1
        fi
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y python3-venv
        echo "  Installed python3-venv."
    elif command -v yum &>/dev/null; then
        sudo yum install -y python3-venv
        echo "  Installed python3-venv."
    else
        echo "  ERROR: ensurepip is not available and no known package manager found."
        echo "  Install the python3-venv package for your system manually."
        exit 1
    fi
fi

# Check GAMS installation
if [ ! -d "$GAMS_BIN_DIR" ]; then
    echo ""
    echo "WARNING: GAMS binary directory not found at:"
    echo "  $GAMS_BIN_DIR"
    echo ""
    echo "  Run './install_gams.sh' first, or adjust GAMS_BIN_DIR in this script."
    echo "  The GAMS Python API will be installed but may not work until GAMS is available."
else
    echo "[2/5] GAMS found at: $GAMS_BIN_DIR"
fi

# ─── Step 2: Create virtual environment ──────────────────────────────────────
echo ""
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
    echo "[3/5] Virtual environment already exists at $VENV_DIR. Activating it..."
    source "$VENV_DIR/bin/activate"
else
    if [ -d "$VENV_DIR" ]; then
        echo "[3/5] Existing $VENV_DIR found but incomplete. Removing and recreating..."
        rm -rf "$VENV_DIR"
    fi
    echo "[3/5] Creating virtual environment at $VENV_DIR..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    echo "  Virtual environment created."
fi

# ─── Step 3: Upgrade pip ─────────────────────────────────────────────────────
echo ""
echo "[4/5] Upgrading pip..."
pip install --quiet --upgrade pip

# ─── Step 4: Install Python dependencies ─────────────────────────────────────
echo ""
echo "  Installing project requirements from requirements.txt..."
pip install --quiet -r requirements.txt
echo "  Project requirements installed."

echo ""
echo "  Installing GAMS Python API (gams==${GAMS_PIP_VERSION})..."
pip install --quiet "gamsapi==${GAMS_PIP_VERSION}"
echo "  GAMS API installed."

# ─── Step 5: Verify ──────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Verification"
echo "=============================================="

echo ""
echo "  Python packages:"
python -c "
import importlib.metadata as md
for pkg in ['gams', 'numpy', 'pandas', 'matplotlib', 'seaborn']:
    try:
        v = md.version(pkg)
        print(f'    {pkg}=={v}')
    except md.PackageNotFoundError:
        print(f'    {pkg} NOT INSTALLED')
"

echo ""
if [ -d "$GAMS_BIN_DIR" ]; then
    # Add GAMS to PATH for this session
    export PATH="${GAMS_BIN_DIR}:$PATH"
    
    echo "  GAMS binary:"
    if command -v gams &>/dev/null; then
        echo "    gams: $(gams --version 2>&1 | head -1)"
    else
        echo "    WARNING: 'gams' not found on PATH despite directory existing."
    fi
    
    if command -v gdxdump &>/dev/null; then
        echo "    gdxdump: $(which gdxdump)"
    else
        echo "    WARNING: 'gdxdump' not found on PATH."
    fi
else
    echo "  GAMS binary: NOT AVAILABLE (skipping verification)"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Setup complete!"
echo "=============================================="
echo ""
echo "  To use this environment in future sessions:"
echo ""
echo "    source ${VENV_DIR}/bin/activate"
echo ""
echo "  To also make GAMS tools (gdxdump, etc.) available:"
echo ""
echo "    export PATH=\"${GAMS_BIN_DIR}:\$PATH\""
echo ""
echo "  Or add both lines to your ~/.bashrc / ~/.zshrc for permanence."
echo ""
echo "  IMPORTANT: Before running GAMS models, make sure these"
echo "  input files are available (e.g. in the Model/ directory):"
echo ""
echo "    - MACMAP_Inputs.gdx"
echo "    - SCC.gdx"
echo ""
echo "  These are not tracked in git and must be loaded manually."
echo ""
echo "=============================================="