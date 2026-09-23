#!/usr/bin/bash
# install.sh -- installer/uninstaller for srlinux.dropterm.
#
# Writes two marker-anchored blocks (one in ~/.config/hypr/hyprland.lua for
# the window rule, one in ~/.config/hypr/bindings.lua for the SUPER+GRAVE
# keybind), symlinks the CLI into ~/.local/bin, and reloads Hyprland.
# Re-running is safe: it refreshes the blocks in place instead of duplicating
# them. `./install.sh uninstall` removes every trace.
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPRLAND_LUA="$HYPR_DIR/hyprland.lua"
BINDINGS_LUA="$HYPR_DIR/bindings.lua"
BIN_DIR="$HOME/.local/bin"
CLI_LINK="$BIN_DIR/omarchy-dropterm"
CLI_TARGET="$SCRIPT_DIR/bin/omarchy-dropterm"

WINDOW_MARK_BEGIN="-- >>> srlinux.dropterm window rule (managed, do not edit by hand) >>>"
WINDOW_MARK_END="-- <<< srlinux.dropterm window rule <<<"
BIND_MARK_BEGIN="-- >>> srlinux.dropterm keybind (managed, do not edit by hand) >>>"
BIND_MARK_END="-- <<< srlinux.dropterm keybind <<<"

fail() {
  echo "install.sh: $*" >&2
  exit 1
}

# Refuses to touch a config file it cannot safely read/replace: missing,
# unreadable, or implausibly large (>1 MiB, suggesting it isn't a normal
# hand-edited Hyprland config) all abort instead of risking data loss.
guard_file() {
  local f="$1"
  [ -f "$f" ] || fail "$f not found -- is this an Omarchy Hyprland config?"
  [ -r "$f" ] || fail "$f is not readable"
  local size
  size=$(stat -c '%s' "$f" 2>/dev/null || echo 0)
  [ "$size" -le 1048576 ] || fail "$f is unexpectedly large (>1MiB), refusing to touch it"
}

# Replace the block between BEGIN/END markers with $2's content, appending a
# fresh block at the end of the file if the markers aren't present yet.
upsert_block() {
  local file="$1" begin="$2" end="$3" content="$4"
  local tmp
  tmp="$(mktemp)"
  if grep -qF -- "$begin" "$file"; then
    awk -v b="$begin" -v e="$end" -v c="$content" '
      $0==b { print c; skip=1; next }
      $0==e { skip=0; next }
      skip { next }
      { print }
    ' "$file" >"$tmp"
  else
    cp -- "$file" "$tmp"
    printf '\n%s\n' "$content" >>"$tmp"
  fi
  mv -- "$tmp" "$file"
}

remove_block() {
  local file="$1" begin="$2" end="$3"
  [ -f "$file" ] || return 0
  grep -qF -- "$begin" "$file" || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0==b { skip=1; next }
    $0==e { skip=0; next }
    skip { next }
    { print }
  ' "$file" >"$tmp"
  mv -- "$tmp" "$file"
}

do_install() {
  guard_file "$HYPRLAND_LUA"
  guard_file "$BINDINGS_LUA"

  mkdir -p "$BIN_DIR"
  ln -sf "$CLI_TARGET" "$CLI_LINK"
  chmod +x "$CLI_TARGET"

  local window_block bind_block
  window_block=$(cat <<LUA
$WINDOW_MARK_BEGIN
-- Dropdown terminal: float, sized ~80% width / 45% height, docked flush
-- against the top bar (y=0 in monitor-local coords, which already excludes
-- the bar's reserved area), slightly transparent -- classic Guake/Quake
-- look. It always opens onto its own hidden special workspace so the CLI
-- never has to race the window's mapping.
--
-- NOTE: deliberately no \`pin = true\`. Pinning keeps a window visible on
-- every workspace regardless of switches -- which defeats hiding it via the
-- special workspace entirely (toggling would dim/undim the desktop, but the
-- pinned window itself would never disappear).
--
-- \`tag = "+terminal"\` opts this window into Omarchy's terminal tag (see
-- default/hypr/apps/terminals.lua), which only auto-tags a fixed list of
-- terminal classes/app-ids. Since DropTerm is a custom class (needed for the
-- rules above), it wouldn't otherwise get that tag -- and SUPER+V/C/X
-- (default/hypr/bindings/clipboard.lua) use it to send Shift+Insert instead
-- of Ctrl+V/C/X to terminal windows.
o.window("DropTerm", {
  float = true,
  size = { "(monitor_w*0.8)", "(monitor_h*0.45)" },
  move = { "(monitor_w*0.1)", "0" },
  opacity = "0.95 0.95",
  tag = "+terminal",
  workspace = "special:dropterm silent",
})
$WINDOW_MARK_END
LUA
)
  upsert_block "$HYPRLAND_LUA" "$WINDOW_MARK_BEGIN" "$WINDOW_MARK_END" "$window_block"

  bind_block=$(cat <<LUA
$BIND_MARK_BEGIN
-- Dropdown terminal (Guake/Quake-style): toggle a persistent tmux-backed
-- terminal on a hidden special workspace. State survives hide/show and even
-- closing the window, since the shell lives inside a detached tmux session.
-- Bound by physical keycode (49 = TLDE, the key below ESC) rather than by
-- keysym: with kb_variants like "intl" that key can produce dead_grave (for
-- accents) instead of the plain "grave" keysym, so a name-based bind would
-- never fire. code:49 matches the physical key regardless of what it types.
o.bind("SUPER + code:49", "Toggle dropdown terminal", "$CLI_LINK toggle")
$BIND_MARK_END
LUA
)
  upsert_block "$BINDINGS_LUA" "$BIND_MARK_BEGIN" "$BIND_MARK_END" "$bind_block"

  if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null 2>&1 || true
  fi

  echo "srlinux.dropterm installed. Press SUPER + GRAVE (the key below ESC)."
}

do_uninstall() {
  remove_block "$HYPRLAND_LUA" "$WINDOW_MARK_BEGIN" "$WINDOW_MARK_END"
  remove_block "$BINDINGS_LUA" "$BIND_MARK_BEGIN" "$BIND_MARK_END"
  [ -L "$CLI_LINK" ] && rm -f "$CLI_LINK"

  if command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t dropterm >/dev/null 2>&1 || true
  fi
  if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    pids=$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class=="DropTerm") | .pid' 2>/dev/null || true)
    [ -n "$pids" ] && kill $pids >/dev/null 2>&1 || true
    hyprctl reload >/dev/null 2>&1 || true
  fi

  echo "srlinux.dropterm uninstalled."
}

case "${1:-install}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  *) fail "usage: $0 [install|uninstall]" ;;
esac
