#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$project_dir/.build/CodexReset.app"
if [[ ! -x "$source_app/Contents/MacOS/CodexReset" ||
      ! -x "$source_app/Contents/MacOS/CodexResetCompanion" ]]; then
  print -u2 'Primeiro compile o app com scripts/build-app.sh.'
  exit 1
fi

applications_dir="$HOME/Applications"
installed_app="$applications_dir/Codex Reset.app"
mkdir -p "$applications_dir"

# Stage the complete signed bundle before replacing a previous installation.
stage_dir="$(mktemp -d "$applications_dir/.codex-reset-install.XXXXXX")"
cleanup() {
  if [[ -d "$stage_dir" ]]; then
    rm -R -- "$stage_dir"
  fi
}
trap cleanup EXIT

staged_app="$stage_dir/Codex Reset.app"
ditto "$source_app" "$staged_app"
codesign --verify --deep --strict "$staged_app"

bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null
}
if [[ "$(bundle_id "$staged_app")" != 'com.arthurbenfica.codexreset' ]]; then
  print -u2 'O bundle compilado não é o Codex Reset esperado.'
  exit 1
fi

if [[ -e "$installed_app" ]]; then
  if [[ "$(bundle_id "$installed_app")" != 'com.arthurbenfica.codexreset' ]]; then
    print -u2 -- "Instalação interrompida: $installed_app pertence a outro aplicativo."
    exit 1
  fi
  mv "$installed_app" "$stage_dir/previous.app"
fi
if ! mv "$staged_app" "$installed_app"; then
  if [[ -d "$stage_dir/previous.app" ]]; then
    mv "$stage_dir/previous.app" "$installed_app"
  fi
  print -u2 'Não foi possível instalar o Codex Reset.'
  exit 1
fi

# Keep the app library pointed at the installed bundle, rather than an old
# development build whose icon may have been registered before it existed.
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
touch "$installed_app"
"$lsregister" -u "$source_app" >/dev/null 2>&1 || true
"$lsregister" -f "$installed_app"

label='com.arthurbenfica.codexreset-companion'
agent_dir="$HOME/Library/LaunchAgents"
agent_file="$agent_dir/$label.plist"
helper="$installed_app/Contents/MacOS/CodexResetCompanion"
mkdir -p "$agent_dir"
python3 - "$agent_file" "$label" "$helper" "$installed_app" <<'PY'
from pathlib import Path
import plistlib
import sys

destination, label, helper, app = sys.argv[1:]
payload = {
    "Label": label,
    "ProgramArguments": [helper, app],
    "RunAtLoad": True,
    "KeepAlive": True,
    "ProcessType": "Background",
    "LimitLoadToSessionType": "Aqua",
}
Path(destination).write_bytes(plistlib.dumps(payload))
PY

domain="gui/$(id -u)"
launchctl bootout "$domain" "$agent_file" >/dev/null 2>&1 || true
launchctl bootstrap "$domain" "$agent_file"
print -r -- "Aplicativo instalado: $installed_app"
print -r -- "Início automático instalado: $agent_file"
