/**
 * The aTrust tunnel's core engine, as an OpenHarmony VPN extension can reach it.
 *
 * The extension owns the interface descriptor, so it owns the engine too: this
 * module dlopens `libgeektrust.so` from the app's own libs directory and
 * forwards the four calls the VPN shape needs. Every call throws a JavaScript
 * error carrying the engine's own message when it refuses.
 */
declare namespace geektrustVpn {
  /**
   * Brings the tunnel up for a session and the controller's routing policy.
   * Both are JSON strings; the session is `{sid, device_id, username, base_url,
   * gateways, dns}` and the policy is the controller's `clientResource` body.
   */
  function start(sessionJson: string, policyJson: string): void;

  /**
   * Hands over the descriptor `VpnConnection.create()` returned. The engine
   * reads and writes packets on it.
   */
  function attachTunFd(fd: number): void;

  /** The engine's own status as JSON (`geektrust_status`). */
  function status(): string;

  /** Tears the tunnel down. Safe to call twice. */
  function stop(): void;

  /** The engine's provenance marker, `TECHPIE-GEEKTRUST=<abi>:<version>:<digest>`. */
  function version(): string;
}

export default geektrustVpn;
