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
import { clearState, readState, updateStatus } from './GeekTrustVpnState';

const DOMAIN: number = 0x0000;
const TAG: string = 'GeekTrustVpn';

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

export default class GeekTrustVpnAbility extends VpnExtensionAbility {
  private connection: vpnExtension.VpnConnection | null = null;
  private up: boolean = false;

  async onCreate(want: Want): Promise<void> {
    const filesDir = this.context.filesDir;
    const state = readState(filesDir);
    if (state === null) {
      hilog.error(DOMAIN, TAG, 'onCreate with no request on disk');
      return;
    }
    try {
      // The engine first: it needs the session and the policy before any packet
      // can be authorized, and it must refuse before an interface exists.
      engine.start(state.sessionJson, state.policyJson);
      hilog.info(DOMAIN, TAG, 'engine up: %{public}s', engine.version());

      this.connection = vpnExtension.createVpnConnection(this.context);
      const config: vpnExtension.VpnConfig = {
        addresses: [
          {
            address: { address: TUN_ADDRESS, family: ADDRESS_FAMILY_IPV4 },
            prefixLength: 32,
          },
        ],
        routes: [routeTo(TUN_ADDRESS)].concat(state.routes.map(routeTo)),
        dnsAddresses: state.dns,
        mtu: DEFAULT_MTU,
        isIPv4Accepted: true,
        // The engine carries IPv4 only; capturing IPv6 would black-hole it.
        isIPv6Accepted: false,
        // Everything that is not routed above keeps the underlying network, and
        // the engine authorizes what is.
        isBlocking: false,
      };
      hilog.info(DOMAIN, TAG, 'creating the tunnel: %{public}s', JSON.stringify(config));
      const tunFd = await this.connection.create(config);
      hilog.info(DOMAIN, TAG, 'tunnel is up, tun fd = %{public}d', tunFd);
      engine.attachTunFd(tunFd);
      this.up = true;
      updateStatus(filesDir, 'active', engine.status(), '');
    } catch (error) {
      const failure = error as BusinessError;
      // 2200001 / 401 is the user declining the system dialog; everything else
      // is a configuration or engine failure.
      const denied = failure.code === 2200001 || failure.code === 401;
      const reason = JSON.stringify(error);
      hilog.error(DOMAIN, TAG, 'cannot raise the tunnel: %{public}s', reason);
      updateStatus(filesDir, 'failed', '', denied ? 'denied' : reason);
      this.teardown();
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.teardown();
  }

  private teardown(): void {
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
