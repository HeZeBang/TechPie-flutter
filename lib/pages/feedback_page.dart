import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/feedback_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, required this.service});
  final FeedbackService service;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _message = TextEditingController();
  final _contact = TextEditingController();
  final _images = <FeedbackImage>[];
  bool _picking = false;
  bool _includeUsername = false;
  bool _includeEmail = false;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _picking || _sent) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.submit(
        _message.text,
        includeUsername: _includeUsername,
        includeEmail: _includeEmail,
        contact: _contact.text,
        images: _images,
        onImageChanged: _refreshImages,
      );
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is TimeoutException
              ? '未能确认送达，内容已保留，请稍后再试'
              : error is Exception && error.toString().startsWith('Exception: ')
                  ? error.toString().substring(11)
                  : '反馈未发送成功，内容已保留';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImages() async {
    if (_picking || _busy || _images.length >= 9) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (files.length > 9 - _images.length) throw Exception('最多添加 9 张图片');
      final selected = <FeedbackImage>[];
      for (final file in files) {
        if (await file.length() > FeedbackService.imageLimit) {
          throw Exception('每张图片请勿超过 4 MB');
        }
        final bytes = await file.readAsBytes();
        try {
          final decoded = await decodeImageFromList(bytes);
          decoded.dispose();
        } catch (_) {
          throw Exception('图片无法读取，请换一张图片');
        }
        selected.add(FeedbackImage(bytes));
      }
      if (mounted) setState(() => _images.addAll(selected));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is Exception && error.toString().startsWith('Exception: ')
                  ? error.toString().substring(11)
                  : '未能添加图片，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _refreshImages() {
    if (mounted) setState(() {});
  }

  Future<void> _retryImage(FeedbackImage image) async {
    if (_busy || _picking) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.uploadImage(image, onChanged: _refreshImages);
    } catch (_) {
      if (mounted) setState(() => _error = '图片上传失败，可重试或移除');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space4,
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '问题反馈 / 功能建议',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '我的',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回我的',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
        ),
        material: () => const BlurredAppBar(title: Text('问题反馈 / 功能建议')),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          TpTokens.pageHorizontalPadding,
          topInset,
          TpTokens.pageHorizontalPadding,
          AppShellMetrics.bottomContentPaddingOf(context) + TpTokens.space4,
        ),
        children: [
          TpPageBody(
            child: _sent
                ? TpCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TpTokens.space5,
                      vertical: TpTokens.space6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          TpIcons.checkCircle,
                          size: 56,
                          color: colors.successGreen,
                        ),
                        const SizedBox(height: TpTokens.space4),
                        Text(
                          '反馈已发送',
                          style: TpTypography.cardTitle(colors)
                              .copyWith(fontSize: 17),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: TpTokens.space2),
                        Text(
                          '感谢你的反馈，我们会尽快查看并跟进。',
                          style: TpTypography.itemMeta(colors),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: TpTokens.space5),
                        AdaptiveButton(
                          label: '返回',
                          icon: TpIcons.chevronLeft,
                          sfSymbol: 'chevron.left',
                          role: AdaptiveButtonRole.standard,
                          width: 160,
                          height: 44,
                          onPressed: () =>
                              unawaited(maybePopAdaptivePage<void>(context)),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TpCard(
                        leadingIcon: TpIcons.feedback,
                        title: '反馈内容',
                        padding: const EdgeInsets.fromLTRB(
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space1,
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _message,
                              enabled: !_busy,
                              minLines: 6,
                              maxLines: 12,
                              maxLength: 2000,
                              decoration: const InputDecoration(
                                hintText: '描述问题或建议',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: TpTokens.space3),
                            if (_images.isNotEmpty) ...[
                              Wrap(
                                spacing: TpTokens.space2,
                                runSpacing: TpTokens.space2,
                                children: [
                                  for (var i = 0; i < _images.length; i++)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        TpTokens.radiusS,
                                      ),
                                      child: Stack(
                                        children: [
                                          Image.memory(
                                            _images[i].bytes,
                                            width: 88,
                                            height: 88,
                                            fit: BoxFit.cover,
                                          ),
                                          if (_images[i].uploading)
                                            const Positioned.fill(
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            ),
                                          if (_images[i].failed)
                                            Positioned(
                                              bottom: 0,
                                              left: 0,
                                              right: 0,
                                              child: Material(
                                                color: colors.dangerRed
                                                    .withValues(alpha: 0.90),
                                                child: InkWell(
                                                  onTap: _busy
                                                      ? null
                                                      : () => unawaited(
                                                            _retryImage(
                                                              _images[i],
                                                            ),
                                                          ),
                                                  child: const Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                      vertical: 4,
                                                    ),
                                                    child: Text(
                                                      '重试',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                          else if (_images[i].uploaded)
                                            Positioned(
                                              bottom: 4,
                                              left: 4,
                                              child: Icon(
                                                TpIcons.checkCircle,
                                                color: colors.successGreen,
                                              ),
                                            ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: Material(
                                              color: Colors.black
                                                  .withValues(alpha: 0.58),
                                              shape: const CircleBorder(),
                                              clipBehavior: Clip.antiAlias,
                                              child: IconButton(
                                                tooltip: '移除第 ${i + 1} 张图片',
                                                constraints:
                                                    const BoxConstraints.tightFor(
                                                  width: 24,
                                                  height: 24,
                                                ),
                                                padding: EdgeInsets.zero,
                                                icon: const Icon(
                                                  TpIcons.close,
                                                  size: TpTokens.iconXs,
                                                  color: Colors.white,
                                                ),
                                                onPressed: _busy || _picking
                                                    ? null
                                                    : () => setState(
                                                          () => _images
                                                              .removeAt(i),
                                                        ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: TpTokens.space3),
                            ],
                            AdaptiveButton(
                              label: '添加图片（${_images.length}/9）',
                              icon: Icons.add_photo_alternate_outlined,
                              sfSymbol: 'photo.badge.plus',
                              loading: _picking,
                              height: 44,
                              onPressed:
                                  _busy || _picking || _images.length >= 9
                                      ? null
                                      : () => unawaited(_pickImages()),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: TpTokens.sectionGap),
                      TpCard(
                        title: '附带信息',
                        padding: const EdgeInsets.fromLTRB(
                          TpTokens.cardPaddingHorizontal,
                          0,
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CheckboxListTile(
                              title: const Text('发送用户名'),
                              value: _includeUsername,
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      setState(() => _includeUsername = value!),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                            CheckboxListTile(
                              title: const Text('发送邮箱'),
                              value: _includeEmail,
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      setState(() => _includeEmail = value!),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: TpTokens.space2),
                            TextField(
                              controller: _contact,
                              enabled: !_busy,
                              maxLength: 200,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: '补充联系方式（选填）',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            Text(
                              '自动附带 App 版本和平台。',
                              style: TpTypography.itemMeta(colors),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        TpCard(
                          color: colors.opaqueDangerContainer,
                          borderColor: colors.dangerRed.withValues(alpha: 0.30),
                          padding: const EdgeInsets.all(TpTokens.space3),
                          child: Text(
                            _error!,
                            style: TpTypography.itemMeta(colors).copyWith(
                              color: colors.dangerRed,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: TpTokens.space4),
                      AdaptiveButton(
                        label: '提交反馈',
                        icon: Icons.send_outlined,
                        sfSymbol: 'paperplane',
                        role: AdaptiveButtonRole.prominent,
                        loading: _busy,
                        height: 46,
                        onPressed:
                            _busy || _picking ? null : () => unawaited(_submit()),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
