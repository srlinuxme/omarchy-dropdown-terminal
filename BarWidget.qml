import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Bar indicator + toggle for the SUPER+GRAVE dropdown terminal. Install.sh
// wires the keybind and window rule; this widget only needs to know the
// special workspace name to show state, and the CLI path to toggle it.
//
// States:
//   - invisible: no dropdown session has been started yet (nothing to show)
//   - dim (bar foreground colour): session exists but is hidden
//   - lit (accent colour): the dropdown is currently visible/revealed
//
// Detection is event-driven via Quickshell.Hyprland's live workspace/monitor
// model (the same API Omarchy's own Workspaces.qml uses): `openwindow` /
// `closewindow` / `activespecial` events refresh just the affected model
// instead of polling.
BarWidget {
  id: root
  moduleName: "srlinux.dropterm"

  readonly property string wsName: "special:dropterm"
  readonly property string toggleCmd: "~/.local/bin/omarchy-dropterm toggle"

  function findWorkspace() {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].name === root.wsName) return values[i]
    }
    return null
  }

  readonly property var workspace: findWorkspace()
  // A special workspace object only exists in the model while it has at
  // least one window (Hyprland destroys it once empty), so its mere
  // presence already means the dropdown session is alive.
  readonly property bool sessionExists: workspace !== null

  // Quickshell's HyprlandMonitor doesn't expose a typed "active special
  // workspace" property, but its lastIpcObject mirrors `hyprctl monitors -j`,
  // which does (the monitor currently showing this special workspace, if
  // any). Compared against every monitor since a special workspace can only
  // be revealed on the one it lives on.
  function monitorShowsDropterm(monitor) {
    if (!monitor || !monitor.lastIpcObject) return false
    var special = monitor.lastIpcObject.specialWorkspace
    return !!special && special.name === root.wsName
  }

  readonly property bool revealed: {
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < monitors.length; i++) {
      if (monitorShowsDropterm(monitors[i])) return true
    }
    return false
  }

  function toggle() {
    if (root.bar) root.bar.run(root.toggleCmd)
  }

  // The events that can change sessionExists/revealed: a window
  // opening/closing (session created/destroyed) or a special workspace being
  // shown/hidden on any monitor. Nothing else needs to trigger a refresh.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      if (name === "openwindow" || name === "closewindow") {
        Hyprland.refreshWorkspaces()
        Hyprland.refreshMonitors()
      } else if (name === "activespecial" || name === "focusedmon") {
        Hyprland.refreshMonitors()
      }
    }
  }

  visible: sessionExists
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf120"
    active: root.revealed
    tooltipText: root.revealed ? "Dropdown terminal (shown)" : "Dropdown terminal (hidden)"
    onPressed: root.toggle()
  }
}
