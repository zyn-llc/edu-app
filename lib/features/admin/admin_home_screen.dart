import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../theme/spacing.dart';
import 'admin_sections_screen.dart';
import 'geo_admin_screen.dart';

/// Admin hub. Reached from Settings, and only for admin roles.
///
/// The role comes from `/v1/me` on every launch, not from the token, so a
/// revoked admin loses the entry on the next refresh. The server checks the
/// role again on every admin call — this gate only hides the door.
const adminRoles = {'admin', 'super_admin'};

bool isAdmin(String? role) => role != null && adminRoles.contains(role);

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authControllerProvider).user?.role;

    if (!isAdmin(role)) {
      // Defence in depth: the entry is hidden for non-admins, but a stale
      // route (deep link, back stack) must not show the panel either.
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(child: Text('Ruxsat yo\'q')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: ListView(
        padding: Spacing.page(context),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: Spacing.sm),
            child: ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Ma\'lumotnoma'),
              subtitle:
                  const Text('Tuman, mahalla va maktablar ro\'yxati'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GeoAdminScreen())),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: Spacing.sm),
            child: ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('Jonli sinovlar'),
              subtitle: const Text('Sinov yaratish va ro\'yxat'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminSectionsScreen())),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: Spacing.md),
            child: Text(
              'Eslatma: ma\'lumotnomadan yozuv o\'chirib bo\'lmaydi — u rasmiy '
              'natijalarga bog\'langan. Xato nom «tahrirlash» orqali '
              'to\'g\'rilanadi.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
