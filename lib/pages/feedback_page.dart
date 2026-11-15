import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/feedback_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
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
        if (await file.length() > FeedbackService.imageLimit) throw Exception('每张图片请勿超过 4 MB');
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
          () => _error = error is Exception && error.toString().startsWith('Exception: ')
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
    final useIosChrome = isIos();
    final topInset = useIosChrome || usesLegacyIosChrome()
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;
    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !usesLegacyIosChrome(),
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: '问题反馈 / 功能建议',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Settings',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回 Settings',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
            )
          : const BlurredAppBar(title: Text('问题反馈 / 功能建议')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          topInset + 20,
          20,
          AppShellMetrics.bottomContentPaddingOf(context) + 20,
        ),
        children: _sent
            ? const [
                SizedBox(height: 40),
                Icon(Icons.check_circle_outline, size: 64),
                SizedBox(height: 20),
                Text('反馈已发送', textAlign: TextAlign.center),
              ]
            : [
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
                const SizedBox(height: 12),
                if (_images.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _images.length; i++)
                        Stack(
                          children: [
                            Image.memory(
                              _images[i].bytes,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                            ),
                            if (_images[i].uploading)
                              const Positioned.fill(
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            if (_images[i].failed)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: FilledButton(
                                  onPressed:
                                      _busy ? null : () => unawaited(_retryImage(_images[i])),
                                  child: const Text('重试'),
                                ),
                              )
                            else if (_images[i].uploaded)
                              const Positioned(
                                bottom: 0,
                                left: 0,
                                child: Icon(Icons.check_circle, color: Colors.green),
                              ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton.filledTonal(
                                tooltip: '移除第 ${i + 1} 张图片',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _busy || _picking
                                    ? null
                                    : () => setState(() => _images.removeAt(i)),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                AdaptiveButton(
                  label: '添加图片（${_images.length}/9）',
                  icon: Icons.add_photo_alternate_outlined,
                  sfSymbol: 'photo.badge.plus',
                  loading: _picking,
                  onPressed: _busy || _picking || _images.length >= 9
                      ? null
                      : () => unawaited(_pickImages()),
                ),
                CheckboxListTile(
                  title: const Text('发送用户名'),
                  value: _includeUsername,
                  onChanged: _busy ? null : (value) => setState(() => _includeUsername = value!),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  title: const Text('发送邮箱'),
                  value: _includeEmail,
                  onChanged: _busy ? null : (value) => setState(() => _includeEmail = value!),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  controller: _contact,
                  enabled: !_busy,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: '补充联系方式（选填）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('自动附带 App 版本和平台。'),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                AdaptiveButton(
                  label: '提交反馈',
                  icon: Icons.send_outlined,
                  sfSymbol: 'paperplane',
                  role: AdaptiveButtonRole.prominent,
                  loading: _busy,
                  onPressed: _busy || _picking ? null : () => unawaited(_submit()),
                ),
              ],
      ),
    );
  }
}
