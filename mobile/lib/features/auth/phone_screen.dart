import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import 'invite_screen.dart';
import 'otp_screen.dart';
import 'telegram_screen.dart';
import '../../core/breakpoints.dart';

/// Phone-number entry. [role] is 'student' (default) or 'parent' — it sets the
/// signup intent the backend stores against the OTP.
class PhoneScreen extends ConsumerStatefulWidget {
  final String role;
  const PhoneScreen({super.key, this.role = 'student'});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _digits => _controller.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _send() async {
    final l = L10n.of(context);
    if (_digits.length != 9) {
      setState(() => _error = l.authInvalidPhone);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final phone = '+998$_digits';
    try {
      final res = await ref
          .read(authRepositoryProvider)
          .requestOtp(phone, role: widget.role);
      if (!mounted) return;
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: phone,
            role: widget.role,
            debugCode: res.debugCode,
            expiresInSeconds: res.expiresInSeconds,
          ),
        ),
      );
      if (ok == true && mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      setState(() => _error = e.response?.statusCode == 429
          ? l.authTooMany
          : l.authNetworkError);
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
    final isParent = widget.role == 'parent';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(isParent ? l.authParentTitle : l.authLoginTitle),
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
              child: Icon(isParent ? Icons.family_restroom : Icons.person,
                  size: 36, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(l.authPhoneLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: InputDecoration(
                prefixText: '+998 ',
                hintText: l.authPhoneHint,
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _loading ? null : _send(),
            ),
            const SizedBox(height: 8),
            Text(l.authLoginBenefit,
                style: TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _loading ? null : _send,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.authSendCode),
            ),
  
            // akkauntini yaratadi.
            if (!isParent) ...[
              const SizedBox(height: 26),
              Row(children: [
                Expanded(child: Divider(color: p.muted.withValues(alpha: 0.4))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(l.authOr,
                      style: TextStyle(fontSize: 13, color: p.muted)),
                ),
                Expanded(child: Divider(color: p.muted.withValues(alpha: 0.4))),
              ]),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _pushLogin(const TelegramLoginScreen()),
                icon: const Icon(Icons.send_rounded, size: 20),
                label: Text(l.authTelegramButton),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _loading ? null : () => _pushLogin(const InviteScreen()),
                child: Text(l.authInviteButton),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pushLogin(Widget screen) async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => screen));
    if (ok == true && mounted) Navigator.pop(context, true);
  }
}
