/**
 * The OHOS side of the eCard bind tunnel: a DNS-only VPN.
 *
 * The interface carries a /32 route for its own address and another for the
 * resolver address it hands out, and this ability answers the resulting queries
 * itself. Only name resolution changes, for every app: their TCP keeps leaving
 * through the underlying network, because nothing else is routed into this
 * tunnel. No app list is configured on purpose — the lookup that matters can
 * come from any of them, and a list would quietly stop covering the ones it does
 * not name.
 *
 * It is the same design as the Android service
 * (android/.../ecardbind/EcardBindVpnService.kt), including the reason the
 * resolver address is routed rather than assigned to the interface — that is
 * also what Tailscale's HarmonyOS port does with its own 100.100.100.100, where
 * the address is not one of the interface's `addresses` either.
 *
 * One thing deliberately differs. The reference Tailscale tunnel protects its
 * whole process with `protectProcessNet()`; here that would defeat the tunnel,
 * because this app is itself in the trusted list — its own lookup of the eCard
 * host has to go through the tunnel. No protection is needed either: the only
 * routes are the two /32s, so the upstream query this ability sends to the real
 * resolver leaves through the underlying network and cannot loop back.
 *
 * Packets are read and written by libecardbind_reader.so: the interface is a
 * non-seekable character device, and the OHOS VPN guide's own sample does its
 * packet I/O natively for the same reason.
 */

import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import connection from '@ohos.net.connection';
import socket from '@ohos.net.socket';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import reader from 'libecardbind_reader.so';
import { EcardBindStateFile, clearState, readState, recordStats, writeState } from './EcardBindState';
import { EcardBindDatagram, buildUdpReply, parseUdp, DNS_PORT } from './EcardBindPackets';
import {
  EcardBindQuestion,
  RCODE_SERVFAIL,
  TYPE_A,
  buildReply,
  parseQuestion,
  queryId,
} from './EcardBindDns';

const DOMAIN: number = 0x0000;
const TAG: string = 'EcardBindVpn';

/** The interface's own address. */
const TUN_ADDRESS: string = '10.111.222.1';
/**
 * The address the tunnel answers DNS for. It sits next to [TUN_ADDRESS] but is
 * deliberately never assigned to the interface: see the config below.
 */
const DNS_ADDRESS: string = '10.111.222.2';
const FALLBACK_UPSTREAM: string = '223.5.5.5';
const DEFAULT_MTU: number = 1500;
/** One IP packet has to fit the interface MTU, headers included. */
const MAX_REPLY_PACKET: number = 1500;
const UPSTREAM_TIMEOUT_MS: number = 4000;
const ADDRESS_FAMILY_IPV4: number = 1;
/** How many queries may wait on the upstream at once. */
const MAX_PENDING_QUERIES: number = 64;

/** One query in flight to the upstream resolver. */
interface PendingQuery {
  resolve: (answer: Uint8Array | null) => void;
}

export default class EcardBindVpnAbility extends VpnExtensionAbility {
  private connection: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;
  private serving: boolean = false;
  private host: string = '';
  private answerText: string = '';
  private answer: number[] = [];
  private relay: socket.UDPSocket | null = null;
  private upstream: string = FALLBACK_UPSTREAM;
  private reads: number = 0;
  private answered: number = 0;
  private forwarded: number = 0;
  private lastError: string = '';
  /** Sources we have already seen asking: the interface shows no app identity. */
  private clients: Set<string> = new Set<string>();
  /** Queries waiting on the upstream, by their DNS transaction id. */
  private pending: Map<number, PendingQuery> = new Map<number, PendingQuery>();

  onCreate(want: Want): void {
    const request = readState(this.context.filesDir);
    if (request === null || request.host.length === 0 || request.ip.length === 0) {
      hilog.error(DOMAIN, TAG, 'no bind request in the state file; nothing to serve');
      return;
    }
    this.answer = parseIpv4(request.ip);
    if (this.answer.length !== 4) {
      hilog.error(DOMAIN, TAG, 'answer is not an IPv4 address: %{public}s', request.ip);
      return;
    }
    this.host = request.host.toLowerCase();
    this.answerText = request.ip;
    hilog.info(DOMAIN, TAG, 'serving %{public}s as %{public}s', this.host, this.answerText);
    this.start();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy (reads=%{public}d answered=%{public}d forwarded=%{public}d)',
      this.reads, this.answered, this.forwarded);
    this.teardown();
    // A verdict the app has not read yet stays in place: a start that was
    // refused has nothing to tear down, and the app still has to hear why.
    const state = readState(this.context.filesDir);
    if (state === null || state.status === 'active' || state.status === 'requested') {
      clearState(this.context.filesDir);
    }
  }

  private async start(): Promise<void> {
    try {
      // Read the upstream resolver before the interface exists: afterwards this
      // app's own lookups are answered by the tunnel.
      this.upstream = await underlyingResolver();
      hilog.info(DOMAIN, TAG, 'upstream resolver is %{public}s', this.upstream);

      this.connection = vpnExtension.createVpnConnection(this.context);
      const config: vpnExtension.VpnConfig = {
        addresses: [
          {
            address: { address: TUN_ADDRESS, family: ADDRESS_FAMILY_IPV4 },
            prefixLength: 32,
          },
        ],
        routes: [
          routeTo(TUN_ADDRESS),
          routeTo(DNS_ADDRESS),
        ],
        dnsAddresses: [DNS_ADDRESS],
        mtu: DEFAULT_MTU,
        isIPv4Accepted: true,
        // IPv6 is left on the underlying network rather than captured and then
        // black-holed: only name resolution is hijacked here.
        isIPv6Accepted: false,
        // Every app keeps its ordinary network for everything that is not
        // routed into this tunnel — which is everything but DNS. With no
        // trustedApplications list the tunnel applies to all of them, which is
        // also what Tailscale's HarmonyOS port relies on.
        isBlocking: false,
      };
      hilog.info(DOMAIN, TAG, 'creating the tunnel: %{public}s', JSON.stringify(config));
      const tunFd = await this.connection.create(config);
      this.tunFd = tunFd;
      hilog.info(DOMAIN, TAG, 'tunnel is up, tun fd = %{public}d', tunFd);
      await this.openRelay();
      this.serving = true;
      writeState(this.context.filesDir, 'active', this.host, this.answerText);
      this.startReading();
    } catch (error) {
      const failure = error as BusinessError;
      // Without the authorization there is no interface to read; everything
      // else is a configuration or platform failure.
      const denied = failure.code !== 2200001 && failure.code !== 401;
      const reason = JSON.stringify(error);
      hilog.error(DOMAIN, TAG, 'cannot serve the bind host: %{public}s', reason);
      writeState(
        this.context.filesDir,
        denied ? 'denied' : 'failed',
        this.host,
        this.answerText,
        reason,
      );
      this.teardown();
    }
  }

  private startReading(): void {
    reader.startReading(
      this.tunFd,
      (packet: ArrayBuffer) => {
        this.onPacket(packet);
      },
      (message: string) => {
        this.onReadFailure(message);
      },
    );
    hilog.info(DOMAIN, TAG, 'reading packets from the interface');
  }

  /** Drops the interface and stops reading from it. */
  private teardown(): void {
    this.serving = false;
    for (const waiting of this.pending.values()) {
      waiting.resolve(null);
    }
    this.pending.clear();
    reader.stopReading();
    this.relay?.close();
    this.relay = null;
    const connection = this.connection;
    this.connection = null;
    if (connection !== null) {
      connection.destroy().catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'destroy failed: %{public}s', JSON.stringify(error));
      });
    }
  }

  private onPacket(packet: ArrayBuffer): void {
    this.reads += 1;
    if (this.reads === 1) {
      // The first packet is the proof that the interface is readable at all.
      hilog.info(DOMAIN, TAG, 'first packet off the interface');
      this.publishStats();
    }
    // Each packet is answered on its own. A query that has to wait on the
    // upstream must not hold up the ones behind it — the hijacked name is
    // usually asked for while some unrelated name is still in flight.
    this.servePacket(new Uint8Array(packet));
  }

  /** Parses one packet and injects whatever reply it is owed. */
  private async servePacket(packet: Uint8Array): Promise<void> {
    try {
      const reply = await this.replyTo(packet, packet.length);
      if (reply === null || !this.serving) {
        return;
      }
      const written = reader.writePacket(
        this.tunFd,
        reply.buffer as ArrayBuffer,
        reply.length,
      );
      if (written < 0) {
        hilog.warn(DOMAIN, TAG, 'cannot inject the reply: errno=%{public}d', written);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'cannot answer a query: %{public}s', JSON.stringify(error));
    }
  }

  /** The interface stopped being readable: the tunnel cannot answer anything. */
  private onReadFailure(message: string): void {
    this.lastError = message;
    hilog.error(DOMAIN, TAG, 'cannot read the interface: %{public}s', message);
    if (!this.serving) {
      return;
    }
    this.serving = false;
    const filesDir = this.context.filesDir;
    recordStats(filesDir, this.reads, this.answered, this.forwarded, message);
    writeState(filesDir, 'failed', this.host, this.answerText, message);
    this.teardown();
  }

  private publishStats(): void {
    recordStats(this.context.filesDir, this.reads, this.answered, this.forwarded, this.lastError);
  }

  private async openRelay(): Promise<void> {
    const relay = socket.constructUDPSocketInstance();
    await relay.bind({ address: '0.0.0.0', family: ADDRESS_FAMILY_IPV4, port: 0 });
    relay.on('message', (info: socket.SocketMessageInfo) => {
      const answer = new Uint8Array(info.message);
      if (answer.length < 2) {
        return;
      }
      const id = queryId(answer);
      const waiting = this.pending.get(id);
      if (waiting === undefined) {
        return;
      }
      this.pending.delete(id);
      waiting.resolve(answer);
    });
    this.relay = relay;
  }

  /** The whole IPv4/UDP packet to inject, or null when nothing is owed. */
  private async replyTo(packet: Uint8Array, length: number): Promise<Uint8Array | null> {
    const datagram: EcardBindDatagram | null = parseUdp(packet, length);
    if (datagram === null || datagram.destinationPort !== DNS_PORT) {
      return null;
    }
    if (!sameAddress(datagram.destinationAddress, parseIpv4(DNS_ADDRESS))) {
      return null;
    }
    const payload = packet.subarray(
      datagram.payloadOffset,
      datagram.payloadOffset + datagram.payloadLength,
    );
    const question = parseQuestion(payload, payload.length);
    if (question === null) {
      return null;
    }
    const id = queryId(payload);
    const client = describeSource(datagram);
    const isNewClient = !this.clients.has(client);
    if (isNewClient) {
      this.clients.add(client);
      hilog.info(DOMAIN, TAG, 'new client %{public}s asks %{public}s/%{public}d',
        client, question.name, question.type);
    }

    let dnsReply: Uint8Array;
    if (question.name.toLowerCase() === this.host) {
      // The A record points at the mirror; every other type for this host
      // answers empty, so clients fall back to that A record.
      const address = question.type === TYPE_A ? this.answer : null;
      this.answered += 1;
      // The A answers are the ones that matter and the empty ones repeat with
      // every connection, so only the first of those is worth a line.
      if (address !== null || isNewClient) {
        hilog.info(DOMAIN, TAG, 'hijack %{public}s/%{public}d %{public}s -> %{public}s',
          question.name, question.type, client, address === null ? 'empty' : this.answerText);
      }
      dnsReply = buildReply(id, payload, question, address);
    } else {
      dnsReply = await this.forward(payload, id, question, client);
    }
    if (this.answered % 32 === 0 || this.forwarded % 32 === 0) {
      this.publishStats();
    }

    const reply = buildUdpReply(datagram, dnsReply);
    if (reply.length <= MAX_REPLY_PACKET) {
      return reply;
    }
    // Bigger than one interface write: hand back an empty truncated answer so
    // the resolver retries this over TCP, which leaves through the underlying
    // network instead of this tunnel.
    hilog.warn(DOMAIN, TAG, 'reply for %{public}s is too big; asking for TCP', question.name);
    return buildUdpReply(datagram, buildReply(id, payload, question, null, 0, true));
  }

  /** The upstream answer for a query the tunnel does not answer itself. */
  private async forward(
    payload: Uint8Array,
    id: number,
    question: EcardBindQuestion,
    client: string,
  ): Promise<Uint8Array> {
    const relay = this.relay;
    if (relay === null || this.pending.size >= MAX_PENDING_QUERIES) {
      return buildReply(id, payload, question, null, RCODE_SERVFAIL);
    }
    this.forwarded += 1;
    const answered = new Promise<Uint8Array | null>((resolve: (answer: Uint8Array | null) => void) => {
      this.pending.set(id, { resolve: resolve });
    });
    try {
      await relay.send({
        // Exactly the DNS message: `payload` is a view into the packet that came
        // off the interface, so its `buffer` is that whole IP packet — headers,
        // padding and all.
        data: payload.slice().buffer as ArrayBuffer,
        address: {
          address: this.upstream,
          family: ADDRESS_FAMILY_IPV4,
          port: DNS_PORT,
        },
      });
      const answer = await settledWithin(answered, UPSTREAM_TIMEOUT_MS);
      if (answer !== null) {
        return answer;
      }
      hilog.warn(DOMAIN, TAG, 'upstream %{public}s timed out for %{public}s (asked by %{public}s)',
        this.upstream, question.name, client);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'upstream %{public}s failed for %{public}s (asked by %{public}s): %{public}s',
        this.upstream, question.name, client, JSON.stringify(error));
    } finally {
      this.pending.delete(id);
    }
    // No answer in time: the client is better off retrying than waiting.
    return buildReply(id, payload, question, null, RCODE_SERVFAIL);
  }
}

/** A route that sends one address into this interface. */
function routeTo(address: string): connection.RouteInfo {
  return {
    interface: '',
    destination: {
      address: { address: address, family: ADDRESS_FAMILY_IPV4 },
      prefixLength: 32,
    },
    gateway: { address: '0.0.0.0', family: ADDRESS_FAMILY_IPV4 },
    hasGateway: false,
    isDefaultRoute: false,
  };
}

/** The resolver of the network underneath, or a public one if unreadable. */
async function underlyingResolver(): Promise<string> {
  try {
    const net = await connection.getDefaultNet();
    const properties = await connection.getConnectionProperties(net);
    for (const server of properties.dnses) {
      if (server.family !== ADDRESS_FAMILY_IPV4) {
        continue;
      }
      if (server.address === TUN_ADDRESS || server.address === DNS_ADDRESS) {
        continue;
      }
      return server.address;
    }
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'cannot read the underlying resolver: %{public}s',
      JSON.stringify(error));
  }
  return FALLBACK_UPSTREAM;
}

/** A dotted quad as four bytes, or an empty array when it is not one. */
function parseIpv4(text: string): number[] {
  const parts = text.split('.');
  if (parts.length !== 4) {
    return [];
  }
  const bytes: number[] = [];
  for (const part of parts) {
    const value = Number.parseInt(part, 10);
    if (Number.isNaN(value) || value < 0 || value > 255) {
      return [];
    }
    bytes.push(value);
  }
  return bytes;
}

/** "a.b.c.d:port" — the interface does not say which app a packet came from. */
function describeSource(datagram: EcardBindDatagram): string {
  const address = datagram.sourceAddress;
  return `${address[0]}.${address[1]}.${address[2]}.${address[3]}:${datagram.sourcePort}`;
}

function sameAddress(left: number[], right: number[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let index = 0; index < left.length; index++) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}

/** `pending`, or null when it has not settled within `ms`. */
function settledWithin(
  pending: Promise<Uint8Array | null>,
  ms: number,
): Promise<Uint8Array | null> {
  return new Promise<Uint8Array | null>((resolve: (answer: Uint8Array | null) => void) => {
    let done = false;
    const timer = setTimeout(() => {
      if (!done) {
        done = true;
        resolve(null);
      }
    }, ms);
    pending.then((answer: Uint8Array | null) => {
      if (!done) {
        done = true;
        clearTimeout(timer);
        resolve(answer);
      }
    });
  });
}
