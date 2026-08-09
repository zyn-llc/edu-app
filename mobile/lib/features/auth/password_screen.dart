import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../auth/token_store.dart';
import '../../core/breakpoints.dart';
import '../../core/prefs.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';
import '../referral/invite_friends.dart';

/// Foydalanuvchi nomi + parol bilan kirish va ro'yxatdan o'tish.
///
/// ## Nega qo'shildi (2026-08-06)
///
/// Mavjud uch yo'lning hech biri "qaytib kirish" ni yaxshi bajarmaydi:
///
///   * telefon+OTP — prodda o'chirilgan;
///   * taklif kodi — bir martalik, ikkinchi marta ishlamaydi;
///   * Telegram   — ishlaydi, lekin har kirishda brauzerdan Telegram'ga
///     o'tish, botda «Start» bosish va qaytish kerak. Sinovchilar buni har
///     safar YANGIDAN RO'YXATDAN O'TISH deb qabul qilishdi — aynan shu
///     shikoyat keldi.
///
/// Parol bu oqimni bitta ekranga siqadi va tashqi ilovaga umuman chiqmaydi.
///
/// ## Ikki holat, bitta ekran
///
/// Kirish va ro'yxatdan o'tish alohida ekran EMAS: farqi bitta qo'shimcha
/// maydon (ism) va tugma matni. Ikkiga bo'lish foydalanuvchini "qaysi biriga
/// bosay" degan keraksiz tanlov oldiga qo'yadi.
class PasswordScreen extends ConsumerStatefulWidget {
  const PasswordScreen({super.key, this.startInRegister = false});

  /// `true` — darhol ro'yxatdan o'tish holatida ochiladi.
  final bool startInRegister;

  @override
  ConsumerState<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends ConsumerState<PasswordScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _inviteCode = TextEditingController();
  final _passwordFocus = FocusNode();

  late bool _register = widget.startInRegister;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  /// `null` — hali tekshirilmadi yoki server javob bermadi.
  bool? _free;
  Timer? _debounce;

  /// Nom maydonini qurilmada saqlangan qiymat to'ldirganmi. Ro'yxatdan
  /// o'tishga o'tilganda uni tozalash uchun kerak.
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _username.addListener(_onUsernameChanged);
    // Qaytib kirayotgan odam nomini QAYTA TERMASIN.
    //
    // Sinovchilar shikoyati aynan shu edi: hisob bor, lekin har safar
    // nomni eslab, harfma-harf yozish kerak. Bitta harf xato bo'lsa server
    // «nom yoki parol noto'g'ri» deydi (ataylab — qaysi biri xato ekanini
    // aytish hisob bor-yo'qligini oshkor qiladi), o'quvchi esa parolni
    // ayblab, uni qayta-qayta almashtiradi.
    //
    // Faqat KIRISH holatida to'ldiriladi: ro'yxatdan o'tishda eski nom
    // maydonda tursa, foydalanuvchi uni band deb o'ylaydi.
    if (!_register) {
      final saved = ref
          .read(sharedPreferencesProvider)
          .getString(PrefKeys.lastUsername);
      if (saved != null && saved.isNotEmpty) {
        _username.text = saved;
        _prefilled = true;
        // Kursor parolga tushsin — nom allaqachon tayyor.
        _passwordFocus.requestFocus();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _username.removeListener(_onUsernameChanged);
    _username.dispose();
    _password.dispose();
    _name.dispose();
    _inviteCode.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ //
  //  Nom bo'shligini tekshirish                                        //
  // ------------------------------------------------------------------ //
  /// Har harfda so'rov yubormaymiz: 400 ms jim turgandan keyin bittasi
  /// ketadi. Aks holda "zizu" yozish 4 ta so'rov degani va ular teskari
  /// tartibda qaytib, natija chalkashishi mumkin.
  void _onUsernameChanged() {
    _debounce?.cancel();
    if (!_register) return;
    final name = _username.text.trim();
    if (_free != null) setState(() => _free = null);
    if (name.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final free = await ref.read(authRepositoryProvider).usernameFree(name);
      // Javob kelguncha foydalanuvchi yozishda davom etgan bo'lishi mumkin —
      // eskirgan natijani ko'rsatmaymiz.
      if (!mounted || _username.text.trim() != name) return;
      setState(() => _free = free);
    });
  }

  /// Serverdan olingan bayroq: parol bilan YANGI hisob ochish taklif kodi
  /// so'raydimi. Standart `true` (xavfsiz tomon) — provider hali
  /// yuklanmagan yoki xato bo'lsa ham kod maydoni talab qilinadi, aks
  /// holda foydalanuvchi kodsiz yuborib, tushunarsiz xato oladi.
  ///
  /// `ref.read` — bu `build()` DAN TASHQARIDA chaqiriladi (tugma bosilganda).
  /// `ref.watch` faqat `build()` ichida kerak; bu yerda qiymat bir martalik
  /// o'qiladi, qayta chizishga hojat yo'q.
  bool _needsInviteNow() {
    if (!_register) return false;
    return ref.read(authMethodsProvider).maybeWhen(
        data: (v) => v.passwordRegisterRequiresInvite, orElse: () => true);
  }

  // ------------------------------------------------------------------ //
  Future<void> _submit() async {
    final l = L10n.of(context);
    final name = _username.text.trim();
    final pw = _password.text;
    final needsInvite = _needsInviteNow();

    if (name.length < 3) {
      setState(() => _error = l.pwUsernameTooShort);
      return;
    }
    if (_register && !RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(name)) {
      setState(() => _error = l.pwUsernameShape);
      return;
    }
    if (pw.length < 6) {
      setState(() => _error = l.pwTooShort);
      return;
    }
    if (needsInvite && _inviteCode.text.trim().length < 4) {
      setState(() => _error = l.pwInviteRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final repo = ref.read(authRepositoryProvider);
    try {
      final pair = _register
          ? await repo.register(name, pw,
              displayName: _name.text.trim(),
              inviteCode: needsInvite ? _inviteCode.text.trim() : null,
              // `?ref=USERNAME` orqali kelgan bo'lsa — mukofotsiz kuzatuv,
              // batafsili `invite_friends.dart` da.
              referredBy: ref.read(pendingReferrerProvider))
          : await repo.login(name, pw);
      await ref.read(authControllerProvider.notifier).completeLogin(pair);
      // Nom shu qurilmada eslab qolinadi — keyingi kirishda maydon tayyor.
      // Parol EMAS, faqat nom: u reytingda va bellashuv havolasida
      // allaqachon ochiq ko'rinadi, ya'ni sir emas.
      await ref
          .read(sharedPreferencesProvider)
          .setString(PrefKeys.lastUsername, name);
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final errType = data is Map ? data['type'] as String? : null;
      setState(() => _error = errType == 'urn:bilim:auth:invite_required'
          ? l.inviteRejected
          : switch (code) {
              401 => l.pwBadCredentials,
              409 => l.pwUsernameTaken,
              400 => l.pwInvalidInput,
              429 => l.authTooMany,
              404 => l.pwUnavailable,
              _ => l.authNetworkError,
            });
    } catch (_) {
      setState(() => _error = l.authNetworkError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------------ //
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = Theme.of(context).extension<AppPalette>()!;

    // Nom holati: bo'sh / band / noma'lum. Yozayotgan paytda ko'rinadi,
    // ya'ni forma yuborilgach "band" xatosini ko'rish holati kamayadi.
    String? helper;
    Color? helperColor;
    if (_register && _username.text.trim().length >= 3 && _free != null) {
      helper = _free! ? l.pwUsernameFree : l.pwUsernameTaken;
      helperColor = _free! ? p.success : p.danger;
    }

    // `ref.watch` — bu yerda, `build()` ichida, chunki provider
    // yuklangach ekran qayta chizilib kod maydonini ko'rsatishi/
    // yashirishi kerak. Standart `true`: hali yuklanmagan bo'lsa ham
    // xavfsiz tomonga (kod so'rash) og'amiz.
    final needsInvite = _register &&
        ref.watch(authMethodsProvider).maybeWhen(
            data: (v) => v.passwordRegisterRequiresInvite,
            orElse: () => true);

    return Scaffold(
      appBar: AppBar(
        title: Text(_register ? l.pwRegisterTitle : l.pwLoginTitle),
      ),
      body: ContentWidth(
        maxWidth: 480,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: p.primaryTint, shape: BoxShape.circle),
                child: Icon(Icons.lock_outline_rounded,
                    size: 34, color: scheme.primary),
              ),
            ),
            const Gap.md(),
            Text(_register ? l.pwRegisterLead : l.pwLoginLead,
                style: text.bodySmall, textAlign: TextAlign.center),
            const Gap.lg(),

            Text(l.pwUsernameLabel, style: text.titleSmall),
            const Gap.sm(),
            TextField(
              controller: _username,
              autofocus: true,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              inputFormatters: [
                LengthLimitingTextInputFormatter(20),
                // Serverdagi shart bilan bir xil. Kirillcha «с» lotincha «c»
                // ga o'xshaydi, lekin boshqa belgi — foydalanuvchi keyin
                // "parolim ishlamayapti" deb qolardi. Shu sababli faqat
                // lotin, raqam va pastki chiziq kiritishga ruxsat.
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              ],
              decoration: InputDecoration(
                hintText: 'zizu_11',
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                border: const OutlineInputBorder(),
                helperText: helper,
                helperStyle: helperColor == null
                    ? null
                    : TextStyle(color: helperColor, fontWeight: FontWeight.w600),
              ),
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const Gap.md(),

            Text(l.pwPasswordLabel, style: text.titleSmall),
            const Gap.sm(),
            TextField(
              controller: _password,
              focusNode: _passwordFocus,
              obscureText: _obscure,
              autofillHints: [
                _register ? AutofillHints.newPassword : AutofillHints.password
              ],
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(128)],
              decoration: InputDecoration(
                hintText: l.pwPasswordHint,
                prefixIcon: const Icon(Icons.key_outlined),
                // Ko'z tugmasi shart: parolni ko'rmasdan yozgan o'quvchi
                // xato yozib, "parol noto'g'ri" xabarini oladi va sababini
                // tushunmaydi.
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  tooltip: _obscure ? l.pwShow : l.pwHide,
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _loading ? null : _submit(),
            ),

            if (_register) ...[
              const Gap.md(),
              Text(l.pwNameLabel, style: text.titleSmall),
              const Gap.sm(),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                decoration: InputDecoration(
                  hintText: l.inviteNameHint,
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (needsInvite) ...[
                const Gap.md(),
                Text(l.inviteCodeLabel, style: text.titleSmall),
                const Gap.sm(),
                TextField(
                  controller: _inviteCode,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [LengthLimitingTextInputFormatter(32)],
                  decoration: InputDecoration(
                    hintText: 'K7M4-X9QP',
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                    border: const OutlineInputBorder(),
                    // Yopiq beta davrida NEGA kod so'ralayotganini tushuntiradi
                    // — aks holda parol yo'li Telegram'dan "qiyinroq" tuyulib,
                    // foydalanuvchi ortga qaytardi.
                    helperText: l.pwInviteHelp,
                  ),
                ),
              ],
              const Gap.sm(),
              // Tiklash yo'li yo'qligi OCHIQ aytiladi. Yashirilsa,
              // parolini unutgan o'quvchi hisobini yo'qotadi va biz buni
              // faqat u shikoyat qilganda bilamiz.
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 16, color: p.muted),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(l.pwNoRecovery,
                      style: text.bodySmall?.copyWith(color: p.muted)),
                ),
              ]),
            ],

            const Gap.lg(),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_register ? l.pwRegisterSubmit : l.pwLoginSubmit),
            ),
            const Gap.sm(),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _register = !_register;
                        _error = null;
                        _free = null;
                        // Ro'yxatdan o'tishga o'tilganda oldindan
                        // to'ldirilgan ESKI nom tozalanadi. Aks holda
                        // foydalanuvchi o'z nomini ko'radi, ustiga
                        // "bu nom band" chiqadi va bu qarama-qarshi
                        // tuyuladi — nom band emas, u O'ZINIKI.
                        if (_register && _prefilled) {
                          _username.clear();
                          _prefilled = false;
                        }
                      }),
              child: Text(_register ? l.pwHaveAccount : l.pwNoAccount),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kirgan foydalanuvchiga parol o'rnatish varag'i (profil ekranidan).
///
/// Telegram yoki taklif kodi bilan kirgan hisob shu yerda nom+parol oladi.
/// Shundan keyin u ikkala yo'l bilan ham kira oladi — Telegram esa amalda
/// "parolni unutdim" ning o'rnini bosadi.
class SetPasswordSheet extends ConsumerStatefulWidget {
  const SetPasswordSheet({super.key, this.existingUsername});

  /// Hisobda nom allaqachon bo'lsa — u qulflangan holda ko'rsatiladi.
  final String? existingUsername;

  static Future<bool> show(BuildContext context, {String? existingUsername}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SetPasswordSheet(existingUsername: existingUsername),
      ),
    );
    return ok == true;
  }

  @override
  ConsumerState<SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends ConsumerState<SetPasswordSheet> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  bool get _locked => (widget.existingUsername ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _username.text = widget.existingUsername ?? '';
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = L10n.of(context);
    final name = _username.text.trim();
    if (!_locked && !RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(name)) {
      setState(() => _error = l.pwUsernameShape);
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = l.pwTooShort);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // `Navigator`, `ScaffoldMessenger` va matnlar await'dan OLDIN olinadi:
    // varaq yopilgandan keyin `context` bilan ishlash mumkin emas.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final okText = l.pwSaved;
    final taken = l.pwUsernameTaken;
    final invalid = l.pwInvalidInput;
    final netError = l.authNetworkError;
    try {
      final pair = await ref
          .read(authRepositoryProvider)
          .setPassword(_password.text, username: _locked ? null : name);
      // Server parolni almashtirganda BARCHA eski refresh tokenlarni bekor
      // qiladi. Yangi juftlik saqlanmasa, foydalanuvchi 15 daqiqadan keyin
      // (access token muddati) o'zini chiqarib yuborgan bo'lardi.
      if (pair != null) {
        await ref.read(tokenStoreProvider).save(
            pair.accessToken, pair.refreshToken);
      }
      // Profildagi "parol o'rnatilgan" holati `username` maydoniga qarab
      // chiziladi — uni yangilash uchun /me qayta o'qiladi.
      await ref.read(authControllerProvider.notifier).refreshMe();
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(okText)));
    } on DioException catch (e) {
      setState(() => _error = switch (e.response?.statusCode) {
            409 => taken,
            400 => invalid,
            _ => netError,
          });
    } catch (_) {
      setState(() => _error = netError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final p = Theme.of(context).extension<AppPalette>()!;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.pwSetTitle, style: text.titleLarge),
            const Gap.sm(),
            Text(l.pwSetLead,
                style: text.bodySmall?.copyWith(color: p.muted)),
            const Gap.md(),
            TextField(
              controller: _username,
              enabled: !_locked,
              inputFormatters: [
                LengthLimitingTextInputFormatter(20),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              ],
              decoration: InputDecoration(
                labelText: l.pwUsernameLabel,
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                border: const OutlineInputBorder(),
              ),
            ),
            const Gap.sm(),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              inputFormatters: [LengthLimitingTextInputFormatter(128)],
              decoration: InputDecoration(
                labelText: l.pwPasswordLabel,
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _loading ? null : _submit(),
            ),
            const Gap.md(),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.pwSetSubmit),
            ),
          ],
        ),
      ),
    );
  }
}
