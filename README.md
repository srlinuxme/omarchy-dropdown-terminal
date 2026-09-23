# Omarchy Dropdown Terminal (srlinux.dropterm)

A Guake/Quake-style dropdown terminal for [Omarchy](https://omarchy.org/):
press **SUPER + GRAVE** (the key below ESC) and a terminal slides down,
docked flush against the top bar. Press again and it hides. The session is
**persistent** — shell, scrollback, running commands and tabs all survive
every hide/show, and even the terminal window being force-closed.

## Features

- **Persistent session** — powered by a dedicated `tmux` session (`dropterm`)
  the dropdown window attaches to. Hiding or even killing the terminal window
  never kills your session; only `tmux kill-session` or logout does. The next
  toggle reattaches to the exact same state.
- **Tabs** — each tab is its own tmux window (own shell, cwd, scrollback,
  running programs) inside the same persistent session:
  - `Alt+T` new tab, `Alt+W` close tab
  - `Alt+Left` / `Alt+Right` switch tabs
  - `Alt+1`..`Alt+9` jump to tab N
  - No tmux prefix key needed — bindings are direct (`-n`).
  - A tab strip at the bottom of the terminal shows every open tab,
    left-aligned.
  - Ships its own `tmux.conf`, loaded only for this session — your personal
    `~/.tmux.conf` is never touched.
- **Docked to the bar, not floating free** — sized ~80% width / 45% height,
  and positioned flush against the bottom edge of the Omarchy top bar (no
  gap), classic dropdown-terminal look.
- **Genuinely hidden, not minimized** — lives on its own named Hyprland
  special workspace (`special:dropterm`), so it's fully absent from
  alt-tab/window lists while hidden, not just out of view.
- **Terminal-aware clipboard** — tagged so Omarchy's universal SUPER+C/V/X
  shortcuts send the terminal-appropriate key sequences (`Shift+Insert` etc.)
  instead of the generic app ones.
- **Bar indicator** — an icon next to the clock: invisible when no session
  exists yet, dim when the session is hidden, lit (accent colour) when
  shown. Click to toggle. Event-driven (Hyprland IPC), no polling.
- **Multi-monitor aware** — the toggle always targets the monitor the window
  actually lives on, working around a known Hyprland quirk where
  `togglespecialworkspace` can silently no-op if focus drifted to a
  different monitor between presses.

## Requirements

- Omarchy on Hyprland (uses the Lua dispatch engine, `hl.dsp.*` /
  `o.window` / `o.bind` — not the legacy `windowrulev2`/`bind=` syntax).
- `alacritty` and `tmux`.
- `jq` (used by the CLI to query `hyprctl -j` output).

## Install

```bash
omarchy plugin add https://github.com/srlinuxme/omarchy-dropdown-terminal.git --enable
cd ~/.config/omarchy/plugins/srlinux.dropterm
./install.sh
```

`omarchy plugin add` puts the files on disk and adds the bar widget;
`./install.sh` does the part a shell plugin cannot do for itself: writes the
window rule and keybind into your Hyprland config, and symlinks the CLI into
`~/.local/bin`.

What `install.sh` does:

1. Symlinks `bin/omarchy-dropterm` into `~/.local/bin/omarchy-dropterm`.
2. Writes a marker-anchored window-rule block into
   `~/.config/hypr/hyprland.lua` (the `DropTerm` float/size/position/tag
   rule).
3. Writes a marker-anchored keybind block into `~/.config/hypr/bindings.lua`:
   `SUPER + code:49` (physical key below ESC, so it fires regardless of
   keyboard layout/variant) → `omarchy-dropterm toggle`.
4. Reloads Hyprland.

Re-running `install.sh` is safe — it refreshes the blocks in place instead of
duplicating them.

### Uninstall

```bash
cd ~/.config/omarchy/plugins/srlinux.dropterm
./install.sh uninstall
omarchy plugin remove srlinux.dropterm
```

Removes the keybind and window-rule blocks, the `~/.local/bin` symlink, kills
the `dropterm` tmux session and any live `DropTerm` window, and reloads
Hyprland.

## Usage

| Key / action | Effect |
|---|---|
| `SUPER + GRAVE` | Toggle the dropdown terminal |
| Bar icon click | Toggle |
| `Alt + T` (inside the dropdown) | New tab |
| `Alt + W` | Close current tab |
| `Alt + Left` / `Alt + Right` | Previous / next tab |
| `Alt + 1`..`9` | Jump to tab N |

CLI (`~/.local/bin/omarchy-dropterm`, once installed):

```
omarchy-dropterm toggle   # show if hidden, hide if shown, spawn if not running (default)
omarchy-dropterm open     # show it (spawning first if needed); no-op if already shown
omarchy-dropterm close    # hide it if shown; no-op otherwise
```

## How it works

```
SUPER+GRAVE -> omarchy-dropterm toggle
                 |-- window doesn't exist yet?
                 |     '-- hyprctl dispatch hl.dsp.exec_cmd(alacritty --class DropTerm -e
                 |           bash -c 'tmux attach -t dropterm || tmux -f dropterm.tmux.conf new -s dropterm')
                 |         (the DropTerm window rule then silently routes it to
                 |          special:dropterm as soon as it maps)
                 '-- hyprctl dispatch hl.dsp.focus({monitor=...})   (pin focus to the
                     hyprctl dispatch hl.dsp.workspace.toggle_special('dropterm')  monitor the
                                                                                    window is on)

Bar widget (BarWidget.qml)
   '-- subscribes to Hyprland's Quickshell IPC model (openwindow / closewindow /
         activespecial events) to show session-exists / revealed state, no polling
```

The tmux session is the actual persistence layer: the Alacritty window is
just a disposable view onto it. Killing the window, hiding it via the special
workspace, or even a Hyprland crash all leave the tmux session running; the
next `toggle`/`open` reattaches to it exactly as it was.

## Known limitations

- **One dropdown at a time** — by design, it's a single Quake-style toggle.
- **Wayland/Hyprland only.**
- **Special-workspace animation is global** — Hyprland only supports one
  slide direction/animation for *all* special workspaces on a monitor (there
  is no per-workspace override in the engine). This plugin does not touch
  your animation config, so the dropdown uses whatever `specialWorkspace`
  animation you already have configured — which also applies to Omarchy's
  own `SUPER + S` scratchpad.
- `install.sh` refuses to touch `hyprland.lua` / `bindings.lua` if either is
  missing, unreadable, or implausibly large (>1 MiB), to avoid corrupting an
  unexpected file.

## License

MIT — see [LICENSE](LICENSE).
