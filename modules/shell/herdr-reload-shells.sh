# herdr-reload-shells — batch reload zsh config in herdr shell panes.
#
# After a darwin-rebuild / plugin change, existing panes keep the old shell.
# This finds every pane whose foreground process is a bare zsh (prompt),
# sends C-c (discards any half-typed line) and runs `exec zsh` there.
# Panes running nvim / agents / other programs are skipped (would eat the text).
#
# Installed onto PATH via writeShellScriptBin in modules/shell/default.nix.
# The wrapper shebang is nixpkgs bash (>=5), so mapfile is safe here.
#
# Usage:
#   herdr-reload-shells            # reload all shell panes
#   herdr-reload-shells w5:p8      # only specific pane id(s)
#   herdr-reload-shells --dry-run  # show what would happen, change nothing
set -uo pipefail

command -v herdr >/dev/null 2>&1 || { echo "herdr not found" >&2; exit 1; }

dry=0
panes=()
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry=1 ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) panes+=("$arg") ;;
  esac
done

# Discover pane ids if none given.
if [[ ${#panes[@]} -eq 0 ]]; then
  mapfile -t panes < <(
    herdr pane list 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for p in d["result"]["panes"]:
        print(p["pane_id"])
except Exception:
    pass
'
  )
fi

[[ ${#panes[@]} -eq 0 ]] && { echo "no panes found (is the herdr server running?)" >&2; exit 1; }

for id in "${panes[@]}"; do
  # Foreground process of the pane: reload only bare zsh prompts.
  fg=$(herdr pane process-info --pane "$id" 2>/dev/null | python3 -c '
import json, sys
try:
    procs = json.load(sys.stdin)["result"]["process_info"]["foreground_processes"]
    p = procs[0] if procs else {}
    print(p.get("argv0") or (p.get("argv") or ["?"])[0])
except Exception:
    print("?")
')
  case "$fg" in
    zsh | -zsh | */zsh)
      if [[ $dry -eq 1 ]]; then
        echo "DRY  $id: would reload (zsh prompt)"
        continue
      fi
      herdr pane send-keys "$id" C-c >/dev/null 2>&1 || true
      sleep 0.2
      if herdr pane run "$id" 'exec zsh' >/dev/null 2>&1; then
        echo "ok   $id: reloaded"
      else
        echo "FAIL $id: send failed"
      fi
      ;;
    *)
      echo "skip $id: foreground is '${fg}' (not a bare zsh prompt)"
      ;;
  esac
done
