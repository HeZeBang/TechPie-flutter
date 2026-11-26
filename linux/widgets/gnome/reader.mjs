import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

// Bound allocation even if another local process replaces the snapshot with a
// large file. read_bytes_async may return a short read before EOF.
export async function readBounded(file, maximum, cancellable) {
    const stream = await new Promise((resolve, reject) => {
        file.read_async(GLib.PRIORITY_DEFAULT, cancellable, (source, result) => {
            try { resolve(source.read_finish(result)); }
            catch (error) { reject(error); }
        });
    });
    try {
        const parts = [];
        let length = 0;
        while (length <= maximum) {
            const bytes = await new Promise((resolve, reject) => {
                stream.read_bytes_async(Math.min(65536, maximum + 1 - length),
                    GLib.PRIORITY_DEFAULT, cancellable, (input, result) => {
                        try { resolve(input.read_bytes_finish(result).get_data()); }
                        catch (error) { reject(error); }
                    });
            });
            if (!bytes.length) break;
            parts.push(bytes);
            length += bytes.length;
        }
        if (length > maximum) throw new Error('Snapshot too large');
        const result = new Uint8Array(length);
        let offset = 0;
        for (const bytes of parts) { result.set(bytes, offset); offset += bytes.length; }
        return new TextDecoder('utf-8', {fatal: true}).decode(result);
    } finally {
        await new Promise(resolve => stream.close_async(GLib.PRIORITY_DEFAULT, null, (input, result) => {
            try { input.close_finish(result); } catch (_) { /* Closing during disable is harmless. */ }
            resolve();
        }));
    }
}
