import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import EventChannel, { EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import connection from '@ohos.net.connection';
import { BusinessError } from '@kit.BasicServicesKit';

export class CampusCardPlatformPlugin implements FlutterPlugin, MethodCallHandler {
  private methods: MethodChannel | null = null;
  private events: EventChannel | null = null;
  private network: connection.NetConnection | null = null;
  private sink: EventSink | null = null;

  getUniqueClassName(): string { return 'CampusCardPlatformPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.methods = new MethodChannel(binding.getBinaryMessenger(), 'techpie/campus_card');
    this.methods.setMethodCallHandler(this);
    this.events = new EventChannel(binding.getBinaryMessenger(), 'techpie/campus_card/connectivity');
    this.events.setStreamHandler({
      onListen: (_args: Object, sink: EventSink) => {
        this.stopListening();
        this.sink = sink;
        const network = connection.createNetConnection();
        this.network = network;
        network.on('netAvailable', () => { this.updateNetwork(network); });
        network.on('netLost', () => { this.updateNetwork(network); });
        network.register((error: BusinessError) => {
          if (this.network !== network) return;
          if (error) sink.error('NETWORK_LISTENER_FAILED', 'Cannot observe network state', null);
          else this.updateNetwork(network);
        });
      },
      onCancel: () => { this.stopListening(); }
    });
  }

  private updateNetwork(network: connection.NetConnection): void {
    connection.hasDefaultNet().then((online: boolean) => {
      if (this.network === network) this.sink?.success(online);
    }).catch(() => {
      if (this.network === network) this.sink?.success(false);
    });
  }

  private stopListening(): void {
    const network = this.network;
    this.network = null;
    this.sink = null;
    network?.unregister(() => {});
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'isOnline') {
      connection.hasDefaultNet().then((online: boolean) => result.success(online))
        .catch(() => result.error('NETWORK_STATE_FAILED', 'Cannot read network state', null));
    } else result.notImplemented();
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.stopListening();
    this.methods?.setMethodCallHandler(null);
    this.events?.setStreamHandler(null);
    this.methods = null;
    this.events = null;
  }
}
