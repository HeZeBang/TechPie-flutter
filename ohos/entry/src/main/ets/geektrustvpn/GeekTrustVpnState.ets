/**
 * The record of what the system tunnel is doing, shared between the two
 * processes that care: the VPN extension ability (which runs in its own process,
 * owns the interface and drives the engine) and the app (which starts, stops and
 * reports on it).
 *
 * A file rather than preferences, for the same reason the eCard bind tunnel uses
 * one: preferences cache in memory per process, so the app would keep reading
 * what it last wrote while the extension was the one changing it.
 */

import fs from '@ohos.file.fs';

const STATE_FILE = 'geektrust_vpn_state.json';

/** `requested` until the extension has an opinion; then one of the others. */
export type GeekTrustVpnStatus = 'requested' | 'active' | 'failed';

export interface GeekTrustVpnStateFile {
  status: GeekTrustVpnStatus;
  /** The control plane's session JSON, handed to the engine verbatim. */
  sessionJson: string;
  /** The controller's routing policy, handed to the engine verbatim. */
  policyJson: string;
  /** Destinations to route into the tunnel, as CIDR strings. */
  routes: string[];
  /** Resolvers to hand the device (the tunnel's own, reachable through it). */
  dns: string[];
  /** The engine's own status JSON, once it is up. */
  engineStatus: string;
  error: string;
  at: number;
}

/** Writes the request the extension will pick up. */
export function writeRequest(
  filesDir: string,
  sessionJson: string,
  policyJson: string,
  routes: string[],
  dns: string[],
): void {
  writeRecord(filesDir, {
    status: 'requested',
    sessionJson: sessionJson,
    policyJson: policyJson,
    routes: routes,
    dns: dns,
    engineStatus: '',
    error: '',
    at: Date.now(),
  });
}

/** The extension's verdict on the request it is running.
 *
 * `base` is the record the extension read when it started, so a verdict needs
 * no second read: an `updateStatus` that re-read the file and silently did
 * nothing when the read failed left the app polling a `requested` state until
 * its timeout, and a tunnel that was up looked exactly like one that never
 * started. */
export function writeVerdict(
  filesDir: string,
  base: GeekTrustVpnStateFile,
  status: GeekTrustVpnStatus,
  engineStatus: string,
  error: string,
): void {
  base.status = status;
  base.engineStatus = engineStatus;
  base.error = error;
  base.at = Date.now();
  writeRecord(filesDir, base);
}

/** The record, or null when there is none (or it is unreadable). */
export function readState(filesDir: string): GeekTrustVpnStateFile | null {
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
    return JSON.parse(bufferToString(buffer, read)) as GeekTrustVpnStateFile;
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

function writeRecord(filesDir: string, record: GeekTrustVpnStateFile): void {
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
