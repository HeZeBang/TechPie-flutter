/**
 * The record of what the bind tunnel is doing, shared between the two processes
 * that care about it: the VPN extension ability (which runs in its own process
 * and owns the tunnel) and the app (which starts, stops and reports on it).
 *
 * It is a file rather than preferences on purpose — preferences cache in memory
 * per process, so the app would keep reading the value it last wrote while the
 * extension process was the one changing it.
 *
 * The counters are for diagnosis: a tunnel that says `active` with `reads` stuck
 * at zero has an interface nothing is arriving on, which is a different fault
 * from one that answers wrongly.
 */

import fs from '@ohos.file.fs';

const STATE_FILE = 'ecard_bind_state.json';

/** `requested` until the extension has an opinion; then one of the others. */
export type EcardBindStateStatus = 'requested' | 'active' | 'denied' | 'failed';

export interface EcardBindStateFile {
  status: EcardBindStateStatus;
  /** The name the tunnel answers for. */
  host: string;
  /** The address it answers with. */
  ip: string;
  /** Packets read off the interface. */
  reads: number;
  /** Queries answered from the hijacked name's own A record. */
  answered: number;
  /** Queries relayed to the upstream resolver. */
  forwarded: number;
  /** Why the tunnel stopped, when it stopped on its own. */
  error: string;
  /** When this record was written, in milliseconds. */
  at: number;
}

export function writeState(
  filesDir: string,
  status: EcardBindStateStatus,
  host: string,
  ip: string,
  error: string = '',
): void {
  writeRecord(filesDir, {
    status: status,
    host: host,
    ip: ip,
    reads: 0,
    answered: 0,
    forwarded: 0,
    error: error,
    at: Date.now(),
  });
}

/** Updates the counters of the record that is already there. */
export function recordStats(
  filesDir: string,
  reads: number,
  answered: number,
  forwarded: number,
  error: string,
): void {
  const current = readState(filesDir);
  if (current === null) {
    return;
  }
  current.reads = reads;
  current.answered = answered;
  current.forwarded = forwarded;
  current.error = error;
  current.at = Date.now();
  writeRecord(filesDir, current);
}

/** The record, or null when there is none (or it is unreadable). */
export function readState(filesDir: string): EcardBindStateFile | null {
  const path = filesDir + '/' + STATE_FILE;
  let file: fs.File | null = null;
  try {
    const stat = fs.statSync(path);
    if (stat.size <= 0) {
      return null;
    }
    file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(stat.size);
    const read = fs.readSync(file.fd, buffer);
    if (read <= 0) {
      return null;
    }
    return JSON.parse(bufferToString(buffer, read)) as EcardBindStateFile;
  } catch (error) {
    return null;
  } finally {
    if (file !== null) {
      fs.closeSync(file);
    }
  }
}

export function clearState(filesDir: string): void {
  try {
    fs.unlinkSync(filesDir + '/' + STATE_FILE);
  } catch (error) {
    // Already gone: nothing to clear.
  }
}

function writeRecord(filesDir: string, record: EcardBindStateFile): void {
  const path = filesDir + '/' + STATE_FILE;
  const file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, JSON.stringify(record));
  } finally {
    fs.closeSync(file);
  }
}

function bufferToString(buffer: ArrayBuffer, length: number): string {
  const bytes = new Uint8Array(buffer, 0, length);
  let text = '';
  for (let index = 0; index < bytes.length; index++) {
    text += String.fromCharCode(bytes[index]);
  }
  return text;
}
