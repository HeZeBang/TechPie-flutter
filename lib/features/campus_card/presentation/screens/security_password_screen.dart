import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/ports/platform_ports.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';

final class SecurityPasswordScreen extends ConsumerStatefulWidget {
  const SecurityPasswordScreen({super.key});

  @override
  ConsumerState<SecurityPasswordScreen> createState() =>
      _SecurityPasswordScreenState();
}

class _SecurityPasswordScreenState
    extends ConsumerState<SecurityPasswordScreen> {
  final _old = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _old.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final initialization =
        ref.read(spendingPasswordInitializationProvider).valueOrNull;
    if (initialization == null) return;
    final valid = [
      _old,
      _next,
      _confirm,
    ].every((controller) => RegExp(r'^\d{6}$').hasMatch(controller.text));
    if (!valid || _next.text != _confirm.text) {
      await _showMessage('输入 6 位消费密码');
      if (!mounted) return;
      await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.error);
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(spendingLimitsControllerProvider.notifier).changePassword(
            accountKey: initialization.accountKey,
            oldPassword: _old.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.success);
      if (!mounted) return;
      await _showMessage('消费密码修改成功');
      if (mounted) popCampusCard(context);
    } catch (error) {
      if (mounted) await _showMessage(GpStateView.safeUiError(error));
    } finally {
      if (mounted) {
        _old.clear();
        _next.clear();
        _confirm.clear();
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showMessage(String message) => showAdaptiveDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => AlertDialog.adaptive(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final initialization = ref.watch(spendingPasswordInitializationProvider);
    return Scaffold(
      body: AppleWalletPage(
        child: ApplePinnedHeaderLayout(
          leading: CampusCardHeaderAction(
            id: 'back',
            sfSymbol: 'chevron.left',
            icon: GpPlatformIcons.back(context),
            label: '返回',
            onPressed: () => popCampusCard(context),
          ),
          title: '修改消费密码',
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              ApplePinnedHeaderLayout.contentTop,
              20,
              52,
            ),
            children: [
              switch (initialization) {
                AsyncData(:final value) when value.haveCard => Column(
                    children: [
                      AppleSection(
                        children: [
                          _PasswordRow(
                            label: '原密码',
                            controller: _old,
                          ),
                          _PasswordRow(
                            label: '新密码',
                            controller: _next,
                          ),
                          _PasswordRow(
                            label: '再次输入新密码',
                            controller: _confirm,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.gpColors.action,
                          minimumSize: const Size.fromHeight(54),
                          shape: const StadiumBorder(),
                        ),
                        child: _loading
                            ? const CupertinoActivityIndicator(
                                color: Colors.white,
                              )
                            : const Text('保存'),
                      ),
                    ],
                  ),
                AsyncData() => const GpStateView(
                    title: '当前卡片状态无法付款',
                  ),
                AsyncError(:final error) => GpStateView.error(
                    error,
                    onRetry: () =>
                        ref.invalidate(spendingPasswordInitializationProvider),
                  ),
                _ => const Padding(
                    padding: EdgeInsets.all(42),
                    child: CupertinoActivityIndicator(radius: 13),
                  ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

final class _PasswordRow extends StatelessWidget {
  const _PasswordRow({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: TextField(
        controller: controller,
        obscureText: true,
        maxLength: 6,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          border: InputBorder.none,
        ),
      ),
    );
  }
}
