export const MAX_BYTES = 262144;
export const MAX_ITEMS = 512;
const timestamp = value => typeof value === 'number' && Number.isFinite(value) &&
    value >= 0 && value <= 253402300799;
const text = value => typeof value === 'string' && new TextEncoder().encode(value).length <= 4096;

// Keep this parser independent of Shell/Qt so fixtures run in Node and GJS.
export function decodeSnapshot(json) {
    if (typeof json !== 'string' || new TextEncoder().encode(json).length > MAX_BYTES)
        throw new Error('Snapshot is too large');
    const snapshot = JSON.parse(json);
    if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot) ||
        Object.keys(snapshot).sort().join(',') !== 'items,schemaVersion,writtenAt' ||
        snapshot.schemaVersion !== 1 || !timestamp(snapshot.writtenAt) ||
        !Array.isArray(snapshot.items) || snapshot.items.length > MAX_ITEMS)
        throw new Error('Invalid snapshot');
    const ids = new Set();
    for (const item of snapshot.items) {
        if (!item || typeof item !== 'object' || Array.isArray(item) ||
            Object.keys(item).sort().join(',') !== 'course,dueAt,id,kind,title' ||
            !text(item.id) || !item.id || ids.has(item.id) ||
            !['assignment', 'exam'].includes(item.kind) || !text(item.title) ||
            !text(item.course) || !timestamp(item.dueAt))
            throw new Error('Invalid item');
        ids.add(item.id);
    }
    return snapshot;
}

export function upcoming(snapshot, now = Date.now() / 1000, limit = 8) {
    return snapshot.items.filter(item => item.dueAt > now)
        .sort((a, b) => a.dueAt - b.dueAt || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
        .slice(0, Math.max(0, limit));
}

export function remaining(dueAt, now = Date.now() / 1000) {
    const hours = Math.floor((dueAt - now) / 3600);
    if (dueAt <= now) return '';
    if (hours === 0) return '<1h';
    return hours < 24 ? `${hours}h` : `${Math.floor(hours / 24)}d ${hours % 24}h`;
}

export function urgency(dueAt, now = Date.now() / 1000) {
    const seconds = dueAt - now;
    if (seconds <= 0) return 'normal';
    if (seconds <= 12 * 3600) return 'urgent';
    return seconds <= 36 * 3600 ? 'soon' : 'normal';
}
