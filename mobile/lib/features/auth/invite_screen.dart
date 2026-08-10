import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../core/breakpoints.dart';
import '../referral/invite_friends.dart';

class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  String get _clean =>
      _code.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _submit() async {
    final l = L10n.of(context);
    if (_clean.length < 6) {
      setState(() => _error = l.inviteInvalid);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pair = await ref.read(authRepositoryProvider).redeemInvite(
          _clean,
          displayName: _name.text.trim(),
          referredBy: ref.read(pendingReferrerProvider));
      await ref.read(authControllerProvider.notifier).completeLogin(pair);
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      setState(() => _error = switch (code) {
            401 => l.inviteRejected,
            429 => l.authTooMany,
            404 => l.inviteDisabled,
            _ => l.authNetworkError,
          });
    } catch (_) {
      setState(() => _error = l.authNetworkError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(l.inviteTitle),
      ),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.confirmation_number_outlined,
                  size: 36, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(l.inviteCodeLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(20),
                TextInputFormatter.withFunction((_, next) => TextEditingValue(
                      text: next.text.toUpperCase(),
                      selection: next.selection,
                      composing: TextRange.empty,
                    )),
              ],
              style: const TextStyle(fontSize: 20, letterSpacing: 3),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'K7M4-X9QP',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _loading ? null : _submit(),
            ),
            const SizedBox(height: 18),
            Text(l.inviteNameLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              decoration: InputDecoration(
                hintText: l.inviteNameHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(l.inviteHint,
                style: TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.inviteSubmit),
            ),
          ],
        ),
      ),
    );
  }
}
