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

/// Telegram orqali kirish.
///
/// Oqim: server bir martalik havola beradi -> foydalanuvchi botni ochib «Start»
/// bosadi -> ilova serverdan «bo'ldimi?» deb so'rab turadi -> token oladi.
///
/// Foydalanuvchi hech narsa yozmaydi: kod ham, telefon ham kerak emas. SMS
/// shlyuzi tayyor bo'lmaganda eng qulay yo'l shu.
///
/// So'rov 2 soniyada bir marta, ko'pi bilan havola muddatigacha. Ilova fonga
/// ketganda ham timer ishlayveradi — foydalanuvchi Telegram'dan qaytganda
/// ekran allaqachon o'zgargan bo'ladi.
class TelegramLoginScreen extends ConsumerStatefulWidget {
  const TelegramLoginScreen({super.key});

  @override
  ConsumerState<TelegramLoginScreen> createState() =>
      _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends ConsumerState<TelegramLoginScreen> {
  TelegramLogin? _session;
  Timer? _timer;

  /// So'rov zanjiri ishlayaptimi. `Timer.isActive` yetarli emas: so'rov
  /// yuborilgan paytda timer allaqachon "o'chgan" bo'ladi.
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
      // DIQQAT: bu yerda so'rov BOSHLANMAYDI. Foydalanuvchi havolani ochmasdan
      // turib so'rov yuborish — real serverda bekorga trafik, MOCK rejimda esa
      // undan ham yomoni: mock 5 soniyadan keyin "kirdi" deb javob beradi va
      // ekran havolani ko'rsatishga ulgurmay o'zi yopilib ketardi.
      // So'rov `_ensurePolling()` bilan, foydalanuvchi harakatidan keyin
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

  /// So'rov oralig'i vaqt o'tishi bilan uzayadi.
  ///
  /// NEGA: odam Telegramda «Start» ni odatda dastlabki 15–20 soniyada bosadi.
  /// Shu oynada tez so'rash (2 s) kirishni bir zumda sezadi. Undan keyin esa
  /// foydalanuvchi ilovadan chalg'igan bo'ladi — 10 daqiqa davomida har 2
  /// soniyada so'rash 300 ta bekor so'rov degani. Bosqichma-bosqich uzaytirish
  /// buni ~90 taga tushiradi, sezgirlikni esa deyarli yo'qotmaydi.
  int _pollDelaySeconds() {
    if (_elapsed < 30) return 2;    // birinchi 30 s — tez
    if (_elapsed < 120) return 4;   // 2 daqiqagacha — o'rtacha
    return 8;                       // undan keyin — kamdan-kam
  }

  /// So'rovni boshlaydi. Ikki marta chaqirilsa ham bitta zanjir bo'ladi
  /// (foydalanuvchi tugmani ham bosishi, havolani ham nusxalashi mumkin).
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

  /// Bitta so'rovni rejalashtiradi va javobdan keyin O'ZI keyingisini qo'yadi.
  ///
  /// `Timer.periodic` ATAYLAB ishlatilmadi: oraliq o'zgaruvchan, va periodic
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
          // Hisobni SAQLAB QO'YISH taklifi.
          //
          // Sabab: Telegram bilan kirish tez, lekin QAYTIB kirishga
          // yaramaydi — har safar brauzerdan chiqib, botda «Start» bosish
          // kerak. Sinovchi buni "yana ro'yxatdan o'tyapman" deb qabul
          // qildi. Shu tufayli kirish tugagan zahoti (foydalanuvchi
          // hisobi allaqachon borligini bilgan paytda) parol taklif
          // qilinadi.
          //
          // Nomi allaqachon bo'lsa (masalan ilgari qo'ygan) varaq uni
          // qulflangan holda ko'rsatadi. Parol allaqachon o'rnatilgan
          // bo'lsa varaq umuman chiqmaydi — buni `hasPassword` hal qiladi.
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
        // Boshqa xatolar (tarmoq uzilishi) — keyingi urinishda o'zi tuzaladi.
      }

      if (mounted && _polling) _scheduleNextPoll();
    });
  }

  Future<void> _openTelegram() async {
    final s = _session;
    if (s == null) return;

    // Webda pop-up blokirovkasi `launchUrl` ni `false` qaytarishga majbur
    // qilishi mumkin. Bunday holda ham havola ekranda ko'rinib turadi va
    // nusxalash mumkin — foydalanuvchi boshi berk ko'chada qolmaydi.
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
              // TASDIQ KODI — havoladan ham oldin.
              //
              // Bot xuddi shu kodni tugmada ko'rsatadi. Foydalanuvchi
              // ikkalasini solishtiradi va shundan keyingina tasdiqlaydi.
              // Usiz oqim bir bosishda hisob o'g'irlash edi: birov yuborgan
              // havolani bosgan odam bilmasdan o'z hisobiga kirishni
              // tasdiqlab yuborardi (izoh: app/services/telegram.py).
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
  
              // Havolaning O'ZI ham ko'rinib turadi. Brauzer yangi oynani
              // bloklasa yoki Telegram boshqa qurilmada bo'lsa — yagona yo'l shu.
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
