import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../l10n/app_localizations.dart';

const String kSupportTelegram = 'topagonuzbot';

class SupportSection extends ConsumerWidget {
  const SupportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.send),
        title: Text(l.supportTelegram),
        subtitle: const Text('@$kSupportTelegram'),
        onTap: () => launchUrl(
          Uri.parse('https://t.me/$kSupportTelegram'),
          mode: LaunchMode.externalApplication,
        ),
      ),
      ListTile(
        leading: const Icon(Icons.feedback_outlined),
        title: Text(l.supportFeedback),
        subtitle: Text(l.supportFeedbackSub),
        onTap: () => openFeedbackDialog(context, ref),
      ),
    ]);
  }
}

void openFeedbackDialog(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final msg = TextEditingController();
    final contact = TextEditingController();
    bool sending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l.supportFeedback),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: msg,
                maxLines: 4,
                maxLength: 2000,
                decoration: InputDecoration(
                  hintText: l.supportMessageHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contact,
                decoration: InputDecoration(
                  labelText: l.supportContactLabel,
                  hintText: l.supportContactHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      final text = msg.text.trim();
                      if (text.length < 3) return;
                      setState(() => sending = true);
                      try {
                        // Works logged-out too: a user whose login is broken
                        // is exactly who must be able to reach support.
                        await ref.read(dioProvider).post('/v1/feedback', data: {
                          'message': text,
                          if (contact.text.trim().isNotEmpty)
                            'contact': contact.text.trim(),
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.supportSent)));
                        }
                      } catch (_) {
                        setState(() => sending = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(l.supportFailed)));
                        }
                      }
                    },
              child: Text(l.supportSend),
            ),
          ],
        ),
      ),
    );
  }
