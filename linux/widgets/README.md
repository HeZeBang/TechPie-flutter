# TechPie Linux deadline widgets (first version)

KDE Plasma 6: a resizable desktop card and compact panel button. GNOME Shell
45–51: a desktop card and top-bar indicator with an expandable deadline list.
GNOME 51 has been checked in an isolated Shell session; other declared versions
and the Plasma desktop still need native visual acceptance.

The widgets show upcoming, visible, incomplete assignments and exams, sorted by
deadline. They do not contact campus services or receive credentials. They read
the last snapshot published by TechPie; keep the app running for new data.
Expired entries and countdowns are refreshed locally at most every 30 seconds.
The timestamp is when the snapshot was saved, not a claim of a successful server
sync. A widget click opens the app's Deadlines page.

## Install a release bundle

Extract the entire Linux release archive to a stable location first. From its
`bundle` directory, using the absolute path to that bundle's executable:

```bash
python3 widgets/install.py install --desktop kde --app /absolute/path/bundle/techpie
# Or GNOME, or --desktop both:
python3 widgets/install.py install --desktop gnome --app /absolute/path/bundle/techpie
```

In TechPie, open **Settings → General → Deadline widgets** to enable sharing.
The setting is off initially. Sharing exposes task titles, course names and
dates to the current user's desktop. Turning it off or signing out clears the
shared task data. Enabled widgets publish an empty list before the first sync.
Widgets are not enabled for the GNOME lock screen.

- KDE: use the desktop/panel **Add Widgets** picker and select **TechPie Deadlines**.
- GNOME: after a first installation, log out/in if the extension is not listed;
  enable **TechPie Deadlines** in Extensions. The installer does not enable it.
- GNOME: drag the card heading to move it. Its position is saved relative to the
  primary monitor's work area. The indicator menu can hide the card or reset its
  position. It stays below application windows and hides in overview/fullscreen.
- If the app bundle moves, rerun the installer with the new executable path.
- Dependencies: Python 3 for installation, Qt 6 Core/Gui/Qml for KDE; GJS/GNOME
  Shell and GLib's `glib-compile-schemas` for GNOME. The app also requires its normal GTK/WebKit/libsecret runtime
  dependencies plus json-glib. For Arch, the corresponding widget build packages
  are `base-devel cmake qt6-base qt6-declarative json-glib`; Plasma provides its
  own QML modules. No root access is required for user installation.

## Build from source

Build the normal Linux app using Flutter **3.41.9**. Then build the KDE adapter:

```bash
cmake -S linux/widgets -B build/linux-widgets -DCMAKE_BUILD_TYPE=Release
cmake --build build/linux-widgets --parallel
python3 linux/widgets/install.py install --desktop kde \
  --kde-package build/linux-widgets/kde \
  --app /absolute/path/build/linux/x64/release/bundle/techpie
```

For GNOME, use the same installer with `--desktop gnome`; no Qt build is needed.
The Linux release workflow includes both packages and the compiled Qt adapter.
The Qt plugin must be rebuilt for another architecture and must not require a
newer Qt minor version than the target desktop provides.

## Uninstall

Disable the GNOME extension/remove the Plasma widget first, then run:

```bash
python3 widgets/install.py uninstall --desktop both
```

Only marked TechPie widget directories and the managed launcher are removed.
The app and its data are retained. Turn off sharing in the app to erase the
snapshot. No account credentials are ever stored in the widget directory.

## Data and lifecycle

The shared v1 protocol follows the macOS branch. Its display-only snapshot is
`$XDG_DATA_HOME/techpie/widgets/deadline-widget-v1.json`, defaulting to
`~/.local/share/techpie/widgets/deadline-widget-v1.json`. Directory permissions
are `0700`, files `0600`; writes are atomic. Readers accept at most 256 KiB / 512
entries and validate fields, version, timestamps and duplicate IDs. Both watch
directories so atomic replacement and first-time creation are detected.

The Flutter service serializes writes, ignores superseded account generations,
and uses the same account-isolation changes as the macOS reference. Linux
registers `techpie://deadlines` and activates an existing application instance.
Its existing application ID is retained so saved preferences keep their location.
The existing payment widget and Huawei Watch code remain separate consumers.

GNOME's `desktopCard.js` owns the desktop actor and placement; `extension.js`
owns the indicator, reader and lifecycle. GSettings stores card visibility and
position. KDE keeps its reader/model in `backend` and presentation in QML.
This version targets an unpacked native bundle; Flatpak/Snap integration is
outside its scope.

## Desktop card stacking regression

The GNOME card ignores minimized or hidden window actors when choosing its
stacking position. It restores that position before painting, after Mutter has
finished updating the window stack, so DING's transparent desktop window cannot
cover its buttons after applications are minimized.

```bash
node --experimental-vm-modules --test linux/widgets/tests/desktop-stacking.test.mjs
```
