#!/usr/bin/env bash
# SSP Cloud / Onyxia VS Code initialization.
# Usage: bash vscode.sh OWNER/REPOSITORY S3_FOLDER
set -euo pipefail

# Save startup output for diagnosing missing installations.
LOG_FILE="${HOME}/sspcloud-init.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
printf '\n========== SSP Cloud initialization: %s ==========\n' "$(date -Is)"
trap 'status=$?; if [ "$status" -ne 0 ]; then echo "Initialization failed (exit $status). Inspect $LOG_FILE" >&2; fi' EXIT

FULL_NAME="${1:?Usage: $0 OWNER/REPOSITORY S3_FOLDER}"
SERV_FOLD="${2:?Usage: $0 OWNER/REPOSITORY S3_FOLDER}"
PROJ_NAME="${FULL_NAME##*/}"
WORK_DIR="/home/onyxia/work/${PROJ_NAME}"
REPO_URL="https://github.com/${FULL_NAME}.git"

step() { printf '\n========== %s ==========\n' "$1"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

# --- CLONE PROJECT ---
step 'Prepare workspace and clone repository'
mkdir -p /home/onyxia/work
# A token, if supplied, is used only for cloning (not echoed).
if [ -n "${GIT_PERSONAL_ACCESS_TOKEN:-}" ]; then
    REPO_URL="https://${GIT_PERSONAL_ACCESS_TOKEN}@github.com/${FULL_NAME}.git"
fi
if [ -d "${WORK_DIR}/.git" ]; then
    echo "Existing repository found: ${WORK_DIR}; updating it with new GitHub commits."
    # --ff-only never resets or overwrites unrelated local work.
    git -C "$WORK_DIR" pull --ff-only || {
        echo "ERROR: Cannot update the existing Git checkout. Check Git credentials and local changes." >&2
        exit 1
    }
elif [ -e "$WORK_DIR" ]; then
    echo "ERROR: ${WORK_DIR} exists but is not a Git checkout." >&2
    exit 1
else
    git clone "$REPO_URL" "$WORK_DIR" || {
        echo "ERROR: Git clone failed. Check repository access and Git credentials." >&2
        exit 1
    }
fi
unset REPO_URL

echo "Workspace available at: $WORK_DIR"

# --- INSTALL TMUX ---
step 'Install tmux'
if ! command -v tmux >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        (sudo -n apt-get update && sudo -n apt-get install -y tmux) || warn "tmux installation failed; continuing."
    else
        warn 'Cannot install tmux: apt-get or passwordless sudo unavailable.'
    fi
else
    echo 'tmux is already installed.'
fi

# --- COPY PROJECT DATA / SUPPORT SCRIPTS FROM S3 ---
step 'Copy S3 files'
if command -v mc >/dev/null 2>&1; then
    if ! mc cp -r "s3/${SERV_FOLD}/${PROJ_NAME}" /home/onyxia/work/; then
        warn "S3 copy failed; continuing with repository files. Check whether installers/data are missing."
    fi
else
    warn "mc is unavailable; skipping S3 copy."
fi
cd "$WORK_DIR"

# Both installers are committed at the ROOT of land-use-coalition.
# install_gams.sh looks for gamslice.txt alongside itself, or (depending on
# its version) in ~/.gamslice. Keep private licenses out of public GitHub.
GAMS_INSTALLER="${WORK_DIR}/install_gams.sh"
VENV_INSTALLER="${WORK_DIR}/setup_venv.sh"
GAMS_BIN_DIR="${HOME}/gams547/gams54.7_linux_x64_64_sfx"

step 'Verify installer files'
for installer in "$GAMS_INSTALLER" "$VENV_INSTALLER"; do
    [ -f "$installer" ] || {
        echo "ERROR: Missing $installer. Check that it was committed and pushed to the cloned branch." >&2
        exit 1
    }
    bash -n "$installer" || {
        echo "ERROR: Invalid Bash syntax in $installer" >&2
        exit 1
    }
done
[ -f "${WORK_DIR}/requirements.txt" ] || {
    echo "ERROR: Missing ${WORK_DIR}/requirements.txt, required by setup_venv.sh." >&2
    exit 1
}

# --- INSTALL GAMS BEFORE THE PYTHON API ---
step 'Install GAMS 54.7'
if [ -x "${GAMS_BIN_DIR}/gams" ]; then
    echo "GAMS already installed at ${GAMS_BIN_DIR}; skipping reinstallation."
else
    (cd "$WORK_DIR" && bash "$GAMS_INSTALLER") || {
        echo 'ERROR: GAMS installation failed. See ~/sspcloud-init.log.' >&2
        exit 1
    }
fi
[ -x "${GAMS_BIN_DIR}/gams" ] || {
    echo "ERROR: GAMS executable still missing: ${GAMS_BIN_DIR}/gams" >&2
    exit 1
}
export PATH="${GAMS_BIN_DIR}:$PATH"

# --- CREATE PYTHON VENV AND INSTALL PROJECT REQUIREMENTS + GAMS API ---
step 'Set up Python virtual environment'
(cd "$WORK_DIR" && bash "$VENV_INSTALLER") || {
    echo 'ERROR: Python environment setup failed. See ~/sspcloud-init.log.' >&2
    exit 1
}
[ -x "${WORK_DIR}/.venv/bin/python" ] || {
    echo "ERROR: Python virtual environment missing: ${WORK_DIR}/.venv/bin/python" >&2
    exit 1
}

# --- INSTALL REQUESTED R PACKAGES IN THE FIRST R LIBRARY ---
step 'Install R packages'
if command -v Rscript >/dev/null 2>&1; then
    # Do not source the project's .Rprofile while preparing the base packages;
    # an active renv bootstrap can otherwise interfere with package installation.
    (cd /tmp && Rscript --vanilla - <<'RSCRIPT'
repos <- "https://cloud.r-project.org"
lib <- .libPaths()[1]
packages <- c("renv", "readr", "dplyr", "tidyr", "tibble", "purrr")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, lib = lib, repos = repos)
}
failed <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(failed)) stop("R packages not installed: ", paste(failed, collapse = ", "))
cat("R packages available in library search path; first library:", lib, "\n")
RSCRIPT
    )
else
    warn 'Rscript not on PATH; skipping R package installation.'
fi

# --- VS CODE SETTINGS ---
step 'Configure VS Code'
SETTINGS_FILE="${HOME}/.local/share/code-server/User/settings.json"
mkdir -p "$(dirname "$SETTINGS_FILE")"
cat > "$SETTINGS_FILE" <<'SETTINGS'
{
  "workbench.panel.defaultLocation": "right",
  "workbench.editor.openSideBySideDirection": "down",
  "editor.rulers": [80, 100, 120],
  "terminal.integrated.cursorStyle": "line",
  "terminal.integrated.cursorBlinking": true,
  "chat.extensionUnification.enabled": false,
  "workbench.colorTheme": "Default Dark Modern",
  "cSpell.enabled": false,
  "r.sessionWatcher": true,
  "r.session.useWebServer": true,
  "r.session.watchGlobalEnvironment": true,
  "r.session.objectLengthLimit": 100,
  "r.session.objectTimeout": 10,
  "r.session.levelOfObjectDetail": "Minimal",
  "r.session.emulateRStudioAPI": false,
  "r.session.data.rowLimit": 3000,
  "r.session.data.pageSize": 200,
  "r.rtermSendDelay": 4,
  "r.lsp.diagnostics": false,
  "flake8.enabled": false,
  "[python]": {"editor.defaultFormatter": "charliermarsh.ruff"},
  "security.workspace.trust.enabled": false,
  "security.workspace.trust.startupPrompt": "never",
  "terminal.integrated.inheritEnv": false,
  "git.defaultCloneDirectory": "~/work",
  "python.testing.pytestEnabled": true,
  "redhat.telemetry.enabled": false,
  "julia.symbolCacheDownload": true,
  "julia.enableTelemetry": false,
  "r.bracketedPaste": true,
  "workbench.secondarySideBar.defaultVisibility": "hidden",
  "workbench.welcomePage.experimentalOnboarding": false
}
SETTINGS
chown onyxia:users "$SETTINGS_FILE" 2>/dev/null || warn 'Could not adjust VS Code settings ownership.'

# --- EXTENSIONS ---
step 'Install VS Code extensions'
if command -v code-server >/dev/null 2>&1; then
    code-server --install-extension oderwat.indent-rainbow || warn "indent-rainbow installation failed"
    code-server --install-extension yzhang.markdown-all-in-one || warn "Markdown extension installation failed"
    code-server --install-extension 3xpo.regionfolding || warn "regionfolding installation failed"
else
    warn "code-server not yet on PATH; skipping extension installation"
fi

# --- COPILOT ---
step 'Install GitHub Copilot'
if command -v code-server >/dev/null 2>&1; then
copilotVersion='1.156.0'
COPILOT_TMP="$(mktemp -d)"
if curl -fL -q --retry 5 \
    "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot/${copilotVersion}/vspackage" \
    -o "${COPILOT_TMP}/copilot.vsix.gz" && \
    gzip -d "${COPILOT_TMP}/copilot.vsix.gz"; then
    code-server --install-extension "${COPILOT_TMP}/copilot.vsix" --force || warn 'Copilot extension installation failed.'
else
    warn 'Copilot extension download failed.'
fi
rm -rf "$COPILOT_TMP"
else
    warn "code-server unavailable; skipping Copilot"
fi

chown -R onyxia:users "$WORK_DIR" 2>/dev/null || warn 'Could not change project ownership.'
echo "Initialization complete. Project ready in $WORK_DIR"

# Quick checks: tmux -V ; test -x ~/gams547/gams54.7_linux_x64_64_sfx/gams ; test -x "$WORK_DIR/.venv/bin/python"
