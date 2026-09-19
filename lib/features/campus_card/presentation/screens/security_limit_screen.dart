import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/models/security_models.dart';
import '../../domain/money_fen.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';

final class SecurityLimitScreen extends ConsumerStatefulWidget {
  const SecurityLimitScreen({super.key});

  @override
  ConsumerState<SecurityLimitScreen> createState() =>
      _SecurityLimitScreenState();
}

class _SecurityLimitScreenState extends ConsumerState<SecurityLimitScreen> {
  Future<void> _editCard(SpendingLimits current) async {
    final edit = await _showEditor(
      title: '卡消费限额',
      perTransaction: current.cardPerTransaction,
      perDay: current.cardPerDay,
      needsPassword: false,
    );
    if (edit == null || !mounted) return;
    try {
      await ref.read(spendingLimitsControllerProvider.notifier).saveCardLimits(
            current.copyWith(
              cardPerTransaction: edit.perTransaction,
              cardPerDay: edit.perDay,
            ),
          );
      if (mounted) await _showMessage('消费限额修改成功');
    } catch (error) {
      if (mounted) await _showMessage(GpStateView.safeUiError(error));
    }
  }

  Future<void> _editQr(SpendingLimits current) async {
    final edit = await _showEditor(
      title: '二维码消费限额',
      perTransaction: current.qrPerTransaction,
      perDay: current.qrPerDay,
      needsPassword: true,
    );
    if (edit == null || !mounted) return;
    try {
      await ref.read(spendingLimitsControllerProvider.notifier).saveQrLimits(
            current.copyWith(
              qrPerTransaction: edit.perTransaction,
              qrPerDay: edit.perDay,
            ),
            transactionPassword: edit.password!,
          );
      if (mounted) await _showMessage('消费限额修改成功');
    } catch (error) {
      if (mounted) await _showMessage(GpStateView.safeUiError(error));
    }
  }

  Future<_LimitEdit?> _showEditor({
    required String title,
    required MoneyFen perTransaction,
    required MoneyFen perDay,
    required bool needsPassword,
  }) =>
      showModalBottomSheet<_LimitEdit>(
        context: context,
        useRootNavigator: false,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => _LimitEditorSheet(
          title: title,
          perTransaction: perTransaction,
          perDay: perDay,
          needsPassword: needsPassword,
        ),
      );

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
    final limits = ref.watch(spendingLimitsControllerProvider);
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
          title: '消费限额',
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              ApplePinnedHeaderLayout.contentTop,
              20,
              52,
            ),
            children: [
              switch (limits) {
                AsyncData(:final value) => Column(
                    children: [
                      AppleSection(
                        header: '卡消费限额',
                        children: [
                          AppleListRow(
                            label: '单笔限额',
                            value:
                                formatMoneyFen(value.cardPerTransaction.value),
                          ),
                          AppleListRow(
                            label: '单日限额',
                            value: formatMoneyFen(value.cardPerDay.value),
                          ),
                          AppleListRow(
                            label: '修改',
                            onTap: value.haveCard
                                ? () => unawaited(_editCard(value))
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AppleSection(
                        header: '二维码消费限额',
                        children: [
                          AppleListRow(
                            label: '单笔限额',
                            value: formatMoneyFen(value.qrPerTransaction.value),
                          ),
                          AppleListRow(
                            label: '单日限额',
                            value: formatMoneyFen(value.qrPerDay.value),
                          ),
                          AppleListRow(
                            label: '修改',
                            onTap: value.haveQrCode
                                ? () => unawaited(_editQr(value))
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                AsyncError(:final error) => GpStateView.error(
                    error,
                    onRetry: () =>
                        ref.invalidate(spendingLimitsControllerProvider),
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

final class _AmountField extends StatelessWidget {
  const _AmountField({required this.label, required this.controller});

  static final _validAmount = RegExp(r'^\d{0,5}(?:\.\d{0,2})?$');

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        LengthLimitingTextInputFormatter(8),
        TextInputFormatter.withFunction((oldValue, newValue) {
          return _validAmount.hasMatch(newValue.text) ? newValue : oldValue;
        }),
      ],
      decoration: InputDecoration(labelText: label, prefixText: '¥ '),
    );
  }
}

final class _LimitEditorSheet extends StatefulWidget {
  const _LimitEditorSheet({
    required this.title,
    required this.perTransaction,
    required this.perDay,
    required this.needsPassword,
  });

  final String title;
  final MoneyFen perTransaction;
  final MoneyFen perDay;
  final bool needsPassword;

  @override
  State<_LimitEditorSheet> createState() => _LimitEditorSheetState();
}

final class _LimitEditorSheetState extends State<_LimitEditorSheet> {
  static const _maximumLimitFen = 1000000;

  late final TextEditingController _single;
  late final TextEditingController _daily;
  late final TextEditingController _password;
  String? _error;

  @override
  void initState() {
    super.initState();
    _single = TextEditingController(
      text: formatMoneyFen(widget.perTransaction.value, symbol: false),
    );
    _daily = TextEditingController(
      text: formatMoneyFen(widget.perDay.value, symbol: false),
    );
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _single.dispose();
    _daily.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final perTransaction = MoneyFen.fromApiYuan(
        _single.text,
        field: 'perTransaction',
      );
      final perDay = MoneyFen.fromApiYuan(_daily.text, field: 'perDay');
      if (perTransaction.value <= 0 ||
          perDay.value < perTransaction.value ||
          perTransaction.value > _maximumLimitFen ||
          perDay.value > _maximumLimitFen ||
          (widget.needsPassword &&
              !RegExp(r'^\d{6}$').hasMatch(_password.text))) {
        throw const FormatException();
      }
      Navigator.pop(
        context,
        _LimitEdit(
          perTransaction: perTransaction,
          perDay: perDay,
          password: widget.needsPassword ? _password.text : null,
        ),
      );
    } catch (_) {
      setState(() => _error = '请输入有效金额，单日限额不能低于单笔限额；二维码限额还需要 6 位消费密码。');
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            _AmountField(
              label: '单笔限额',
              controller: _single,
            ),
            const SizedBox(height: 12),
            _AmountField(label: '单日限额', controller: _daily),
            if (widget.needsPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '消费密码',
                  counterText: '',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: context.gpColors.danger),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: context.gpColors.action,
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      );
}

final class _LimitEdit {
  const _LimitEdit({
    required this.perTransaction,
    required this.perDay,
    this.password,
  });

  final MoneyFen perTransaction;
  final MoneyFen perDay;
  final String? password;
}
