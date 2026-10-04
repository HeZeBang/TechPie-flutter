/**
 * The route arithmetic the interface needs, and the one rule behind it.
 *
 * A gateway is where the tunnel begins, so it has to stay reachable *outside*
 * the interface that carries it. Routing it in turns the engine's own dial to it
 * into a flow over the tunnel being built, and the device side refuses that flow
 * by design (`ErrGatewayLoop`) — so the tunnel dies with the very interface it
 * created and never comes back. A device log showed exactly that:
 *
 *   tun TCP flow src=10.111.223.1:55468 dst=10.13.90.147:441
 *   tun TCP flow refused ... refusing to proxy a VPN gateway through its own tunnel
 *   gateway TLS connection failed ... gateway 119.78.254.241:441: EOF
 *
 * The gateways are campus addresses, so they fall inside the ranges the
 * interface routes; they cannot simply be left out of the list and are cut out
 * of the covering prefixes instead.
 *
 * `protectProcessNet()` is the documented way to keep a VPN's own traffic out of
 * itself, but it only protects sockets created *after* the call, and on the
 * device this was written for the sockets it did cover were still captured. The
 * routes are what has to be right.
 *
 * The Dart/Android implementation is `AtrustRouting.withoutGateways`, and
 * `test/atrust/route_vectors.json` is the shared golden contract for both
 * implementations. Keep the two functions behaviorally identical when either
 * side changes; the OHOS extension is a separate process and cannot call Dart.
 */

/** One IPv4 prefix: a base address and a length in bits. */
interface RoutePrefix {
  base: number;
  length: number;
}

/** The engine's own status, of which only the gateway list matters here. */
interface EngineStatus {
  gateways?: string[];
}

/**
 * `prefixes` with every IPv4 gateway in `gateways` cut out.
 *
 * `gateways` is the engine's `host:port` list, exactly as `geektrust_status`
 * reports it — the only place the flattened list exists, since the app's session
 * never carries it and expanding the policy is the engine's job. IPv6 entries
 * exclude nothing: the interface does not route IPv6.
 */
export function routesWithoutGateways(
  prefixes: string[],
  gateways: string[],
): string[] {
  const excluded = excludedAddresses(gateways);
  if (excluded.length === 0) {
    return prefixes;
  }
  const out: string[] = [];
  for (const prefix of prefixes) {
    const parsed = parsePrefix(prefix);
    if (parsed === null) {
      out.push(prefix);
      continue;
    }
    for (const kept of withoutHosts(parsed, excluded)) {
      out.push(kept);
    }
  }
  return out;
}

/** The IPv4 addresses in a `geektrust_status` gateway list. */
export function gatewaysOf(statusJson: string): string[] {
  try {
    const status = JSON.parse(statusJson) as EngineStatus;
    const gateways = status.gateways;
    return gateways === undefined ? [] : gateways;
  } catch (error) {
    return [];
  }
}

function excludedAddresses(gateways: string[]): number[] {
  const addresses: number[] = [];
  for (const gateway of gateways) {
    // `[v6]:port` is not an address this interface routes.
    if (gateway.startsWith('[')) {
      continue;
    }
    const colon = gateway.indexOf(':');
    const address = ipv4(colon < 0 ? gateway : gateway.substring(0, colon));
    if (address !== null) {
      addresses.push(address);
    }
  }
  return addresses;
}

/**
 * The prefixes inside `prefix` with every address in `excluded` removed.
 *
 * A route list has no "except", so an excluded address is removed by splitting
 * its covering prefix into the prefixes around it: the complement of one address
 * inside a /8 is at most 24 entries, and every address that is not excluded
 * stays routed.
 */
function withoutHosts(prefix: RoutePrefix, excluded: number[]): string[] {
  const pending: RoutePrefix[] = [prefix];
  const kept: RoutePrefix[] = [];
  while (pending.length > 0) {
    const current = pending.pop() as RoutePrefix;
    let holds = false;
    for (const address of excluded) {
      if (containsAddress(current, address)) {
        holds = true;
        break;
      }
    }
    if (!holds) {
      kept.push(current);
      continue;
    }
    // A /32 that is one of the excluded addresses has nothing left to route.
    if (current.length === 32) {
      continue;
    }
    const half = 1 << (31 - current.length);
    pending.push({ base: current.base, length: current.length + 1 });
    pending.push({ base: (current.base | half) >>> 0, length: current.length + 1 });
  }
  kept.sort((left: RoutePrefix, right: RoutePrefix): number =>
    left.base !== right.base
      ? left.base - right.base
      : left.length - right.length);
  return kept.map((entry: RoutePrefix): string =>
    `${formatAddress(entry.base)}/${entry.length}`);
}

function containsAddress(prefix: RoutePrefix, address: number): boolean {
  const mask = maskFor(prefix.length);
  return ((address & mask) >>> 0) === prefix.base;
}

function maskFor(length: number): number {
  return length === 0 ? 0 : (0xffffffff << (32 - length)) >>> 0;
}

function parsePrefix(text: string): RoutePrefix | null {
  const slash = text.indexOf('/');
  if (slash < 0) {
    return null;
  }
  const base = ipv4(text.substring(0, slash));
  const length = Number.parseInt(text.substring(slash + 1), 10);
  if (base === null || Number.isNaN(length) || length < 0 || length > 32) {
    return null;
  }
  return { base: (base & maskFor(length)) >>> 0, length: length };
}

function ipv4(text: string): number | null {
  const parts = text.split('.');
  if (parts.length !== 4) {
    return null;
  }
  let value = 0;
  for (const part of parts) {
    const octet = Number.parseInt(part, 10);
    if (Number.isNaN(octet) || octet < 0 || octet > 255) {
      return null;
    }
    value = ((value << 8) | octet) >>> 0;
  }
  return value;
}

function formatAddress(address: number): string {
  return `${(address >>> 24) & 0xff}.${(address >>> 16) & 0xff}.` +
    `${(address >>> 8) & 0xff}.${address & 0xff}`;
}
