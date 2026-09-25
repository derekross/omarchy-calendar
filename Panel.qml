import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "ClockModel.js" as ClockModel

// The calendar popup: Omarchy's clock panel (hero date, year and life bars,
// month grid with ISO weeks) with khal events worked in. Days with events
// carry a dot per calendar; the agenda underneath follows the chosen day,
// and with nothing chosen it shows the days ahead.
//
// The clock sections are adapted from Omarchy's built-in clock
// (shell/plugins/panels/clock/Panel.qml, MIT license).
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against, and the service that reads khal.
Panel {
  id: root
  moduleName: "derekross.calendar"
  manageIpc: false

  property var anchorItem: null
  property var service: null

  // The bar tracks the widget mounted in its slot, not this nested panel, so
  // everything the bar identifies a panel by has to be that widget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: ClockModel.keyForDate(today)
  property double now: Date.now()

  // The month on screen.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // The day picked in the grid, as a "yyyy-MM-dd" key. Empty means nothing
  // was picked: the agenda then shows today and the days after it.
  property string selectedKey: ""
  readonly property bool selectedIsToday: selectedKey === "" || selectedKey === todayKey
  readonly property double selectedMs: {
    if (selectedKey === "") return Model.startOfDay(now)
    var p = selectedKey.split("-")
    return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10)).getTime()
  }
  readonly property int selectedYear: new Date(selectedMs).getFullYear()
  readonly property int selectedMonth: new Date(selectedMs).getMonth()

  // Pinned to today, not to the month being browsed.
  readonly property real yearDone: ClockModel.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: ClockModel.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori: double-tapping the year bar asks for a birth year and a
  // life expectancy, and a second bar tracks one against the other.
  readonly property int birthYear: ClockModel.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: ClockModel.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: ClockModel.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: ClockModel.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: ClockModel.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day. Clicking the grid's
  // "W" heading writes the choice back to shell.json.
  readonly property int weekStart: ClockModel.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(ClockModel.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: ClockModel.weekdayOrder(weekStart)
  readonly property var weeks: ClockModel.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // ---- Events. The grid reads the month on screen; the agenda reads the
  //      upcoming list, or the chosen day's month. Until a month has loaded,
  //      the upcoming list stands in for the current one.
  readonly property var viewEvents: {
    if (!service) return []
    var loaded = service.monthEvents[Model.monthKey(viewYear, viewMonth)]
    if (loaded) return loaded.events
    return viewingCurrentMonth ? service.events : []
  }
  readonly property var dayDots: Model.eventsByDay(viewEvents)
  readonly property var selectedMonthEvents: {
    var loaded = service ? service.monthEvents[Model.monthKey(selectedYear, selectedMonth)] : null
    return loaded ? loaded.events : null
  }
  readonly property bool dayLoading: !selectedIsToday && !selectedMonthEvents
  readonly property var rows: {
    if (!service) return []
    if (selectedIsToday) return Model.agendaRows(service.events, now)
    return Model.dayAgendaRows(selectedMonthEvents || [], selectedMs, now)
  }
  readonly property bool use24h: service ? service.use24h : true

  // One event is expanded at a time; its key is uid + start. The keyboard
  // cursor (up/down) is tracked by key too, so it survives refreshes.
  property string expandedKey: ""
  property string cursorKey: ""
  readonly property var agendaEvents: rows.filter(function(r) { return r.kind === "event" }).map(function(r) { return r.event })

  // Guarded so the widget renders before the bar is injected.
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(contentForeground, 1.4)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  readonly property string statusText: {
    if (!service) return "Calendar service is not running. Enable the plugin with omarchy plugin enable derekross.calendar."
    if (!service.khalAvailable) return "khal is not installed or not configured. See the plugin README for setup."
    if (service.lastError) return service.lastError
    return ""
  }

  readonly property string emptyText: {
    if (statusText !== "") return statusText
    if (selectedIsToday) return "Nothing scheduled in the next " + (service ? service.agendaDays : 7) + " days."
    return dayLoading ? "Loading…" : "Nothing scheduled."
  }

  readonly property string syncText: {
    if (!service) return ""
    if (service.syncing) return "Syncing…"
    if (!service.syncAvailable) return "Sync command not found"
    if (service.syncError) return service.syncError
    if (service.lastSync > 0) return "Synced " + Model.formatClock(service.lastSync, use24h)
    return ""
  }

  function open() {
    refresh()
    if (service) service.refresh()
    root.controller.show()
    // Set after showing: showing hands the popout coordinator over, which
    // closes whichever panel was open, and that close clears the flag.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLife) root.cancelEditingLife()
    expandedKey = ""
    cursorKey = ""
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.now = Date.now()
    root.goToToday()
  }

  // Ask the service for the months the panel shows. Cheap when cached.
  function requestMonths() {
    if (!service || !root.opened) return
    service.loadMonth(viewYear, viewMonth)
    if (!selectedIsToday) service.loadMonth(selectedYear, selectedMonth)
  }

  onViewYearChanged: Qt.callLater(requestMonths)
  onViewMonthChanged: Qt.callLater(requestMonths)
  onSelectedKeyChanged: Qt.callLater(requestMonths)
  onOpenedChanged: if (opened) Qt.callLater(requestMonths)

  Connections {
    target: root.service
    function onRangeGenerationChanged() { root.requestMonths() }
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    setSelected("")
  }

  function setSelected(key) {
    if (key === root.todayKey) key = ""
    if (key === root.selectedKey) return
    root.selectedKey = key
    root.expandedKey = ""
    root.cursorKey = ""
  }

  // Picking a day outside the month on screen brings its month into view.
  function selectDay(day) {
    if (!day) return
    root.viewYear = day.year
    root.viewMonth = day.month
    setSelected(day.key)
  }

  function moveDay(delta) {
    var d = new Date(root.selectedMs)
    d.setDate(d.getDate() + delta)
    selectDay({ key: ClockModel.keyForDate(d), year: d.getFullYear(), month: d.getMonth() })
  }

  function moveMonth(delta) {
    var next = ClockModel.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. The host
  // widget builds its own entry when the label format is cycled, so it has
  // to be kept in step or it would write this key straight back out.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = ClockModel.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: ClockModel.weekStartSettingName(next) })
  }

  function toggleWeekStart() {
    setWeekStart(ClockModel.toggledWeekStart(root.weekStart))
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = ClockModel.parseBirthYear(bornField.text, today.getFullYear())
    var span = ClockModel.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  // Scroll so `item` (a row inside the panel) is fully visible, top first.
  function ensureVisible(item) {
    if (!item || !scroller) return
    var y = item.mapToItem(calendarColumn, 0, 0).y
    var maxY = Math.max(0, scroller.contentHeight - scroller.height)
    if (y < scroller.contentY) scroller.contentY = Math.max(0, y - Style.space(4))
    else if (y + item.height > scroller.contentY + scroller.height)
      scroller.contentY = Math.min(maxY, Math.min(y - Style.space(4), y + item.height - scroller.height + Style.space(4)))
  }

  function moveCursor(delta) {
    var list = agendaEvents
    if (list.length === 0) return
    var index = -1
    for (var i = 0; i < list.length; i++) if (list[i].key === cursorKey) index = i
    index = index === -1 ? (delta > 0 ? 0 : list.length - 1) : Math.max(0, Math.min(list.length - 1, index + delta))
    cursorKey = list[index].key
  }

  function focusedEvent() {
    var key = cursorKey || expandedKey
    var list = agendaEvents
    for (var i = 0; i < list.length; i++) if (list[i].key === key) return list[i]
    return null
  }

  // "m" joins and "d" gets directions for the event under the cursor.
  function actOnFocused(action) {
    var ev = focusedEvent()
    if (!ev || !service) return
    service.loadDetails(ev.uid)
    var info = service.details(ev)
    if (action === "join" && info.meeting) openLink(info.meeting.url)
    else if (action === "directions" && info.directions) openLink(info.directions)
    else if (expandedKey !== ev.key) toggleExpanded(ev)
  }

  function toggleExpanded(ev) {
    if (!ev) return
    if (expandedKey === ev.key) {
      expandedKey = ""
      return
    }
    expandedKey = ev.key
    if (service) service.loadDetails(ev.uid)
  }

  // Opening a link hands focus to the browser or meeting app, so the
  // popup gets out of the way.
  function openLink(url) {
    if (!service || !url) return
    service.openUrl(url)
    close()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.now = Date.now()
      if (ClockModel.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth && root.selectedKey === ""
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      // Left/right (and h/l) walk the days; up/down (and j/k) walk the
      // events of the agenda underneath.
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveDay(dx)
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: { var ev = root.focusedEvent(); if (ev) root.toggleExpanded(ev) }
      onCloseRequested: {
        if (root.expandedKey !== "") root.expandedKey = ""
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "s" || t === "S") { if (root.service) root.service.sync() }
        else if (t === "r" || t === "R") { if (root.service) root.service.reload() }
        else if (t === "m" || t === "M") root.actOnFocused("join")
        else if (t === "d" || t === "D") root.actOnFocused("directions")
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid: the popup width is capped to what
          // the screen allows, and the grid should scroll rather than clip.
          width: Math.max(scroller.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth || !root.selectedIsToday
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: dayCell
                      required property var modelData
                      readonly property bool selected: root.selectedKey !== "" && modelData.key === root.selectedKey
                      readonly property var dots: root.dayDots[modelData.key] || []

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. Only a day picked by hand is
                      // filled.
                      color: selected
                        ? Style.selectedFillFor(root.contentForeground, Color.accent)
                        : dayMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: dayCell.dots.length > 0 ? -Style.space(3) : 0
                        text: dayCell.modelData.day
                        color: dayCell.modelData.inMonth
                          ? (dayCell.modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: dayCell.modelData.today || dayCell.selected
                      }

                      // One dot per calendar with events that day.
                      Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(4)
                        spacing: Style.space(3)

                        Repeater {
                          model: dayCell.dots

                          Rectangle {
                            required property var modelData
                            width: Style.space(4)
                            height: width
                            radius: width / 2
                            color: modelData || Color.accent
                            opacity: dayCell.modelData.inMonth ? 1 : 0.4
                          }
                        }
                      }

                      MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDay(dayCell.modelData)
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- Agenda for the chosen day, or the days ahead. Aligned to
          //      the grid's edges like the rails above it.
          Item {
            width: parent.width
            height: agendaColumn.height

            Column {
              id: agendaColumn
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(6)

              PanelSeparator {
                width: parent.width
                foreground: root.contentForeground
              }

              Text {
                visible: root.statusText !== "" || root.agendaEvents.length === 0
                width: parent.width
                topPadding: Style.space(4)
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.emptyText
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                model: root.rows

                Loader {
                  required property var modelData
                  width: agendaColumn.width
                  // A chosen day with nothing on it says so, without an
                  // orphaned heading above the message.
                  active: modelData.kind === "event" || root.agendaEvents.length > 0
                  visible: active
                  sourceComponent: modelData.kind === "day" ? dayHeading : eventRow
                  onLoaded: item.row = modelData
                }
              }

              // Sync status and the sync button close the panel out.
              Item {
                width: parent.width
                height: syncButton.visible ? syncButton.height : syncLabel.implicitHeight

                Text {
                  id: syncLabel
                  anchors.right: syncButton.visible ? syncButton.left : parent.right
                  anchors.rightMargin: syncButton.visible ? Style.space(6) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.syncText
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                PanelActionButton {
                  id: syncButton
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰑐"
                  tooltipText: "Sync now (s)"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  visible: !!root.service && root.service.syncCommand.trim() !== ""
                  onClicked: root.service.sync()
                }
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: dayHeading

    Item {
      property var row: null
      height: headingText.implicitHeight + Style.space(6)

      PanelSectionHeader {
        id: headingText
        anchors.bottom: parent.bottom
        text: row ? row.label.toUpperCase() : ""
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
      }
    }
  }

  Component {
    id: eventRow

    Column {
      id: eventItem
      property var row: null
      readonly property var ev: row ? row.event : null
      readonly property bool happening: !!ev && ev.start <= root.now && ev.end > root.now
      readonly property bool expanded: !!ev && root.expandedKey === ev.key
      readonly property bool hasCursor: !!ev && root.cursorKey === ev.key
      // Re-evaluated when the service caches this event's .ics details.
      readonly property var info: expanded && root.service
        ? (root.service.icsDetails, root.service.mapsProvider, root.service.details(ev)) : null
      readonly property bool loadingDetails: expanded && !!root.service && !root.service.hasDetails(ev.uid)
      readonly property color stripe: ev && ev.color ? ev.color : Color.accent
      onHasCursorChanged: if (hasCursor) Qt.callLater(root.ensureVisible, eventItem)
      onExpandedChanged: if (expanded) Qt.callLater(root.ensureVisible, eventItem)
      // Details arrive after the click; keep the grown row in view.
      onHeightChanged: if (expanded) Qt.callLater(root.ensureVisible, eventItem)
      spacing: Style.space(6)

      Item {
        width: parent.width
        height: summaryRow.height

        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          radius: Style.space(4)
          color: summaryMouse.containsMouse || eventItem.expanded || eventItem.hasCursor ? Style.hoverFill : "transparent"
          border.width: eventItem.hasCursor ? Style.hoverBorderWidth : 0
          border.color: Style.hoverBorderColor
        }

        Row {
          id: summaryRow
          width: parent.width
          spacing: Style.space(10)

          Rectangle {
            width: Style.space(3)
            height: detailColumn.height
            radius: width / 2
            color: eventItem.stripe
          }

          Text {
            id: timeText
            width: Style.space(root.use24h ? 92 : 128)
            textFormat: Text.PlainText
            text: eventItem.ev ? Model.timeRange(eventItem.ev, root.use24h) : ""
            color: eventItem.happening ? Color.accent : root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            id: detailColumn
            width: summaryRow.width - timeText.width - Style.space(3) - summaryRow.spacing * 2
            spacing: Style.space(1)

            Text {
              width: parent.width
              elide: eventItem.expanded ? Text.ElideNone : Text.ElideRight
              wrapMode: eventItem.expanded ? Text.Wrap : Text.NoWrap
              textFormat: Text.PlainText
              text: eventItem.ev ? (eventItem.ev.status === "CANCELLED" ? "Cancelled: " : "") + eventItem.ev.title : ""
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: eventItem.happening || eventItem.expanded
              font.strikeout: !!eventItem.ev && eventItem.ev.status === "CANCELLED"
            }

            Text {
              width: parent.width
              visible: !eventItem.expanded && !!eventItem.ev && eventItem.ev.location !== ""
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: eventItem.ev ? eventItem.ev.location : ""
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        MouseArea {
          id: summaryMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.cursorKey = eventItem.ev ? eventItem.ev.key : ""
            root.toggleExpanded(eventItem.ev)
          }
        }
      }

      // ---- Expanded details, indented under the title.
      Column {
        visible: eventItem.expanded
        x: Style.space(3) + Style.space(10) * 2 + timeText.width
        width: parent.width - x
        spacing: Style.space(8)
        bottomPadding: Style.space(6)

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: {
            var ev = eventItem.ev
            if (!ev) return ""
            var shownDay = Model.startOfDay(root.selectedIsToday ? root.now : root.selectedMs)
            var parts = [Model.dayHeading(Math.max(ev.start, shownDay), root.now).replace(/^(Today|Tomorrow) · /, "")]
            if (ev.repeating) parts.push("Repeats")
            if (ev.status === "TENTATIVE") parts.push("Tentative")
            // Google calendar folders are named by address; only show real names.
            if (ev.calendar && ev.calendar.indexOf("@") === -1) parts.push(ev.calendar)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        // Actions: join (+ copy link) and directions.
        Flow {
          visible: !!eventItem.info && (!!eventItem.info.meeting || eventItem.info.directions !== "")
          width: parent.width
          spacing: Style.space(6)

          Button {
            visible: !!eventItem.info && !!eventItem.info.meeting
            text: eventItem.info && eventItem.info.meeting ? "Join " + eventItem.info.meeting.label : ""
            iconText: "󰤙"
            bordered: true
            active: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            tooltipText: "m"
            onClicked: root.openLink(eventItem.info.meeting.url)
          }

          PanelActionButton {
            visible: !!eventItem.info && !!eventItem.info.meeting
            iconText: "󰆏"
            tooltipText: "Copy meeting link"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.service.copyText(eventItem.info.meeting.url)
          }

          Button {
            visible: !!eventItem.info && eventItem.info.directions !== ""
            text: "Directions"
            iconText: "󰁔"
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            tooltipText: "d"
            onClicked: root.openLink(eventItem.info.directions)
          }
        }

        Text {
          visible: !!eventItem.info && eventItem.info.location !== ""
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: eventItem.info ? "󰍎  " + eventItem.info.location : ""
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !!eventItem.info && !!eventItem.info.organizer
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: eventItem.info && eventItem.info.organizer ? "Organized by " + Model.personLabel(eventItem.info.organizer) : ""
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        // Guests.
        Column {
          visible: !!eventItem.info && eventItem.info.attendees.length > 0
          width: parent.width
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: eventItem.info ? Model.attendeeSummary(eventItem.info.attendees) : ""
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: eventItem.info ? eventItem.info.attendees.slice(0, 8) : []

            Text {
              required property var modelData
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: Model.attendeeStatus(modelData.status).glyph + "  " + Model.personLabel(modelData)
                + (modelData.organizer ? " · organizer" : "")
              color: modelData.status === "DECLINED" ? root.dim : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            visible: !!eventItem.info && eventItem.info.attendees.length > 8
            textFormat: Text.PlainText
            text: eventItem.info ? "+" + (eventItem.info.attendees.length - 8) + " more" : ""
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: !!eventItem.info && eventItem.info.description !== ""
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: eventItem.info ? Model.linkifiedHtml(eventItem.info.description) : ""
          color: root.contentForeground
          linkColor: Color.accent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          onLinkActivated: function(link) { root.openLink(link) }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
          }
        }

        // Other links from the event URL and description.
        Column {
          visible: !!eventItem.info && eventItem.info.links.length > 0
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            model: eventItem.info ? eventItem.info.links.slice(0, 6) : []

            Text {
              required property var modelData
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: "󰌹  " + modelData.label
              color: linkMouse.containsMouse ? Color.accent : root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall

              MouseArea {
                id: linkMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openLink(parent.modelData.url)
              }

              PanelToolTip {
                visible: linkMouse.containsMouse
                text: parent.modelData.url
                fontFamily: root.contentFontFamily
              }
            }
          }
        }

        Text {
          visible: eventItem.loadingDetails
          textFormat: Text.PlainText
          text: "Loading details…"
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: !!eventItem.info && !eventItem.loadingDetails && !eventItem.info.meeting
            && eventItem.info.location === "" && eventItem.info.description === ""
            && eventItem.info.attendees.length === 0 && eventItem.info.links.length === 0
          textFormat: Text.PlainText
          text: "No other details."
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
