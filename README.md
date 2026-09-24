# Omarchy Calendar

An [Omarchy](https://omarchy.org) shell plugin that puts your calendar in the bar:

- **Bar widget.** Shows the current or next event today, like `󰃭 6:00 PM Soccer game`.
- **Agenda popup.** Click the widget to see the next week of events grouped by day, with each calendar's color and the event location.
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

Omarchy installs plugins switched off by default and asks you to confirm; `--enable` turns it on straight away. The widget goes in the center of the bar. To move it:

```bash
omarchy bar move derekross.calendar --section right
```

Update with `omarchy plugin update derekross.calendar`. Uninstall with `omarchy plugin remove derekross.calendar`.

## Using it

| Action | Result |
| --- | --- |
| Left click the widget | Open or close the agenda |
| Right click the widget | Sync now |
| Middle click the widget | Re-read events from khal |
| Click an event | Expand or collapse its details |
| `↑` / `↓` | Move between events |
| `Enter` | Expand or collapse the selected event |
| `j` | Join the selected event's meeting |
| `d` | Directions to the selected event's location |
| `s` / `r` | Sync now / re-read events |
| `Esc` | Collapse the event, or close the agenda |

## Settings

Change these in the Omarchy bar settings, or from a terminal with `omarchy bar set derekross.calendar <key> <value>`:

| Key | Default | Meaning |
| --- | --- | --- |
| `notifications` | `true` | Notify before timed events |
| `leadMinutes` | `10` | How many minutes before an event to notify |
| `agendaDays` | `7` | How many days the agenda shows |
| `maxTitleLength` | `24` | How much of the title to show in the bar; `0` shows the full title |
| `timeFormat` | `Match khal` | `Match khal`, `12-hour` or `24-hour` |
| `mapsProvider` | `Google Maps` | Map site for directions: `Google Maps`, `OpenStreetMap` or `Apple Maps` |
| `showWhenIdle` | `true` | Show the calendar icon when nothing else is scheduled today |
| `syncIntervalMinutes` | `15` | How often to run the sync command; `0` turns syncing off |
| `syncCommand` | `vdirsyncer sync` | The sync command, run with `sh -c`. Leave it empty to never sync |

If a systemd timer or cron job already runs vdirsyncer, set `syncIntervalMinutes` to `0`.

Notifications and syncing come from the plugin's background service, so they keep working even if you remove the widget from the bar. Without the widget in the bar, the defaults above apply.

## Scripting

```bash
omarchy-shell derekross.calendar sync      # sync now
omarchy-shell derekross.calendar refresh   # re-read khal
omarchy-shell derekross.calendar status    # JSON: event count, last sync, errors
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
- `BarWidget.qml` and `Panel.qml` read events from the service. `Model.js` holds all the parsing and scheduling logic, with no QML, so it can be tested with node.

The plugin only runs `khal`, your sync command, `grep`/`cat` to read your own calendar files, `mkdir` for its state folder, `omarchy-notification-send`, `xdg-open` for links you click, and `wl-copy` when you copy a meeting link. It makes no network requests of its own.

## Development

```bash
git clone https://github.com/derekross/omarchy-calendar.git
ln -s "$PWD/omarchy-calendar" ~/.config/omarchy/plugins/derekross.calendar
omarchy-shell shell rescanPlugins
omarchy plugin enable derekross.calendar

node --test tests/                 # unit tests for Model.js
omarchy plugin validate .          # manifest check
```

Changes to the bar widget and panel reload when you save. Omarchy keeps the service loaded between reloads, so after editing `Service.qml`, run `omarchy restart shell`.

## License

MIT
