import 'dart:async';

import 'package:flutter/material.dart';

import '../features/campus_card/core/errors/app_failure.dart';
import '../features/campus_card/domain/models/auth_models.dart';
import '../services/campus_card_service.dart';
import '../services/ecard_bind_hijack.dart';
import '../services/ecard_bind_service.dart';
import '../services/service_provider.dart';
import '../theme/tp_icons.dart';
import '../theme/tp_tokens.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_ecard_wizard.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/design_system/tp_card.dart';
import 'ecard_wizard_copy.dart';
import 'sync_settings_page.dart';

class CampusCardAccountPage extends StatefulWidget {
  const CampusCardAccountPage({super.key, this.fromCard = false});

  final bool fromCard;

  @override
  State<CampusCardAccountPage> createState() => _CampusCardAccountPageState();
}

class _CampusCardAccountPageState extends State<CampusCardAccountPage> with WidgetsBindingObserver {
  final _code = TextEditingController();
  final _openId = TextEditingController();
  EcardOpenIdChannel _channel = EcardOpenIdChannel.wechat;
  late final EcardBindService _binding;
  late final CampusCardService _card;
  late final Listenable _changes;
  bool _initialized = false;
  bool _ready = false;
  bool _reviewing = false;
  bool _justConnected = false;
  bool _busy = false;
  bool _starting = false;
  RedeemedOpenId? _pending;
  Object? _error;

  String _text(String en, String zh) =>
      View.of(context).platformDispatcher.locale.languageCode == 'zh' ? zh : en;

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final services = ServiceProvider.of(context);
    _binding = services.ecardBindService;
    _card = services.campusCardService;
    _changes = Listenable.merge([_card, _binding]);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run(_load));
  }

  Future<void> _load() async {
    await Future.wait([_card.refreshAccount(), _binding.refreshStatus()]);
    if (!_ready &&
        widget.fromCard &&
        !isDesktop() &&
        !_card.configured &&
        _binding.status == EcardBindHijackStatus.inactive) {
      _reviewing = true;
    }
    _ready = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_starting || _binding.hijackNeedsStop) {
      // The platform can finish starting after the system dismisses this route.
      unawaited(_binding.stopHijack().catchError((Object _) {}));
    }
    _code.dispose();
    _openId.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) _error = error;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPermission() async {
    _starting = true;
    try {
      final status = await _binding.startHijack();
      if (status == EcardBindHijackStatus.denied) {
        throw const AppFailure(FailureKind.permissionDenied, '未获得系统 VPN 授权');
      }
      if (status != EcardBindHijackStatus.active) {
        throw const AppFailure(FailureKind.unavailable, '临时连接未就绪，请重试');
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _cancel() async {
    if (_binding.hijackNeedsStop) await _binding.stopHijack();
    if (!mounted) return;
    _pending = null;
    _reviewing = false;
    _code.clear();
    _openId.clear();
  }

  Future<void> _redeem() async {
    // Always release the temporary connection, including on an invalid code.
    try {
      _pending = await _binding.redeem(_code.text);
    } finally {
      await _binding.stopHijack();
    }
    if (mounted) await _finishConnection();
  }

  Future<void> _finishConnection() async {
    final credential = _pending!;
    await _connect(credential.openId, channel: credential.channel);
  }

  Future<void> _connectManually() async {
    final openId = _openId.text.trim();
    final channel = _channel;
    OpenIdAuthCredential(openId: openId, channel: channel).validate();
    await _connect(openId, channel: channel);
  }

  Future<void> _connect(String openId, {required EcardOpenIdChannel channel}) async {
    await _binding.prepareCampusConnection();
    if (!mounted) return;
    if (!_card.configured) {
      await _card.connect(openId, channel: channel);
    }
    if (!mounted) return;
    _justConnected = true;
    _pending = null;
    _code.clear();
    _openId.clear();
    _reviewing = false;
  }

  Future<void> _openCloudSync() async {
    await pushAdaptivePage<void>(context, builder: (_) => const SyncSettingsPage());
    if (mounted) await _run(_load);
  }

  Future<void> _disconnect() async {
    final confirmed = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: _text('Disconnect this eCard?', '断开校园卡连接？'),
      message: _text('You can connect your card again later.', '你可以稍后重新连接校园卡。'),
      actions: [
        AdaptiveAlertAction(label: _text('Keep connected', '保持连接'), value: false),
        AdaptiveAlertAction(label: _text('Disconnect', '断开连接'), value: true, isDestructive: true),
      ],
    );
    if (confirmed == true && mounted) {
      await _cancel();
      if (mounted) await _card.disconnect();
    }
  }

  String _message(Object error) {
    if (error is AppFailure) {
      if (View.of(context).platformDispatcher.locale.languageCode == 'zh') {
        return error.safeMessage;
      }
      return switch (error.code) {
        'ECARD_BIND_STOP_FAILED' => 'The temporary VPN is still active. Stop it and try again.',
        'ECARD_BIND_DNS_UNAVAILABLE' ||
        'ECARD_BIND_DNS_NOT_RESTORED' =>
          'Your normal connection has not returned yet. Try again shortly.',
        _ => switch (error.kind) {
            FailureKind.invalidInput => isDesktop()
                ? 'Check your OPENID and channel, then try again.'
                : 'Check your binding code and try again.',
            FailureKind.permissionDenied =>
              'Permission was denied. Review the request and try again.',
            FailureKind.network || FailureKind.timeout => 'Check your network and try again.',
            _ => 'Could not complete setup. Please try again.',
          },
      };
    }
    if (error is FormatException && isDesktop()) {
      return _text('Enter a valid OPENID.', '请输入有效的 OPENID。');
    }
    return _text('Could not complete setup. Please try again.', '未能完成设置，请重试。');
  }

  Widget _button(
    String label,
    VoidCallback? action, {
    Key? key,
    bool primary = true,
  }) {
    return AdaptiveEcardWizardButton(
      label: label,
      onPressed: !_busy && !_card.busy ? action : null,
      buttonKey: key,
      primary: primary,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _changes,
        builder: (context, _) {
          final inSetup = _reviewing || _pending != null || _binding.hijackNeedsStop;
          return PopScope(
            canPop: !_busy && !inSetup,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && !_busy && inSetup) unawaited(_run(_cancel));
            },
            child: _content(),
          );
        },
      );

  Widget _content() {
    final chinese = View.of(context).platformDispatcher.locale.languageCode == 'zh';
    ({String title, String description}) heading(WizardStep step) =>
        AdaptiveEcardWizard.heading(step, chinese: chinese);
    Widget? field;
    IconData? stateIcon;
    late String title;
    String? description;
    final controls = <Widget>[];
    final cancel = _text('Cancel setup', '取消设置');
    final cancelButton = _button(cancel, () => _run(_cancel), primary: false);
    var showCard = false;
    if (!_ready) {
      title = _text('Could not load your card', '无法读取校园卡');
      if (_error != null) controls.add(_button(_text('Retry', '重试'), () => _run(_load)));
    } else if (_card.configured && _justConnected) {
      showCard = true;
      title = heading(WizardStep.success).title;
      description = heading(WizardStep.success).description;
      stateIcon = TpIcons.check;
      controls.add(_button(_text('Done', '完成'), () => setState(() => _justConnected = false)));
    } else if (_card.configured) {
      showCard = true;
      title = heading(WizardStep.account).title;
      final details = heading(WizardStep.account).description;
      if (details.isNotEmpty) description = details;
      controls.add(
        _button(
          _text('Disconnect eCard', '断开校园卡连接'),
          () => _run(_disconnect),
          primary: false,
        ),
      );
      if (_binding.hijackNeedsStop) controls.add(cancelButton);
    } else if (_pending != null) {
      stateIcon = TpIcons.activity;
      title = heading(WizardStep.retry).title;
      description = _text(
        'Your code was accepted. You can retry without entering it again.',
        '绑定码已验证。你可以直接重试，无需重新输入。',
      );
      if (_busy) {
        description = _text('Connecting your card…', '正在连接校园卡…');
      } else {
        controls.addAll([
          _button(_text('Retry connection', '重试连接'), () => _run(_finishConnection)),
          cancelButton,
        ]);
      }
    } else if (_binding.status == EcardBindHijackStatus.unknown) {
      title = _text('Restore your connection', '恢复网络连接');
      description = _text('Stop the temporary VPN before continuing.', '请先停止临时 VPN 连接。');
      controls.add(_button(_text('Stop temporary VPN', '停止临时 VPN'), () => _run(_cancel)));
    } else if (isDesktop()) {
      showCard = true;
      title = heading(WizardStep.welcome).title;
      description = _text(
        'Enter your WeChat or Alipay eCard OPENID.',
        '输入微信或支付宝校园卡的 OPENID。',
      );
      final enabled = !_busy && !_card.busy;
      field = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<EcardOpenIdChannel>(
            initialValue: _channel,
            decoration: InputDecoration(labelText: _text('OPENID channel', 'OPENID 渠道')),
            items: [
              for (final channel in EcardOpenIdChannel.values)
                DropdownMenuItem(value: channel, child: Text(channel.label)),
            ],
            onChanged: enabled
                ? (channel) {
                    if (channel == null) return;
                    setState(() {
                      _channel = channel;
                      _error = null;
                    });
                  }
                : null,
          ),
          const SizedBox(height: TpTokens.space3),
          AdaptiveTextFieldGroup(
            key: const Key('openid-field'),
            items: [
              AdaptiveTextFieldGroupItem(
                controller: _openId,
                placeholder: 'OPENID',
                obscureText: true,
                enabled: enabled,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: enabled ? (_) => unawaited(_run(_connectManually)) : null,
              ),
            ],
          ),
        ],
      );
      controls.addAll([
        _button(
          _text('Connect eCard', '连接校园卡'),
          () => _run(_connectManually),
          key: const Key('openid-save-button'),
        ),
        _button(_text('Open Cloud sync', '打开云同步'), _openCloudSync, primary: false),
      ]);
    } else if (_binding.status == EcardBindHijackStatus.unsupported) {
      showCard = true;
      title = _text('Use your card on this device', '在此设备上使用校园卡');
      description = _text(
        'Back up your card on your phone with Cloud sync, then restore your linked accounts here using the same GeekPie account.',
        '先在手机上通过云同步备份校园卡，再使用同一 GeekPie 账号在此恢复已绑定的账号。',
      );
      controls.add(_button(_text('Open Cloud sync', '打开云同步'), _openCloudSync));
    } else if (_binding.hijackActive) {
      stateIcon = TpIcons.code;
      title = heading(WizardStep.code).title;
      description =
          _text('Enter the code shown in the campus card mini program.', '请输入一卡通小程序中显示的绑定码。');
      field = AdaptiveTextFieldGroup(
        key: const Key('ecard-bind-code-field'),
        items: [
          AdaptiveTextFieldGroupItem(
            controller: _code,
            placeholder: _text('Binding code', '绑定码'),
            enabled: !_busy && !_card.busy,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: !_busy && !_card.busy ? (_) => unawaited(_run(_redeem)) : null,
          ),
        ],
      );
      controls.addAll([
        _button(
          _text('Connect eCard', '连接校园卡'),
          () => _run(_redeem),
          key: const Key('ecard-bind-redeem-button'),
        ),
        cancelButton,
      ]);
    } else if (_reviewing) {
      stateIcon = TpIcons.lock;
      title = heading(WizardStep.permission).title;
      description = _text(
        'While setup is active, this device’s DNS lookups go through the binding service. Your current VPN may pause. The temporary connection stops when you finish or cancel.',
        '设置期间，此设备的 DNS 查询会经过绑定服务，正在使用的 VPN 可能会暂停。完成或取消设置后，临时连接会关闭。',
      );
      controls.addAll([
        _button(
          _text('Review permission', '查看系统授权'),
          () => _run(_requestPermission),
          key: const Key('ecard-bind-hijack-button'),
        ),
        cancelButton,
      ]);
    } else {
      showCard = true;
      title = heading(WizardStep.welcome).title;
      description = heading(WizardStep.welcome).description;
      controls.add(
        _button(_text('Connect my card', '连接我的校园卡'), () => setState(() => _reviewing = true)),
      );
    }

    final details = _card.configured && !_justConnected
        ? TpCard(
            child: Column(
              children: [
                ListTile(
                  title: Text(_text('Account', '账号')),
                  trailing: Text(_card.maskedOpenId ?? '—'),
                ),
                ListTile(
                  title: Text(_text('Status', '状态')),
                  trailing: Text(_text('Connected', '已连接')),
                ),
              ],
            ),
          )
        : null;
    return AdaptiveEcardWizard(
      title: title,
      description: description,
      stateIcon: stateIcon,
      field: field,
      error: _error == null ? null : _message(_error!),
      details: details,
      showCard: showCard,
      cardFirst: showCard && !_card.configured,
      controls: controls,
      loading: !_ready && _error == null,
      backLabel: _text('Back', '返回'),
      cardLabel: _text('Campus card', '校园卡'),
      backEnabled: !_busy && !_card.busy,
      onBack: () => unawaited(maybePopAdaptivePage<void>(context)),
    );
  }
}
