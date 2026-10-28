#!/usr/bin/env python3
"""Install only TechPie's launcher and selected widgets for the current user."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
KDE_ID = "club.geekpie.techpie.deadlines"
GNOME_ID = "deadlines@techpie.geekpie.club"
MARKER = ".techpie-widget-install"
# Keep the runner's existing ID: path_provider uses it for app preferences.
DESKTOP_NAME = "com.example.techpie.desktop"


def desktop_quote(path):
    value = str(path).replace("%", "%%")
    for char in ('\\', '"', '`', '$'):
        value = value.replace(char, '\\' + char)
    # Desktop Entry string escaping is applied before Exec argument escaping.
    return ('"' + value + '"').replace('\\', '\\\\')


def managed_copy(source, target):
    if target.is_symlink() or (target.exists() and not (target / MARKER).is_file()):
        raise ValueError(f"Refusing to replace an unmanaged directory: {target}")
    # Source validation occurs before any existing installation is replaced.
    temporary = target.with_name(target.name + ".techpie-staging")
    if temporary.exists():
        raise ValueError(f"Staging directory already exists: {temporary}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, temporary)
    (temporary / MARKER).write_text("TechPie deadline widgets v1\n", encoding="utf-8")
    if target.exists():
        shutil.rmtree(target)
    temporary.rename(target)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "uninstall"])
    parser.add_argument("--desktop", choices=["kde", "gnome", "both"], required=True)
    parser.add_argument("--app", type=Path, help="Absolute path to the built bundle/techpie")
    parser.add_argument("--kde-package", type=Path, default=ROOT / "kde",
                        help="Built KDE package from cmake, or the bundled package")
    parser.add_argument("--data-home", type=Path,
                        default=Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")))
    args = parser.parse_args(argv)
    if not args.data_home.is_absolute():
        parser.error("--data-home must be absolute")
    data = args.data_home.resolve()
    targets = []
    if args.desktop in ("kde", "both"):
        targets.append((args.kde_package, data / "plasma/plasmoids" / KDE_ID))
    if args.desktop in ("gnome", "both"):
        targets.append((ROOT / "gnome", data / "gnome-shell/extensions" / GNOME_ID))
    launcher = data / "applications" / DESKTOP_NAME
    if args.action == "install":
        if args.desktop in ("gnome", "both") and not shutil.which("glib-compile-schemas"):
            parser.error("GNOME installation requires glib-compile-schemas (GLib)")
        if not args.app or not args.app.is_absolute() or not args.app.is_file() or not os.access(args.app, os.X_OK):
            parser.error("--app must name an absolute executable TechPie bundle path")
        app = args.app.resolve()
        icon = app.parent / "techpie.png"
        if not icon.is_file():
            icon = ROOT.parents[1] / "assets/icon/icon.png"
        icon_name = str(icon).replace('\\', '\\\\') if icon.is_file() else "view-calendar-tasks"
        if '\n' in str(app) or '\r' in str(app):
            parser.error("Application path cannot contain newlines")
        for source, target in targets:
            if not (source / "metadata.json").is_file():
                parser.error(f"Missing widget package: {source}")
            if target.is_symlink() or (target.exists() and not (target / MARKER).is_file()):
                parser.error(f"Existing directory is not managed by this installer: {target}")
            if source == args.kde_package and args.desktop in ("kde", "both") and not (
                    source / "contents/ui/backend/libtechpiedeadlines.so").is_file():
                parser.error("Build the KDE backend first; pass --kde-package BUILD/kde")
        if launcher.exists() and "X-TechPie-Managed=true" not in launcher.read_text(encoding="utf-8"):
            parser.error(f"Launcher already exists and is not managed: {launcher}")
        for source, target in targets:
            managed_copy(source, target)
            if target.name == GNOME_ID:
                shutil.copy2(ROOT / "common/snapshot.mjs", target / "snapshot.mjs")
                subprocess.run(["glib-compile-schemas", "--strict", str(target / "schemas")], check=True)
        launcher.parent.mkdir(parents=True, exist_ok=True)
        launcher.write_text(
            "[Desktop Entry]\nType=Application\nName=TechPie\n"
            f"Exec={desktop_quote(app)} %u\nIcon={icon_name}\n"
            "Terminal=false\nCategories=Education;\nMimeType=x-scheme-handler/techpie;\n"
            "StartupWMClass=com.example.techpie\nX-TechPie-Managed=true\n", encoding="utf-8")
        print("Installed. Enable Deadline widgets in TechPie Settings.")
        if args.desktop in ("gnome", "both"):
            print(f"GNOME: log out/in if newly installed, then enable {GNOME_ID} in Extensions.")
        if args.desktop in ("kde", "both"):
            print("KDE: use Add Widgets and select TechPie Deadlines (restart Plasma session if needed).")
    else:
        for _, target in targets:
            if target.is_symlink():
                parser.error(f"Refusing to remove a symlink: {target}")
            if target.exists():
                if not (target / MARKER).is_file():
                    parser.error(f"Refusing to remove an unmanaged directory: {target}")
        for _, target in targets:
            if target.exists():
                shutil.rmtree(target)
        # Keep the launcher if the other desktop's widget is still installed.
        other_installed = any((path / MARKER).exists() for path in (
            data / "plasma/plasmoids" / KDE_ID, data / "gnome-shell/extensions" / GNOME_ID))
        if not other_installed and launcher.exists() and "X-TechPie-Managed=true" in launcher.read_text(encoding="utf-8"):
            launcher.unlink()
        print("Removed selected widget packages. Application and snapshots are retained.")
    update = shutil.which("update-desktop-database")
    if update and launcher.parent.exists():
        subprocess.run([update, str(launcher.parent)], check=True)


if __name__ == "__main__":
    main()
