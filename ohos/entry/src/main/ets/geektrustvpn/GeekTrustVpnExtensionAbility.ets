/**
 * The system-wide shape of the campus tunnel: an interface the whole device
 * routes through, for the destinations the policy authorizes.
 *
 * This ability owns the descriptor — only a VPN extension can create one — so it
 * owns the engine too, through the NAPI shim `libgeektrust_vpn.so` (the core
 * engine is a c-shared library ArkTS cannot call directly). The app asks for a
 * session by writing the state file and starting this ability; everything the
 * engine refuses is written back into that file rather than guessed at.
 */

import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import connection from '@ohos.net.connection';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import engine from 'libgeektrust_vpn.so';
import {
  GeekTrustVpnStateFile,
  markStopped,
  readState,
  writeVerdict,
} from './GeekTrustVpnState';
import { gatewaysOf, routesWithoutGateways } from './GeekTrustVpnRoutes';

const DOMAIN: number = 0x0000;
const TAG: string = 'GeekTrustVpn';

/** How long the engine is given to dial the gateway before the attempt fails. */
const ENGINE_TIMEOUT_MS: number = 20000;
const ENGINE_POLL_MS: number = 150;

/**
 * How often the record's copy of the engine's counters is refreshed while the
 * tunnel is up. The app re-reads the record about once a second, so anything
 * slower than this is a panel that lags a live tunnel.
 */
const ENGINE_REFRESH_MS: number = 5000;

/**
 * Waits for the engine to report a live tunnel. It dials the gateway in the
 * background, so its address (`vip`) is unknown until then — and
 * `geektrust_attach_tun_fd` refuses an attachment before that, on purpose.
 *
 * `status()` is matched as text rather than parsed: ArkTS refuses `any`, and
 * `JSON.parse` is typed as one, while the engine's own JSON is stable
 * (`{"alive":true,...}`).
 */
async function waitForEngine(): Promise<boolean> {
  const deadline = Date.now() + ENGINE_TIMEOUT_MS;
  while (Date.now() < deadline) {
    try {
      const status = engine.status();
      hilog.info(DOMAIN, TAG, 'engine status: %{public}s', status);
      if (status.includes('"alive":true')) {
        return true;
      }
    } catch (error) {
      // The engine has an opinion; keep waiting until the deadline.
    }
    await new Promise<void>((resolve) => setTimeout(resolve, ENGINE_POLL_MS));
  }
  return false;
}

/** The interface's own address. Private and distinct from the bind tunnel's. */
const TUN_ADDRESS: string = '10.111.223.1';
const ADDRESS_FAMILY_IPV4: number = 1;
const DEFAULT_MTU: number = 1400;

function routeTo(cidr: string): connection.RouteInfo {
  const slash = cidr.indexOf('/');
  const address = slash < 0 ? cidr : cidr.substring(0, slash);
  const prefixLength = slash < 0 ? 32 : Number.parseInt(cidr.substring(slash + 1), 10);
  return {
    interface: '',
    destination: {
      address: { address: address, family: ADDRESS_FAMILY_IPV4 },
      prefixLength: prefixLength,
    },
    gateway: { address: '0.0.0.0', family: ADDRESS_FAMILY_IPV4 },
    hasGateway: false,
    isDefaultRoute: false,
  };
}

/**
 * The resolvers of the network this interface sits above.
 *
 * An interface that declares none becomes a default network with nowhere to ask,
 * and every lookup on the device then fails — the controller's included. Measured
 * on the Android side of this same tunnel; the hazard is the platform's, not that
 * one's.
 */
async function underlyingDnsServers(): Promise<string[]> {
  try {
    const net = await connection.getDefaultNet();
    const properties = await connection.getConnectionProperties(net);
    const addresses: string[] = [];
    for (const entry of properties.dnses ?? []) {
      addresses.push(entry.address);
    }
    return addresses;
  } catch (error) {
    hilog.warn(
      DOMAIN, TAG,
      'underlying resolvers unreadable: %{public}s',
      JSON.stringify(error),
    );
    return [];
  }
}

export default class GeekTrustVpnAbility extends VpnExtensionAbility {
  private connection: vpnExtension.VpnConnection | null = null;
  private up: boolean = false;
  private refreshTimer: number = -1;

  async onCreate(want: Want): Promise<void> {
    const filesDir = this.context.filesDir;
    const state = readState(filesDir);
    if (state === null) {
      hilog.error(DOMAIN, TAG, 'onCreate with no request on disk');
      return;
    }
    try {
      // Match ohtailscale's lifecycle: the Go engine must establish its own
      // outbound path before the OS starts routing campus ranges into the VPN.
      // Otherwise the first gateway dial can be captured by the interface it is
      // trying to create and the engine never reaches alive.
      this.connection = vpnExtension.createVpnConnection(this.context);
      engine.start(state.sessionJson, state.policyJson);
      hilog.info(DOMAIN, TAG, 'engine started: %{public}s', engine.version());
      if (!await waitForEngine()) {
        throw new Error(
          'the engine never reported a live tunnel before VPN creation: ' +
            engine.status(),
        );
      }
      hilog.info(DOMAIN, TAG, 'engine alive before VPN creation');
      // The engine is the only thing that knows the flattened gateway list (the
      // app's session has never carried it), and a gateway covered by these
      // routes is captured by the very interface they configure — see
      // GeekTrustVpnRoutes. Read them off the engine's own status.
      const gateways = gatewaysOf(engine.status());
      const routes = routesWithoutGateways(state.routes, gateways);
      // An interface that declares no resolver becomes a default network with
      // nowhere to ask, and then every lookup on the device fails — the
      // controller's included (measured on the Android side of this tunnel, and
      // the same hazard here). The network under this one has resolvers that
      // work, so they are carried when the policy names none.
      const dns: string[] = state.dns.length > 0 ? state.dns : await underlyingDnsServers();
      hilog.info(
        DOMAIN, TAG,
        'vpn inputs routes=%{public}s gateways=%{public}s dns=%{public}s',
        JSON.stringify(routes), JSON.stringify(gateways), JSON.stringify(dns),
      );

      const config: vpnExtension.VpnConfig = {
        addresses: [
          {
            address: { address: TUN_ADDRESS, family: ADDRESS_FAMILY_IPV4 },
            prefixLength: 32,
          },
        ],
        routes: [routeTo(TUN_ADDRESS)].concat(routes.map(routeTo)),
        dnsAddresses: dns,
        mtu: DEFAULT_MTU,
        isIPv4Accepted: true,
        // The engine carries IPv4 only; capturing IPv6 would black-hole it.
        isIPv6Accepted: false,
        isBlocking: false,
      };
      hilog.info(DOMAIN, TAG, 'creating the tunnel: %{public}s', JSON.stringify(config));
      const tunFd = await this.connection.create(config);
      hilog.info(DOMAIN, TAG, 'tunnel is up, tun fd = %{public}d', tunFd);

      // Protect only the extension process. Its gateway sockets must stay on
      // the underlying network; app/WebView traffic must remain unprotected so
      // it can enter this VPN.
      await this.connection.protectProcessNet();
      hilog.info(DOMAIN, TAG, 'this process bypasses its own tunnel');
      // Raising the interface can cut the gateway connection that was
      // established before it: those packets now belong to the tunnel they
      // just raised, and the engine's own tunnel dies with them (a device log
      // showed exactly that — alive, then "no live tunnel yet" at attach,
      // 70ms after the interface came up). The supervisor redials over the
      // protected path, so what has to be alive when the descriptor is
      // attached is the tunnel *after* the interface, not the one before it.
      if (!await waitForEngine()) {
        throw new Error(
          'the engine brought no tunnel back after the interface came up: ' +
            engine.status(),
        );
      }
      engine.attachTunFd(tunFd);
      hilog.info(DOMAIN, TAG, 'tunnel attached');
      this.up = true;
      writeVerdict(filesDir, state, 'active', engine.status(), '');
      this.watchEngine(filesDir, state);
    } catch (error) {
      const failure = error as BusinessError;
      // 2200001 / 401 is the user declining the system dialog; everything else
      // is a configuration or engine failure.
      const denied = failure.code === 2200001 || failure.code === 401;
      // JSON.stringify on these errors prints "{}" — the message is on the
      // object, and without it a device log says nothing at all.
      const reason = `${failure.code ?? ''} ${failure.message ?? ''}`.trim() ||
        String(error);
      hilog.error(DOMAIN, TAG, 'cannot raise the tunnel: %{public}s', reason);
      writeVerdict(filesDir, state, 'failed', '', denied ? 'denied' : reason);
      this.teardown();
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    // Order matters: the refresh timer is stopped with the tunnel, and only then
    // is the record marked stopped, so nothing can write `active` after it.
    this.teardown();
    // The interface goes with this ability, so the record must not outlive it.
    markStopped(this.context.filesDir);
  }

  /**
   * Keeps the record's copy of the engine's counters current.
   *
   * The verdict is a snapshot, and the counters in it are zero at the moment a
   * tunnel comes up — the interface has carried nothing yet. Left at that, the
   * app's diagnostics panel shows a field of zeros over a tunnel that is moving
   * traffic, which reads as a tunnel doing nothing at all.
   */
  private watchEngine(filesDir: string, state: GeekTrustVpnStateFile): void {
    this.stopWatching();
    this.refreshTimer = setInterval(() => {
      if (!this.up) {
        return;
      }
      try {
        writeVerdict(filesDir, state, 'active', engine.status(), '');
      } catch (error) {
        hilog.warn(
          DOMAIN, TAG,
          'engine status unreadable: %{public}s',
          JSON.stringify(error),
        );
      }
    }, ENGINE_REFRESH_MS);
  }

  private stopWatching(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private teardown(): void {
    this.stopWatching();
    if (this.up) {
      try {
        this.connection?.destroy();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'destroy failed: %{public}s', JSON.stringify(error));
      }
      this.connection = null;
      this.up = false;
    }
    try {
      engine.stop();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'engine stop failed: %{public}s', JSON.stringify(error));
    }
  }
}
