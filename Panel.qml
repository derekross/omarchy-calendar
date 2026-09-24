import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Agenda popup: the next few days of events from khal, grouped by day.
Panel {
  id: root
  moduleName: "derekross.calendar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(contentForeground, 1.4)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property double now: Date.now()
  readonly property var rows: service ? Model.agendaRows(service.events, now) : []
  readonly property bool use24h: service ? service.use24h : true

  // One event is expanded at a time; its key is uid + start. The keyboard
  // cursor (arrow keys) is tracked by key too, so it survives refreshes.
  property string expandedKey: ""
  property string cursorKey: ""
  readonly property var agendaEvents: rows.filter(function(r) { return r.kind === "event" }).map(function(r) { return r.event })

  // Scroll so `item` (a row inside the agenda) is fully visible, top first.
  function ensureVisible(item) {
    if (!item || !scroller) return
    var y = item.mapToItem(agendaColumn, 0, 0).y
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

  // "j" joins and "d" gets directions for the event under the cursor.
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

  readonly property string statusText: {
    if (!service) return "Calendar service is not running. Enable the plugin with omarchy plugin enable derekross.calendar."
    if (!service.khalAvailable) return "khal is not installed or not configured. See the plugin README for setup."
    if (service.lastError) return service.lastError
    return ""
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
    now = Date.now()
    if (service) service.refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function openFromHotkey() { open() }

  function close() {
    setCenterHoverRevealSuppressed(false)
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
  }

  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: root.now = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(agendaColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.expandedKey !== "") root.expandedKey = ""
        else root.close()
      }
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: { var ev = root.focusedEvent(); if (ev) root.toggleExpanded(ev) }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s" || t === "S") { if (root.service) root.service.sync() }
        else if (t === "r" || t === "R") { if (root.service) root.service.refresh() }
        else if (t === "j" || t === "J") root.actOnFocused("join")
        else if (t === "d" || t === "D") root.actOnFocused("directions")
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: agendaColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: agendaColumn
          width: scroller.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            height: Math.max(titleText.implicitHeight, syncButton.height)

            Text {
              id: titleText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "󰃭  Agenda"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              anchors.right: syncButton.left
              anchors.rightMargin: Style.space(6)
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
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑐"
              tooltipText: "Sync now (s)"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              visible: !!root.service && root.service.syncCommand.trim() !== ""
              onClicked: root.service.sync()
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.contentForeground
          }

          Text {
            visible: root.statusText !== "" || root.rows.length === 0
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.statusText !== "" ? root.statusText : "Nothing scheduled in the next " + (root.service ? root.service.agendaDays : 7) + " days."
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.rows

            Loader {
              required property var modelData
              width: agendaColumn.width
              sourceComponent: modelData.kind === "day" ? dayHeading : eventRow
              onLoaded: item.row = modelData
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
            var parts = [Model.dayHeading(Math.max(ev.start, Model.startOfDay(root.now)), root.now).replace(/^(Today|Tomorrow) · /, "")]
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
            tooltipText: "j"
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
