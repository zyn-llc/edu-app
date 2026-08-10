import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import 'password_screen.dart';
import '../../theme/app_colors.dart';
import '../../core/breakpoints.dart';

class TelegramLoginScreen extends ConsumerStatefulWidget {
  const TelegramLoginScreen({super.key});

  @override
  ConsumerState<TelegramLoginScreen> createState() =>
      _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends ConsumerState<TelegramLoginScreen> {
  TelegramLogin? _session;
  Timer? _timer;

  bool _polling = false;
  bool _starting = true;
  bool _opened = false;
  String? _error;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _start() async {
    _stopPolling();
    setState(() {
      _starting = true;
      _error = null;
      _elapsed = 0;
      _opened = false;
      _session = null;
    });
    try {
      final s = await ref.read(authRepositoryProvider).telegramStart();
      if (!mounted) return;
      setState(() {
        _session = s;
        _starting = false;
      });
      // boshlanadi.
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = e.response?.statusCode == 404
            ? L10n.of(context).telegramDisabled
            : L10n.of(context).authNetworkError;
      });
    }
  }

  ///
  /// soniyada so'rash 300 ta bekor so'rov degani. Bosqichma-bosqich uzaytirish
  int _pollDelaySeconds() {
    if (_elapsed < 30) return 2;
    if (_elapsed < 120) return 4;   // 2 daqiqagacha — o'rtacha
    return 8;
  }

  void _ensurePolling() {
    if (_polling) return;
    _polling = true;
    _scheduleNextPoll();
  }

  void _stopPolling() {
    _polling = false;
    _timer?.cancel();
    _timer = null;
  }

  ///
  /// timer oldingi so'rov tugashini kutmaydi — sekin tarmoqda so'rovlar
  /// bir-birining ustiga chiqib ketardi.
  void _scheduleNextPoll() {
    final step = _pollDelaySeconds();
    _timer = Timer(Duration(seconds: step), () async {
      if (!mounted || !_polling) return;
      final s = _session;
      if (s == null) return;

      _elapsed += step;
      if (_elapsed > s.expiresInSeconds) {
        _stopPolling();
        if (mounted) setState(() => _error = L10n.of(context).telegramExpired);
        return;
      }

      try {
        final pair =
            await ref.read(authRepositoryProvider).telegramPoll(s.nonce);
        if (pair != null) {
          _stopPolling();
          await ref.read(authControllerProvider.notifier).completeLogin(pair);
          if (!mounted) return;
          final me = ref.read(authControllerProvider).user;
          if (me != null && (me.username == null || me.username!.isEmpty)) {
            await SetPasswordSheet.show(context);
          }
          if (mounted) Navigator.pop(context, true);
          return;
        }
        // pair == null → hali «Start» bosilmagan, zanjir davom etadi.
      } on DioException catch (e) {
        if (e.response?.statusCode == 410) {
          _stopPolling();
          if (mounted) {
            setState(() => _error = L10n.of(context).telegramExpired);
          }
          return;
        }
      }

      if (mounted && _polling) _scheduleNextPoll();
    });
  }

  Future<void> _openTelegram() async {
    final s = _session;
    if (s == null) return;

    // On web a blocked pop-up makes `launchUrl` return false.
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(s.deepLink),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _opened = true;
      if (!ok) _error = L10n.of(context).telegramNotInstalled;
    });
    _ensurePolling();
  }

  Future<void> _copyLink() async {
    final s = _session;
    if (s == null) return;
    await Clipboard.setData(ClipboardData(text: s.deepLink));
    if (!mounted) return;
    setState(() => _opened = true);
    _ensurePolling();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;
    final expired = _error == l.telegramExpired;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(l.telegramTitle),
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
              child: Icon(Icons.send_rounded, size: 34, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(l.telegramExplainer,
                style: TextStyle(fontSize: 14, height: 1.5, color: p.muted)),
            const SizedBox(height: 24),
            if (_starting)
              const Center(child: CircularProgressIndicator())
            else if (_error != null) ...[
              Text(_error!,
                  style: TextStyle(color: scheme.error, fontSize: 14, height: 1.4)),
              const SizedBox(height: 16),
              if (expired)
                OutlinedButton(
                  onPressed: _start,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                  child: Text(l.telegramRetry),
                ),
            ] else ...[
              //
              // ikkalasini solishtiradi va shundan keyingina tasdiqlaydi.
              if ((_session?.confirmCode ?? '').isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      Text(l.telegramCodeLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: p.muted)),
                      const SizedBox(height: 8),
                      SelectableText(
                        _session!.confirmCode,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 8,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(l.telegramCodeHint,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: p.muted)),
                const SizedBox(height: 18),
              ],
              FilledButton.icon(
                onPressed: _openTelegram,
                icon: const Icon(Icons.open_in_new, size: 20),
                label: Text(l.telegramOpen),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 14),
  
              if (_session != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _session!.deepLink,
                          style: TextStyle(fontSize: 12.5, color: p.muted),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: l.copy,
                        onPressed: _copyLink,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              if (_opened)
                Row(
                  children: [
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(l.telegramWaiting,
                          style: TextStyle(fontSize: 13, color: p.muted)),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
