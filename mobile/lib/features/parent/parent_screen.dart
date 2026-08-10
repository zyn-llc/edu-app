import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/elevation.dart';
import '../../theme/spacing.dart';
import '../../widgets/app_footer.dart';
import '../../widgets/avatar.dart';
import '../subjects/subject_card.dart' show relativeDay;
import '../../widgets/empty_state.dart';
import '../auth/login_sheet.dart';
import 'child_detail_screen.dart';
import 'parent_data.dart';

class ParentScreen extends ConsumerWidget {
  const ParentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final auth = ref.watch(authControllerProvider);

    Widget body;
    if (auth.initializing) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!auth.isAuthenticated) {
      body = const _ParentLogin();
    } else {
      body = const _ParentHome();
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.navParent)),
      body: body,
    );
  }
}

class _ParentLogin extends ConsumerWidget {
  const _ParentLogin();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    return EmptyState(
      icon: Icons.family_restroom,
      title: l.navParent,
      message: l.parentLoginDesc,
      actionLabel: l.parentLoginCta,
      onAction: () => LoginSheet.show(context, reason: l.parentLoginDesc),
    );
  }
}

class _ParentHome extends ConsumerWidget {
  const _ParentHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final async = ref.watch(childrenProvider);

    return async.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: 3,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: Spacing.ms),
          child: Skeleton(height: 88, radius: Radii.lg),
        ),
      ),
      error: (e, _) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: l.errNoConnection,
        message: l.authNetworkError,
        actionLabel: l.retry,
        onAction: () => ref.invalidate(childrenProvider),
      ),
      data: (children) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(childrenProvider),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.md, Spacing.md, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
            if (children.isNotEmpty) ...[
              for (final c in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.ms),
                  child: InkWell(
                    borderRadius: Radii.cardRadius,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChildDetailScreen(child: c)),
                    ),
                    child: _ChildCard(child: c),
                  ),
                ),
              const Gap.sm(),
            ],
            _ParentSideCard(hasChildren: children.isNotEmpty),
            const Gap.ms(),
            const _StudentSideCard(),
                ]),
              ),
            ),
            const FooterSliver(),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- //
//  «Men ota-onaman» — farzand kodini kiritish                            //
// --------------------------------------------------------------------- //

class _ParentSideCard extends ConsumerWidget {
  final bool hasChildren;
  const _ParentSideCard({required this.hasChildren});

  Future<void> _addChild(BuildContext context, WidgetRef ref) async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.parentAddChild),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.parentAddChildDesc,
                style: Theme.of(ctx).textTheme.bodySmall),
            const Gap.ms(),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 4),
              inputFormatters: [
                LengthLimitingTextInputFormatter(6),
                UpperCaseFormatter(),
              ],
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              decoration: InputDecoration(
                hintText: l.parentEnterCode,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.parentLink)),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      await ref.read(parentRepositoryProvider).link(code);
      ref.invalidate(childrenProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.parentLinked)));
    } on DioException catch (e) {
      final msg = switch (e.response?.statusCode) {
        404 => l.parentLinkError,
        400 => l.parentSelfLink,
        401 => l.parentNeedLogin,
        _ => l.authNetworkError,
      };
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.authNetworkError)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    return _SectionCard(
      icon: Icons.family_restroom,
      title: l.parentIAmParent,
      description: hasChildren ? l.parentAddChildDesc : l.parentNoChildren,
      child: FilledButton.icon(
        onPressed: () => _addChild(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l.parentAddChild),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
      ),
    );
  }
}

class _StudentSideCard extends ConsumerStatefulWidget {
  const _StudentSideCard();
  @override
  ConsumerState<_StudentSideCard> createState() => _StudentSideCardState();
}

class _StudentSideCardState extends ConsumerState<_StudentSideCard> {
  bool _loading = false;
  LinkCode? _code;
  String? _error;

  Future<void> _generate() async {
    final l = L10n.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await ref.read(parentRepositoryProvider).createLinkCode();
      if (mounted) setState(() => _code = code);
    } catch (_) {
      if (mounted) setState(() => _error = l.authNetworkError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _code!.code));
    if (mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l.parentCodeCopied)));
    }
  }

  Future<void> _share() async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: l.parentShareText(_code!.code)));
    if (mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l.parentShareCopied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final p = Theme.of(context).extension<AppPalette>()!;

    return _SectionCard(
      icon: Icons.qr_code_2,
      title: l.parentIAmStudent,
      description: l.parentStudentDesc,
      child: Column(
        children: [
          if (_code != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: Radii.cardRadius,
                border: Border.all(color: scheme.primary),
              ),
              child: Column(
                children: [
                  SelectableText(
                    _code!.code,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        color: scheme.primary),
                  ),
                  const Gap.xs(),
                  Text(l.parentCodeExpires(_code!.expiresInSeconds ~/ 60),
                      style: TextStyle(fontSize: 12, color: p.muted)),
                  const Gap.ms(),
                  Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.xs,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: Text(l.parentCopyCode),
                      ),
                      OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: Text(l.parentShareCode),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap.ms(),
          ],
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: scheme.error)),
            const Gap.sm(),
          ],
          if (_code == null)
            FilledButton(
              onPressed: _loading ? null : _generate,
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.parentGenerateCode),
            )
          else
            OutlinedButton(
              onPressed: _loading ? null : _generate,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46)),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.parentRegenerate),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = Theme.of(context).extension<AppPalette>()!;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: p.hairline),
        boxShadow: Shadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
          ]),
          const Gap.sm(),
          Text(description,
              style: TextStyle(fontSize: 13, height: 1.45, color: p.muted)),
          const Gap.md(),
          child,
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final ChildSummary child;
  const _ChildCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;
    final name = child.displayName?.isNotEmpty == true
        ? child.displayName!
        : l.lbAnonymous;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: p.hairline),
        boxShadow: Shadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                  name: child.displayName,
                  colorIndex: child.avatarColor,
                  size: 40),
              const SizedBox(width: Spacing.ms),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (child.grade != null)
                Text(l.gradeN(child.grade!),
                    style: TextStyle(color: p.muted, fontSize: 13)),
            ],
          ),
          const Gap.ms(),

          //
          // muntazam, qanday ketyapti.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(
                label: l.parentThisWeek,
                value: '${child.answered7d}',
              ),
              _Stat(
                label: l.parentActiveDays,
                value: '${child.activeDays7d}/7',
              ),
              _Stat(
                label: l.parentAccuracy7d,
                value: child.answered7d == 0
                    ? '—'
                    : '${(child.accuracy7d * 100).round()}%',
              ),
            ],
          ),
          const Gap.ms(),
          Row(children: [
            Icon(Icons.schedule_rounded, size: 15, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                child.lastPracticedAt == null
                    ? l.parentNeverPracticed
                    : '${l.lastPractice}: '
                        '${relativeDay(l, child.lastPracticedAt!)}',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ),
            Text(l.parentOpenDetail,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary)),
            Icon(Icons.chevron_right_rounded, size: 16, color: scheme.primary),
          ]),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: scheme.primary)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: p.muted)),
      ],
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
