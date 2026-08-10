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
import '../challenges/challenge_invite.dart' show pendingJoinCodeProvider;
import '../referral/invite_friends.dart';

///
///
///
///   * telefon+OTP — prodda o'chirilgan;
///
///
///
class PasswordScreen extends ConsumerStatefulWidget {
  const PasswordScreen({super.key, this.startInRegister = false});

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

  bool? _free;
  Timer? _debounce;

  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _username.addListener(_onUsernameChanged);
    // Qaytib kirayotgan odam nomini QAYTA TERMASIN.
    //
    // ayblab, uni qayta-qayta almashtiradi.
    //
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
  /// ketadi. Aks holda "zizu" yozish 4 ta so'rov degani va ular teskari
  void _onUsernameChanged() {
    _debounce?.cancel();
    if (!_register) return;
    final name = _username.text.trim();
    if (_free != null) setState(() => _free = null);
    if (name.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final free = await ref.read(authRepositoryProvider).usernameFree(name);
      if (!mounted || _username.text.trim() != name) return;
      setState(() => _free = free);
    });
  }

  bool _needsInviteNow() {
    if (!_register) return false;
    if (_joinCode != null) return false;
    return ref.read(authMethodsProvider).maybeWhen(
        data: (v) => v.passwordRegisterRequiresInvite, orElse: () => true);
  }

  String? get _joinCode {
    final c = ref.read(pendingJoinCodeProvider)?.trim();
    return (c == null || c.isEmpty) ? null : c;
  }

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
              joinCode: _joinCode,
              // batafsili `invite_friends.dart` da.
              referredBy: ref.read(pendingReferrerProvider))
          : await repo.login(name, pw);
      await ref.read(authControllerProvider.notifier).completeLogin(pair);
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

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = Theme.of(context).extension<AppPalette>()!;

    String? helper;
    Color? helperColor;
    if (_register && _username.text.trim().length >= 3 && _free != null) {
      helper = _free! ? l.pwUsernameFree : l.pwUsernameTaken;
      helperColor = _free! ? p.success : p.danger;
    }

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
            Text(
                !_register
                    ? l.pwLoginLead
                    // o'tish so'ralayotganini kutmagan.
                    : (_joinCode != null ? l.pwJoinLead : l.pwRegisterLead),
                style: text.bodySmall,
                textAlign: TextAlign.center),
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
                    // — aks holda parol yo'li Telegram'dan "qiyinroq" tuyulib,
                    helperText: l.pwInviteHelp,
                  ),
                ),
              ],
              const Gap.sm(),
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

///
/// "parolni unutdim" ning o'rnini bosadi.
class SetPasswordSheet extends ConsumerStatefulWidget {
  const SetPasswordSheet({super.key, this.existingUsername});

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
      if (pair != null) {
        await ref.read(tokenStoreProvider).save(
            pair.accessToken, pair.refreshToken);
      }
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
