import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import Shell from 'gi://Shell';
import Clutter from 'gi://Clutter';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {decodeSnapshot, upcoming, remaining, urgency, MAX_BYTES} from './snapshot.mjs';
import {readBounded} from './reader.mjs';
import {DesktopCard} from './desktopCard.js';

export default class TechPieDeadlines extends Extension {
    enable() {
        this._alive = true;
        this._generation = (this._generation ?? 0) + 1;
        this._cancellable = new Gio.Cancellable();
        this._settings = this.getSettings();
        this._desktop = new DesktopCard(this._settings, () => this._open());
        this._directory = GLib.build_filenamev([GLib.get_user_data_dir(), 'techpie', 'widgets']);
        this._path = GLib.build_filenamev([this._directory, 'deadline-widget-v1.json']);
        this._button = new PanelMenu.Button(0.0, 'TechPie Deadlines');
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        box.add_child(new St.Icon({icon_name: 'view-calendar-symbolic', style_class: 'system-status-icon'}));
        this._label = new St.Label({text: 'TechPie', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(this._label);
        this._button.add_child(box);
        Main.panel.addToStatusArea(this.uuid, this._button);
        this._button.menu.connect('open-state-changed', (_menu, open) => {
            if (open) this._reload().catch(error => console.error(error));
        });
        this._watch();
        this._reload().catch(error => console.error(error));
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, () => {
            this._watch();
            this._reload().catch(error => console.error(error));
            return GLib.SOURCE_CONTINUE;
        });
    }

    _watch() {
        // Watch the closest existing ancestor as the app may not have created
        // its directory yet. Reattach after creation or an atomic replacement.
        let directory = Gio.File.new_for_path(this._directory);
        while (!directory.query_exists(null) && directory.get_parent())
            directory = directory.get_parent();
        const path = directory.get_path();
        if (this._watched === path) return;
        this._clearMonitor();
        try {
            this._monitor = directory.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, this._cancellable);
            this._watched = path;
            this._monitorSignal = this._monitor.connect('changed', () => {
                if (!this._alive) return;
                if (this._debounce) GLib.Source.remove(this._debounce);
                this._debounce = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
                    this._debounce = 0;
                    this._watch();
                    this._reload().catch(error => console.error(error));
                    return GLib.SOURCE_REMOVE;
                });
            });
        } catch (_) { /* Retry on the periodic tick. */ }
    }

    _clearMonitor() {
        if (this._monitor) {
            if (this._monitorSignal) this._monitor.disconnect(this._monitorSignal);
            this._monitor.cancel();
        }
        this._monitor = null;
        this._monitorSignal = 0;
        this._watched = null;
    }

    async _reload() {
        const generation = ++this._generation;
        try {
            const file = Gio.File.new_for_path(this._path);
            const json = await readBounded(file, MAX_BYTES, this._cancellable);
            if (!this._alive || generation !== this._generation) return;
            this._snapshot = decodeSnapshot(json);
            this._state = 'ready';
        } catch (error) {
            if (!this._alive || generation !== this._generation) return;
            this._snapshot = null;
            this._state = error.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND)
                ? 'notSynced' : 'unavailable';
        }
        this._render();
    }

    _open() {
        const timestamp = global.get_current_time();
        this._button.menu.close();
        // Activate through Shell as well as delivering the URI: on Wayland an
        // existing GTK window cannot always raise itself without user input.
        const app = Shell.AppSystem.get_default().lookup_app('com.example.techpie.desktop');
        app?.activate();
        Gio.AppInfo.launch_default_for_uri_async('techpie://deadlines',
            global.create_app_launch_context(timestamp, -1), this._cancellable, (_source, result) => {
                try { Gio.AppInfo.launch_default_for_uri_finish(result); }
                catch (_) {
                    if (this._alive) Main.notify('TechPie', 'Install the TechPie desktop launcher to open deadlines.');
                }
            });
    }

    _render() {
        if (!this._alive) return;
        const menu = this._button.menu;
        menu.removeAll();
        const now = Date.now() / 1000;
        const items = this._snapshot ? upcoming(this._snapshot, now) : [];
        this._desktop.update(this._snapshot, this._state);
        this._label.text = items.length ? remaining(items[0].dueAt, now) : 'TechPie';
        this._label.style_class = items.length
            ? `techpie-deadline-time-${urgency(items[0].dueAt, now)}` : '';
        if (!this._snapshot || !items.length) {
            const message = this._state === 'unavailable' ? 'Deadline data is unavailable' :
                this._snapshot ? 'No upcoming deadlines' : 'Enable Deadline widgets in TechPie Settings';
            menu.addMenuItem(new PopupMenu.PopupMenuItem(message, {reactive: false}));
        }
        for (const item of items) {
            const row = new PopupMenu.PopupMenuItem('');
            const direction = 'orientation' in St.BoxLayout.prototype
                ? {orientation: Clutter.Orientation.VERTICAL} : {vertical: true};
            const level = urgency(item.dueAt, now);
            const box = new St.BoxLayout({...direction,
                style_class: `techpie-deadline-row techpie-deadline-card-${level}`});
            const heading = new St.BoxLayout({style_class: 'techpie-deadline-heading'});
            heading.add_child(new St.Label({text: `${item.kind === 'exam' ? '考试' : '作业'}  ${item.title}`,
                style_class: 'techpie-deadline-title', x_expand: true}));
            heading.add_child(new St.Label({text: remaining(item.dueAt, now),
                style_class: `techpie-deadline-time techpie-deadline-time-${level}`}));
            box.add_child(heading);
            box.add_child(new St.Label({text: `${item.course}  ·  ${new Date(item.dueAt * 1000).toLocaleString()}`,
                style_class: 'techpie-deadline-detail'}));
            row.add_child(box);
            row.connect('activate', () => this._open());
            menu.addMenuItem(row);
        }
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        const visible = new PopupMenu.PopupSwitchMenuItem('Desktop card',
            this._settings.get_boolean('desktop-visible'));
        visible.connect('toggled', (_item, value) => this._settings.set_boolean('desktop-visible', value));
        menu.addMenuItem(visible);
        const reset = new PopupMenu.PopupMenuItem('Reset desktop card position');
        reset.connect('activate', () => this._desktop.resetPosition());
        menu.addMenuItem(reset);
        const open = new PopupMenu.PopupMenuItem('Open TechPie Deadlines');
        open.connect('activate', () => this._open());
        menu.addMenuItem(open);
        if (this._snapshot) {
            menu.addMenuItem(new PopupMenu.PopupMenuItem(
                `Cached snapshot · ${new Date(this._snapshot.writtenAt * 1000).toLocaleString()}`,
                {reactive: false}));
        }
    }

    disable() {
        this._alive = false;
        this._generation++;
        this._cancellable?.cancel();
        this._clearMonitor();
        if (this._timer) GLib.Source.remove(this._timer);
        if (this._debounce) GLib.Source.remove(this._debounce);
        this._timer = this._debounce = 0;
        this._monitor = this._cancellable = null;
        this._watched = this._snapshot = null;
        this._button?.destroy();
        this._desktop?.destroy();
        this._desktop = this._settings = null;
        this._button = this._label = null;
    }
}
