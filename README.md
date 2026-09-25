# Omarchy Calendar Clock

An [Omarchy](https://omarchy.org) shell plugin that adds your calendar to Omarchy's clock:

- **Clock.** Takes the place of Omarchy's built-in clock in the bar. The label, its formats and the right-click format cycle work the same.
- **Month grid with events.** The clock's popup keeps its date, year bar and month grid, and each day with events gets a dot in each calendar's color. Click a day to see its events, and page through months to see what's coming up or what happened.
- **Agenda.** Under the grid is the next week of events, grouped by day, with each calendar's color and the event location.
- **Event details.** Click an event to expand it. It shows a **Join** button for Google Meet, Zoom, Microsoft Teams, Jitsi, Webex, Whereby, Signal and Discord links, plus **Directions** to the location, the description with clickable links, the organizer, and each guest's RSVP.
- **Notifications.** A desktop notification a few minutes before each timed event (10 by default). All-day events are skipped.
- **Sync.** Runs `vdirsyncer sync` every 15 minutes, or any command you choose, so events stay current.

It reads events with [khal](https://khal.readthedocs.io), so it works with any calendar khal can read: Google (through vdirsyncer), CalDAV servers like Nextcloud, Fastmail and iCloud, or plain `.ics` folders.

## Requirements

- Omarchy 4 or newer (the Quickshell-based `omarchy-shell`)
- `khal` configured with at least one calendar. `khal list` should print your events.
- Optional: `vdirsyncer` (or any other sync tool) to pull events from a server

```bash
sudo pacman -S khal vdirsyncer
```

If you've never set up khal and vdirsyncer, see [Setting up a calendar](#setting-up-a-calendar) below.

## Install

```bash
omarchy plugin add https://github.com/derekross/omarchy-calendar.git --enable
```

Omarchy installs plugins switched off by default and asks you to confirm; `--enable` turns it on straight away.

The plugin replaces `omarchy.clock` using Omarchy's clone mechanism (`"clonedFrom": "omarchy.clock"` in the manifest). When you enable it, it takes the clock's place in the bar and keeps the clock's settings. Anything that talks to the clock reaches this plugin instead, including the `Super + Ctrl + Alt + D` shortcut and `omarchy-shell shell toggle omarchy.clock`.

To put the stock clock back, disable the plugin:

```bash
omarchy plugin disable derekross.calendar
```

Update with `omarchy plugin update derekross.calendar`. Uninstall with `omarchy plugin remove derekross.calendar`.

### Upgrading from 0.1

Version 0.1 was a separate bar widget next to the clock. If the stock clock and this plugin are both in your bar after updating, move this plugin into the clock's slot:

```bash
omarchy bar move derekross.calendar --before omarchy.clock
omarchy plugin disable omarchy.clock
```

If you had changed the clock's label format, set it again with `omarchy bar set derekross.calendar format "<format>"`.

Omarchy centers the bar on the widget named by `centerAnchor` in `~/.config/omarchy/shell.json`, which is `omarchy.clock` by default. That id doesn't follow the plugin, so the bar has no center widget until you change it. Set it to `"derekross.calendar"`.

## Using it

| Action | Result |
| --- | --- |
| Left click the clock | Open or close the calendar |
| Right click the clock | Next label format |
| Middle click the clock | Pick a timezone |
| Click a day | Show that day's events |
| Click the date at the top | Back to today |
| Click an event | Expand or collapse its details |
| Double-click the year bar | Set a birth year for the life bar, as in Omarchy's clock |
| `←` / `→` (or `h` / `l`) | Previous / next day |
| `[` / `]` | Previous / next month |
| `{` / `}` | Previous / next year |
| `t` | Back to today |
| `w` | Start weeks on Sunday or Monday |
| `↑` / `↓` (or `k` / `j`) | Move between events |
| `Enter` | Expand or collapse the selected event |
| `m` | Join the selected event's meeting |
| `d` | Directions to the selected event's location |
| `s` / `r` | Sync now / re-read events |
| `Esc` | Collapse the event, or close the calendar |

## Settings

Change these in the Omarchy bar settings, or from a terminal with `omarchy bar set derekross.calendar <key> <value>`:

| Key | Default | Meaning |
| --- | --- | --- |
| `format` | `dddd HH:mm` | The clock label, as a [Qt date format](https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method); `ww` is the ISO week |
| `formatAlt` | `d MMMM 'W'ww yyyy` | An extra format in the right-click cycle |
| `notifications` | `true` | Notify before timed events |
| `leadMinutes` | `10` | How many minutes before an event to notify |
| `agendaDays` | `7` | How many days the agenda shows |
| `timeFormat` | `Match khal` | Event times: `Match khal`, `12-hour` or `24-hour` |
| `mapsProvider` | `Google Maps` | Map site for directions: `Google Maps`, `OpenStreetMap` or `Apple Maps` |
| `syncIntervalMinutes` | `15` | How often to run the sync command; `0` turns syncing off |
| `syncCommand` | `vdirsyncer sync` | The sync command, run with `sh -c`. Leave it empty to never sync |

The clock's own settings (`weekStartDay`, `birthYear`, `lifeExpectancy`, `verticalFormat`) carry over and work as they do in Omarchy's clock.

If a systemd timer or cron job already runs vdirsyncer, set `syncIntervalMinutes` to `0`.

Notifications and syncing come from the plugin's background service, so they keep working even if you remove the clock from the bar. Without the widget in the bar, the defaults above apply.

## Scripting

```bash
omarchy-shell shell toggle omarchy.clock   # open or close the calendar
omarchy-shell derekross.calendar sync      # sync now
omarchy-shell derekross.calendar refresh   # re-read khal
omarchy-shell derekross.calendar status    # JSON: event count, loaded months, last sync, errors
```

## Setting up a calendar

### Google Calendar

vdirsyncer copies Google calendars to local files, and khal reads those files. vdirsyncer needs its own Google OAuth client:

1. Create an OAuth client by following vdirsyncer's [Google guide](https://vdirsyncer.pimutils.org/en/stable/config.html#google), and install `python-aiohttp-oauthlib`.
2. Write `~/.config/vdirsyncer/config`:

   ```ini
   [general]
   status_path = "~/.local/share/vdirsyncer/status/"

   [pair google_calendar]
   a = "google_remote"
   b = "google_local"
   collections = ["from a"]
   metadata = ["color"]

   [storage google_remote]
   type = "google_calendar"
   token_file = "~/.local/share/vdirsyncer/google_token"
   client_id = "…"
   client_secret = "…"

   [storage google_local]
   type = "filesystem"
   path = "~/.local/share/calendars/"
   fileext = ".ics"
   ```

3. Run `vdirsyncer discover`, which opens a browser to sign in. Then run `vdirsyncer metasync && vdirsyncer sync`.
4. Point khal at the synced folder in `~/.config/khal/config`:

   ```ini
   [calendars]
   [[synced]]
   path = ~/.local/share/calendars/*
   type = discover
   ```

### CalDAV (Nextcloud, Fastmail, iCloud and others)

Use a `caldav` storage in place of `google_calendar`; see the [vdirsyncer CalDAV docs](https://vdirsyncer.pimutils.org/en/stable/config.html#caldav). The khal setup is the same.

### No sync at all

Point khal at any folder of `.ics` files and set `syncCommand` to an empty string.

## How it works

- `Service.qml` is a headless Omarchy `service` plugin. Once a minute it runs `khal list --json …`, and it sends notifications through `omarchy-notification-send`. Events it has already notified about are recorded in `~/.local/state/omarchy-calendar/notified.json`, so restarting the shell doesn't repeat a notification.
- khal prints dates in each user's own locale format. At startup the service runs `khal printformats` and builds a matching parser, so `2026-09-24`, `24.09.2026`, `09/24/26` and `Thursday, September 24, 2026` all parse.
- Meeting links and guest lists aren't in khal's output (Google keeps Meet links in `X-GOOGLE-CONFERENCE`). When you expand an event, the service finds its `.ics` file in the folders named by the `path =` lines of your khal config, and reads those details from it.
- If khal's date or time format is one the plugin can't read back (for example non-English month names), the agenda shows an error saying which setting to change. It doesn't guess, so it never shows wrong times.
- To browse another month, the panel asks the service for that month, and the service runs `khal list <start> 48d` for it. That covers any six-week grid. khal only accepts dates written in your own `longdateformat`, so the start date is written using the same `printformats` sample. Months are cached until the next sync or refresh.
- `BarWidget.qml` and `Panel.qml` read events from the service. `Model.js` holds all the parsing and scheduling logic, with no QML, so it can be tested with node.
- The clock label, month grid, year and life bars, and `ClockModel.js` are adapted from Omarchy's built-in clock (`shell/plugins/panels/clock`, MIT). They are kept close to upstream so upstream changes are easy to bring in.

The plugin only runs `khal`, your sync command, `grep`/`cat` to read your own calendar files, `mkdir` for its state folder, `omarchy-notification-send`, `xdg-open` for links you click, and `wl-copy` when you copy a meeting link. It makes no network requests of its own.

## Development

```bash
git clone https://github.com/derekross/omarchy-calendar.git
ln -s "$PWD/omarchy-calendar" ~/.config/omarchy/plugins/derekross.calendar
omarchy-shell shell rescanPlugins
omarchy plugin enable derekross.calendar

node --test tests/                 # unit tests for Model.js and ClockModel.js
omarchy plugin validate .          # manifest check
```

Changes to the bar widget and panel reload when you save. Omarchy keeps the service loaded between reloads, so after editing `Service.qml`, run `omarchy restart shell`.

## License

MIT
