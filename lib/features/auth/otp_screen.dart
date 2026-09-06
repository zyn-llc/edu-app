import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../core/breakpoints.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String role;
  final String? debugCode; // dev only; prefilled to ease testing
  final int expiresInSeconds;
  const OtpScreen({
    super.key,
    required this.phone,
    required this.role,
    this.debugCode,
    this.expiresInSeconds = 300,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.debugCode ?? '');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final l = L10n.of(context);
    final code = _controller.text.trim();
    if (code.length < 4) {
      setState(() => _error = l.authInvalidCode);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pair = await ref
          .read(authRepositoryProvider)
          .verifyOtp(widget.phone, code);
      await ref.read(authControllerProvider.notifier).completeLogin(pair);
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      setState(() => _error = e.response?.statusCode == 401
          ? l.authInvalidCode
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(l.authCodeTitle),
      ),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(l.authCodeSentTo(widget.phone),
                style: TextStyle(fontSize: 14, height: 1.4, color: p.muted)),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, letterSpacing: 8),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(
                hintText: '••••••',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _loading ? null : _verify(),
            ),
            if (widget.debugCode != null) ...[
              const SizedBox(height: 10),
              Text(l.authDevCode(widget.debugCode!),
                  style: TextStyle(fontSize: 12, color: p.faint)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _loading ? null : _verify,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.authVerify),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loading ? null : () => Navigator.pop(context, false),
              child: Text(l.authResend),
            ),
          ],
        ),
      ),
    );
  }
}
