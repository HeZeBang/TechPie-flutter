// Run: node --experimental-vm-modules --test linux/widgets/tests/desktop-stacking.test.mjs
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {test} from 'node:test';

const pending = new Map();
let nextId = 1;
const laters = {
    add(_phase, callback) { const id = nextId++; pending.set(id, callback); return id; },
    remove(id) { pending.delete(id); },
};
const context = vm.createContext({global: {compositor: {get_laters: () => laters}}});
const modules = new Map([
    ['gi://Clutter', {default: {}}],
    ['gi://St', {default: {}}],
    ['gi://Meta', {default: {WindowType: {DESKTOP: 1}, LaterType: {BEFORE_REDRAW: 5}}}],
    ['resource:///org/gnome/shell/ui/main.js', {layoutManager: {untrackChrome() {}}}],
    ['./snapshot.mjs', {upcoming() {}, remaining() {}, urgency() {}}],
]);
const filename = process.env.TECHPIE_CARD_MODULE ??
    new URL('../gnome/desktopCard.js', import.meta.url);
const module = new vm.SourceTextModule(readFileSync(filename, 'utf8'), {context});
await module.link(specifier => {
    const exports = modules.get(specifier);
    assert.ok(exports, `unexpected dependency: ${specifier}`);
    return new vm.SyntheticModule(Object.keys(exports), function () {
        for (const [key, value] of Object.entries(exports)) this.setExport(key, value);
    }, {context});
});
await module.evaluate();
const {DesktopCard} = module.namespace;

function fixture() {
    pending.clear();
    const window = (type, shown = true) => ({visible: shown, mapped: shown,
        get_meta_window: () => ({get_window_type: () => type})});
    const hiddenApp = window(0, false);
    const desktop = window(1);
    const visibleApp = window(0);
    const actor = {destroy() { this.destroyed = true; }};
    const children = [hiddenApp, actor, desktop, visibleApp];
    const move = (child, sibling, offset) => {
        children.splice(children.indexOf(child), 1);
        const index = sibling ? children.indexOf(sibling) + offset : children.length;
        children.splice(index, 0, child);
    };
    const card = Object.create(DesktopCard.prototype);
    Object.assign(card, {actor, _signals: [], _windowGroup: {
        get_children: () => children,
        set_child_below_sibling: (a, sibling) => move(a, sibling, 0),
        set_child_above_sibling: (a, sibling) => move(a, sibling, 1),
    }});
    const paint = () => {
        const callbacks = [...pending.values()]; pending.clear();
        for (const callback of callbacks) callback();
    };
    return {card, actor, children, hiddenApp, desktop, visibleApp, paint};
}

test('a minimized actor before DING never pulls the card underneath DING', () => {
    const f = fixture();
    f.card._restack();
    assert.ok(f.children.indexOf(f.actor) > f.children.indexOf(f.desktop));
    assert.ok(f.children.indexOf(f.actor) < f.children.indexOf(f.visibleApp));
});

test('restacking runs after compositor stack changes, before painting', () => {
    const f = fixture();
    f.card._queueRestack();
    assert.equal(pending.size, 1);
    assert.ok(f.children.indexOf(f.actor) < f.children.indexOf(f.desktop));
    f.children.splice(f.children.indexOf(f.actor), 1);
    f.children.unshift(f.actor); // Mutter overwrites the order after restacked.
    f.paint();
    assert.ok(f.children.indexOf(f.actor) > f.children.indexOf(f.desktop));
    assert.ok(f.children.indexOf(f.actor) < f.children.indexOf(f.visibleApp));
});

test('coalesces repeated events and allows a later restack', () => {
    const f = fixture();
    for (let i = 0; i < 20; i++) f.card._queueRestack();
    assert.equal(pending.size, 1);
    f.paint();
    f.card._queueRestack();
    assert.equal(pending.size, 1);
});

test('with all apps minimized the card stays above the desktop', () => {
    const f = fixture();
    f.visibleApp.visible = f.visibleApp.mapped = false;
    f.card._restack();
    assert.ok(f.children.indexOf(f.actor) > f.children.indexOf(f.desktop));
});

test('destroy cancels queued work and never schedules another callback', () => {
    const f = fixture();
    f.card._queueRestack();
    f.card.destroy();
    assert.equal(pending.size, 0);
    assert.equal(f.actor.destroyed, true);
    f.card._queueRestack();
    assert.equal(pending.size, 0);
});
