import Clutter from 'gi://Clutter';
import St from 'gi://St';
import Meta from 'gi://Meta';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {upcoming, remaining, urgency} from './snapshot.mjs';

function column(properties = {}) {
    const direction = 'orientation' in St.BoxLayout.prototype
        ? {orientation: Clutter.Orientation.VERTICAL} : {vertical: true};
    return new St.BoxLayout({...direction, ...properties});
}

// Kept below application windows; no reserved screen area or lock-screen actor.
export class DesktopCard {
    constructor(settings, open) {
        this._settings = settings;
        this._open = open;
        this.actor = column({style_class: 'popup-menu-content techpie-desktop-card',
            reactive: true, x_expand: false, y_expand: false,
            x_align: Clutter.ActorAlign.START, y_align: Clutter.ActorAlign.START});
        this._header = new St.Label({text: 'TechPie · Deadlines', reactive: true,
            style_class: 'techpie-desktop-header'});
        this.actor.add_child(this._header);
        this._rows = column({style_class: 'techpie-desktop-rows'});
        this.actor.add_child(this._rows);
        this._footer = new St.Label({style_class: 'techpie-deadline-detail'});
        this.actor.add_child(this._footer);
        const button = new St.Button({label: 'Open TechPie', can_focus: true,
            style_class: 'button'});
        button.connect('clicked', open);
        this.actor.add_child(button);
        this._windowGroup = global.window_group;
        this._windowGroup.add_child(this.actor);
        Main.layoutManager.trackChrome(this.actor, {affectsStruts: false});
        this._signals = [
            [settings, settings.connect('changed', () => this._position())],
            [Main.layoutManager, Main.layoutManager.connect('monitors-changed', () => this._position())],
            [global.display, global.display.connect('workareas-changed', () => this._position())],
            [global.display, global.display.connect('in-fullscreen-changed', () => this._position())],
            [global.display, global.display.connect('restacked', () => this._restack())],
            [this._windowGroup, this._windowGroup.connect('child-added', () => this._restack())],
        ];
        this._header.connect('button-press-event', (_actor, event) => {
            if (event.get_button() !== 1) return Clutter.EVENT_PROPAGATE;
            const [x, y] = event.get_coords();
            this._drag = [x - this.actor.x, y - this.actor.y];
            this._grab = global.stage.grab(this._header);
            return Clutter.EVENT_STOP;
        });
        this._header.connect('motion-event', (_actor, event) => {
            if (!this._drag) return Clutter.EVENT_PROPAGATE;
            const [x, y] = event.get_coords();
            const bounds = this._bounds();
            if (bounds) this.actor.set_position(
                Math.max(bounds.x, Math.min(bounds.x + bounds.width, x - this._drag[0])),
                Math.max(bounds.y, Math.min(bounds.y + bounds.height, y - this._drag[1])));
            return Clutter.EVENT_STOP;
        });
        this._header.connect('button-release-event', () => {
            if (!this._drag) return Clutter.EVENT_PROPAGATE;
            const bounds = this._bounds();
            const x = bounds?.width ? (this.actor.x - bounds.x) / bounds.width : 1;
            const y = bounds?.height ? (this.actor.y - bounds.y) / bounds.height : 0;
            this._endDrag();
            settings.set_double('position-x', x);
            settings.set_double('position-y', y);
            return Clutter.EVENT_STOP;
        });
        this._restack();
        this._position();
    }

    _restack() {
        // Desktop icon extensions use a transparent desktop window which still
        // receives pointer events. Place the card above it, below normal apps.
        const sibling = this._windowGroup.get_children().find(child => {
            const window = child.get_meta_window?.();
            return window && window.get_window_type() !== Meta.WindowType.DESKTOP;
        });
        if (sibling) this._windowGroup.set_child_below_sibling(this.actor, sibling);
        else this._windowGroup.set_child_above_sibling(this.actor, null);
    }

    _bounds() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor) return null;
        const area = Main.layoutManager.getWorkAreaForMonitor(monitor.index);
        // Clear the previous request before measuring, so removing content
        // can shrink the card as well as adding content can grow it.
        this.actor.set_size(-1, -1);
        const [, naturalWidth] = this.actor.get_preferred_width(-1);
        const maxWidth = Math.min(440, Math.max(1, area.width - 48));
        this.actor.width = Math.min(maxWidth, Math.max(300, naturalWidth));
        const [, height] = this.actor.get_preferred_height(this.actor.width);
        this.actor.height = height;
        return {x: area.x + 24, y: area.y + 24,
            width: Math.max(0, area.width - this.actor.width - 48),
            height: Math.max(0, area.height - height - 48)};
    }

    _endDrag() {
        const grab = this._grab;
        this._grab = this._drag = null;
        grab?.dismiss();
    }

    _position() {
        this._endDrag();
        const bounds = this._bounds();
        this.actor.visible = Boolean(bounds && this._settings.get_boolean('desktop-visible') &&
            !Main.layoutManager.primaryMonitor.inFullscreen);
        if (bounds) this.actor.set_position(
            bounds.x + bounds.width * this._settings.get_double('position-x'),
            bounds.y + bounds.height * this._settings.get_double('position-y'));
    }

    resetPosition() {
        this._settings.reset('position-x');
        this._settings.reset('position-y');
    }

    update(snapshot, state) {
        this._rows.destroy_all_children();
        const now = Date.now() / 1000;
        const items = snapshot ? upcoming(snapshot, now).slice(0, 4) : [];
        for (const item of items) {
            const level = urgency(item.dueAt, now);
            const row = column({style_class: `techpie-deadline-row techpie-deadline-card-${level}`,
                x_expand: true,
                x_align: Clutter.ActorAlign.FILL});
            const heading = new St.BoxLayout({style_class: 'techpie-deadline-heading', x_expand: true});
            heading.add_child(new St.Label({text: item.kind === 'exam' ? '考试' : '作业',
                style_class: 'techpie-deadline-kind'}));
            heading.add_child(new St.Label({text: item.title, x_expand: true,
                style_class: 'techpie-deadline-title'}));
            const time = new St.Label({text: remaining(item.dueAt, now),
                style_class: `techpie-deadline-time techpie-deadline-time-${level}`});
            heading.add_child(time);
            row.add_child(heading);
            const due = new Date(item.dueAt * 1000).toLocaleString(undefined,
                {month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit'});
            row.add_child(new St.Label({text: `${item.course} · ${due}`,
                x_expand: true, style_class: 'techpie-deadline-detail'}));
            const button = new St.Button({child: row, x_expand: true, can_focus: true,
                style_class: 'techpie-desktop-item'});
            button.connect('clicked', this._open);
            this._rows.add_child(button);
        }
        if (!items.length) this._rows.add_child(new St.Label({
            text: state === 'unavailable' ? 'Deadline data is unavailable' : snapshot
                ? 'No upcoming deadlines' : 'Enable Deadline widgets\nin TechPie Settings',
        }));
        this._footer.text = snapshot
            ? `Cached · ${new Date(snapshot.writtenAt * 1000).toLocaleString()}` : 'Drag the heading to move';
        this._position();
    }

    destroy() {
        this._endDrag();
        for (const [object, signal] of this._signals) object.disconnect(signal);
        Main.layoutManager.untrackChrome(this.actor);
        this.actor.destroy();
    }
}
