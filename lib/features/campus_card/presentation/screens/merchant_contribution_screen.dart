import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/merchant_contribution_models.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../widgets/apple_wallet_components.dart';

final merchantPhotoPickerProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => () async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (file == null) return null;
    if (await file.length() > 10 * 1024 * 1024) {
      throw const FormatException('Photo is too large');
    }
    return file.readAsBytes();
  },
);

final merchantIssueLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

final class MerchantContributionScreen extends ConsumerStatefulWidget {
  const MerchantContributionScreen({
    super.key,
    required this.merchantId,
    this.posCode,
    this.correction = false,
  });

  final String merchantId;
  final String? posCode;
  final bool correction;

  @override
  ConsumerState<MerchantContributionScreen> createState() =>
      _MerchantContributionScreenState();
}

final class _MerchantContributionScreenState
    extends ConsumerState<MerchantContributionScreen> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _cafeteria = TextEditingController();
  final _floor = TextEditingController();
  final _stall = TextEditingController();
  Uint8List? _photo;
  bool _preview = false;
  bool _busy = false;
  String? _error;

  MerchantContribution get _draft => MerchantContribution(
        merchantId: widget.merchantId,
        posCode: widget.posCode,
        cafeteria: _cafeteria.text,
        floor: _floor.text,
        stall: _stall.text,
        correction: widget.correction,
      );

  @override
  void dispose() {
    _cafeteria.dispose();
    _floor.dispose();
    _stall.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await ref.read(merchantPhotoPickerProvider)();
      if (mounted && photo != null) setState(() => _photo = photo);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取照片，请选择不超过 10 MB 的图片。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openIssue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opened =
          await ref.read(merchantIssueLauncherProvider)(_draft.issueUri);
      if (!opened && mounted) setState(() => _error = '无法打开 GitHub，请稍后重试。');
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开 GitHub，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_preview,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _preview) setState(() => _preview = false);
        },
        child: Scaffold(
          body: AppleWalletPage(
            child: ApplePinnedHeaderLayout(
              leading: CampusCardHeaderAction(
                id: 'back',
                sfSymbol: 'chevron.left',
                icon: GpPlatformIcons.back(context),
                label: '返回',
                onPressed: () => _preview
                    ? setState(() => _preview = false)
                    : popCampusCard(context),
              ),
              title: _preview
                  ? '确认商户资料'
                  : widget.correction
                      ? '纠正商户资料'
                      : '补充商户资料',
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  20,
                  ApplePinnedHeaderLayout.contentTop(context),
                  20,
                  40,
                ),
                children: [
                  AppleSection(
                    children: [
                      AppleListRow(
                        label: '商户号',
                        value: widget.merchantId,
                        valueMaxLines: null,
                      ),
                      if (widget.posCode != null)
                        AppleListRow(
                          label: 'POS 代码',
                          value: widget.posCode,
                          valueMaxLines: null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_preview) ...[
                    AppleSection(
                      children: [
                        AppleListRow(
                          label: '食堂或区域',
                          value: _draft.cafeteria.trim(),
                          valueMaxLines: null,
                        ),
                        if (_draft.floor.trim().isNotEmpty)
                          AppleListRow(
                            label: '楼层',
                            value: _draft.floor.trim(),
                            valueMaxLines: null,
                          ),
                        if (_draft.stall.trim().isNotEmpty)
                          AppleListRow(
                            label: '店铺名称',
                            value: _draft.stall.trim(),
                            valueMaxLines: null,
                          ),
                      ],
                    ),
                  ] else
                    Form(
                      key: _form,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _cafeteria,
                            maxLength: 80,
                            decoration:
                                const InputDecoration(labelText: '食堂或区域'),
                            validator: (value) =>
                                value?.trim().isNotEmpty == true
                                    ? null
                                    : '请填写食堂或区域。',
                          ),
                          TextFormField(
                            controller: _floor,
                            maxLength: 40,
                            decoration:
                                const InputDecoration(labelText: '楼层（可选）'),
                          ),
                          if (widget.posCode != null)
                            TextFormField(
                              controller: _stall,
                              maxLength: 80,
                              decoration:
                                  const InputDecoration(labelText: '店铺名称（可选）'),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_photo != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _photo!,
                        height: 220,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 220,
                          child: Center(child: Text('无法预览图片')),
                        ),
                      ),
                    ),
                    if (!_preview)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: '移除照片',
                          icon: Icon(GpPlatformIcons.delete(context)),
                          onPressed: () => setState(() => _photo = null),
                        ),
                      ),
                  ],
                  if (!_preview)
                    TextButton.icon(
                      onPressed: _busy ? null : _choosePhoto,
                      icon: Icon(GpPlatformIcons.photoLibrary(context)),
                      label: const Text('选择招牌照片（可选）'),
                    ),
                  const SizedBox(height: 12),
                  const Text('资料将在 GitHub 公开，需要 GitHub 账户。提交后由维护者核实。'),
                  const SizedBox(height: 8),
                  const Text('照片仅在本机预览。可在 GitHub 附加照片，请确认没有人脸、付款码或账户信息。'),
                  const SizedBox(height: 8),
                  const Text('本次仅提供以上商户资料，不包含金额、账户或完整交易记录。'),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : _preview
                            ? _openIssue
                            : () {
                                if (_form.currentState!.validate()) {
                                  setState(() {
                                    _preview = true;
                                    _error = null;
                                  });
                                  _scroll.jumpTo(0);
                                }
                              },
                    child: Text(_preview ? '确认并前往 GitHub' : '预览资料'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
