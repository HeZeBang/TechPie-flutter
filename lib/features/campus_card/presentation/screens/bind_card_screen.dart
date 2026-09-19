import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/models/card_models.dart';
import '../../domain/ports/platform_ports.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';

final class BindCardScreen extends ConsumerStatefulWidget {
  const BindCardScreen({super.key});

  @override
  ConsumerState<BindCardScreen> createState() => _BindCardScreenState();
}

class _BindCardScreenState extends ConsumerState<BindCardScreen> {
  final _card = TextEditingController();
  final _password = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();
  IdentityDocumentType _type = IdentityDocumentType.nationalId;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _card.dispose();
    _password.dispose();
    _document.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_card.text.trim().isEmpty ||
        _document.text.trim().isEmpty ||
        !RegExp(r'^\d{6}$').hasMatch(_password.text) ||
        !RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text)) {
      setState(() => _error = '请填写完整信息');
      await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.error);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(cardControllerProvider.notifier).bind(
            BindCardCommand(
              cardNumber: _card.text.trim(),
              queryPassword: _password.text,
              identityNumber: _document.text.trim(),
              identityType: _type,
              phoneNumber: _phone.text,
            ),
          );
      if (!mounted) return;
      _password.clear();
      await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.success);
      if (mounted) await goToCampusCardPay(context, ref);
    } catch (error) {
      if (mounted) setState(() => _error = GpStateView.safeUiError(error));
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          title: '绑定卡片',
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              ApplePinnedHeaderLayout.contentTop,
              20,
              52,
            ),
            children: [
              Center(
                child: SizedBox(
                  width: 218,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      GeekPayAssets.cardFull,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              AppleSection(
                children: [
                  _Field(
                    label: '卡号',
                    controller: _card,
                    keyboardType: TextInputType.number,
                    maxLength: 19,
                  ),
                  _Field(
                    label: '查询密码（6 位数字）',
                    controller: _password,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    child: DropdownButtonFormField<IdentityDocumentType>(
                      // Flutter 3.27 uses value; newer SDKs call it initialValue.
                      // ignore: deprecated_member_use
                      value: _type,
                      decoration: const InputDecoration(
                        labelText: '证件类型',
                        border: InputBorder.none,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: IdentityDocumentType.nationalId,
                          child: Text('居民身份证'),
                        ),
                        DropdownMenuItem(
                          value: IdentityDocumentType.militaryId,
                          child: Text('军人证件'),
                        ),
                        DropdownMenuItem(
                          value: IdentityDocumentType.passport,
                          child: Text('护照'),
                        ),
                        DropdownMenuItem(
                          value: IdentityDocumentType.workId,
                          child: Text('工作证'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _type = value ?? _type),
                    ),
                  ),
                  _Field(
                    label: '证件号',
                    controller: _document,
                    maxLength: 20,
                  ),
                  _Field(
                    label: '手机号',
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.gpColors.danger),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('bind-submit'),
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: context.gpColors.action,
                  minimumSize: const Size.fromHeight(54),
                  shape: const StadiumBorder(),
                ),
                child: _loading
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text('确认绑定'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final int? maxLength;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        obscureText: obscureText,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          border: InputBorder.none,
        ),
      ),
    );
  }
}
