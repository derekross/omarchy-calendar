import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar pill showing the current or next timed event today. Left click opens the
// agenda, right click syncs now, middle click re-reads khal.
BarWidget {
  id: root
  moduleName: "derekross.calendar"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("derekross.calendar") : null

  readonly property int maxTitleLength: Model.clampInt(setting("maxTitleLength", 24), 24, 0, 120)
  readonly property bool showWhenIdle: setting("showWhenIdle", true) !== false

  property double now: Date.now()
  readonly property var upcoming: service ? Model.nextEvent(service.events, now) : null
  readonly property string label: upcoming
    ? "󰃭  " + Model.barLabel(upcoming, now, service.use24h, maxTitleLength)
    : (showWhenIdle ? "󰃭" : "")

  // The service owns settings so notifications work without the widget;
  // forward this entry's shell.json values whenever they change.
  function pushSettings() {
    if (service && typeof service.configure === "function") service.configure(settings)
  }
  onServiceChanged: {
    pushSettings()
    injectPanel()
  }
  onSettingsChanged: {
    pushSettings()
    injectPanel()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }
  onBarChanged: injectPanel()

  // Shape contract for the bar's panel routing: open/close/opened on the root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: root.now = Date.now()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "󰃭" : root.label
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: ""

    onPressed: function(b) {
      if (!root.service) return
      if (b === Qt.RightButton) root.service.sync()
      else if (b === Qt.MiddleButton) root.service.refresh()
      else root.togglePanel()
    }
  }
}
