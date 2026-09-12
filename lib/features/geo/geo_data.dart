import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';

/// Reference geography: district -> mahalla / school.
///
/// Backend contract: MOBILE_ARCHITECTURE.md §8 (migration 040). Everything is
/// ID-based; the old free-text `district` / `school_number` / `mahalla` fields
/// are gone and a request carrying them gets a 422.
///
/// CACHING. The three list providers are `FutureProvider.family` WITHOUT
/// autoDispose, so a region's districts (and a district's mahallas/schools)
/// are fetched once and then reused for the rest of the session — the user
/// walks up and down the cascade while filling one form, and refetching on
/// every step change would make the picker feel broken on a slow connection.
/// Admin writes call `ref.invalidate(...)` on the exact family key they
/// changed, so a newly added row shows up immediately.

class GeoDistrict {
  final String id;
  final String regionCode;
  final String name;

  const GeoDistrict({
    required this.id,
    required this.regionCode,
    required this.name,
  });

  factory GeoDistrict.fromJson(Map<String, dynamic> j) => GeoDistrict(
        id: j['id'] as String,
        regionCode: j['region_code'] as String,
        name: j['name'] as String,
      );
}

class GeoMahalla {
  final String id;
  final String name;
  final String districtId;
  final String? district;
  final String? regionCode;

  const GeoMahalla({
    required this.id,
    required this.name,
    required this.districtId,
    this.district,
    this.regionCode,
  });

  factory GeoMahalla.fromJson(Map<String, dynamic> j) => GeoMahalla(
        id: j['id'] as String,
        name: j['name'] as String,
        districtId: j['district_id'] as String,
        district: j['district'] as String?,
        regionCode: j['region_code'] as String?,
      );
}

class GeoSchool {
  final String id;
  final String regionCode;
  final String? districtId;
  final String? district;
  final int number;
  final String? name;

  const GeoSchool({
    required this.id,
    required this.regionCode,
    required this.districtId,
    required this.district,
    required this.number,
    required this.name,
  });

  factory GeoSchool.fromJson(Map<String, dynamic> j) => GeoSchool(
        id: j['id'] as String,
        regionCode: j['region_code'] as String,
        districtId: j['district_id'] as String?,
        district: j['district'] as String?,
        number: (j['number'] as num).toInt(),
        name: j['name'] as String?,
      );

  /// "12-maktab" or "12-maktab · Prezident maktabi".
  String get label =>
      name == null || name!.isEmpty ? '$number-maktab' : '$number-maktab · $name';
}

/// Thrown for a duplicate name/number (HTTP 409) so screens can show the
/// message on the field instead of a generic error toast.
class GeoConflict implements Exception {
  final String message;
  const GeoConflict(this.message);
  @override
  String toString() => message;
}

class GeoRepository {
  final Ref ref;
  GeoRepository(this.ref);

  // ---- read (any signed-in user) ------------------------------------------
  Future<List<GeoDistrict>> districts(String regionCode) async {
    final res = await ref.read(dioProvider).get('/v1/geo/districts',
        queryParameters: {'region_code': regionCode});
    final items = (res.data as Map<String, dynamic>)['items'] as List;
    return [
      for (final e in items) GeoDistrict.fromJson(e as Map<String, dynamic>)
    ];
  }

  /// No `q`: the whole district is fetched once and filtered on the client.
  /// Server-side search exists (§8) but would re-hit the network on every
  /// keystroke; `limit` is raised instead so one fetch covers the district.
  Future<List<GeoMahalla>> mahallas(String districtId) async {
    final res = await ref.read(dioProvider).get('/v1/geo/mahallas',
        queryParameters: {'district_id': districtId, 'limit': 1000});
    final items = (res.data as Map<String, dynamic>)['items'] as List;
    return [
      for (final e in items) GeoMahalla.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<List<GeoSchool>> schools(String districtId) async {
    final res = await ref.read(dioProvider).get('/v1/geo/schools',
        queryParameters: {'district_id': districtId, 'limit': 1000});
    final items = (res.data as Map<String, dynamic>)['items'] as List;
    return [
      for (final e in items) GeoSchool.fromJson(e as Map<String, dynamic>)
    ];
  }

  // ---- write (admin only) --------------------------------------------------
  Future<T> _write<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final data = e.response?.data;
        throw GeoConflict(data is Map && data['detail'] is String
            ? data['detail'] as String
            : 'Bunday nom allaqachon mavjud');
      }
      rethrow;
    }
  }

  Future<GeoDistrict> createDistrict(String regionCode, String name) =>
      _write(() async {
        final res = await ref.read(dioProvider).post('/v1/admin/geo/districts',
            data: {'region_code': regionCode, 'name': name});
        return GeoDistrict.fromJson(res.data as Map<String, dynamic>);
      });

  Future<GeoDistrict> renameDistrict(String id, String name) =>
      _write(() async {
        final res = await ref
            .read(dioProvider)
            .patch('/v1/admin/geo/districts/$id', data: {'name': name});
        return GeoDistrict.fromJson(res.data as Map<String, dynamic>);
      });

  Future<GeoMahalla> createMahalla(String districtId, String name) =>
      _write(() async {
        final res = await ref.read(dioProvider).post('/v1/admin/geo/mahallas',
            data: {'district_id': districtId, 'name': name});
        return GeoMahalla.fromJson(res.data as Map<String, dynamic>);
      });

  Future<GeoMahalla> renameMahalla(String id, String name) => _write(() async {
        final res = await ref
            .read(dioProvider)
            .patch('/v1/admin/geo/mahallas/$id', data: {'name': name});
        return GeoMahalla.fromJson(res.data as Map<String, dynamic>);
      });

  /// `linkedExisting` is true when the row already existed because a student
  /// had typed that school into their profile before 040 — the backend adopts
  /// it into the reference list instead of creating a duplicate (§8).
  Future<({GeoSchool school, bool linkedExisting})> createSchool(
    String districtId,
    int number, {
    String? name,
  }) =>
      _write(() async {
        final res = await ref.read(dioProvider).post('/v1/admin/geo/schools',
            data: {
              'district_id': districtId,
              'number': number,
              if (name != null && name.isNotEmpty) 'name': name,
            });
        final j = res.data as Map<String, dynamic>;
        return (
          school: GeoSchool.fromJson(j),
          linkedExisting: j['linked_existing'] == true,
        );
      });

  Future<GeoSchool> patchSchool(String id, {int? number, String? name}) =>
      _write(() async {
        final res =
            await ref.read(dioProvider).patch('/v1/admin/geo/schools/$id', data: {
          if (number != null) 'number': number,
          if (name != null) 'name': name,
        });
        return GeoSchool.fromJson(res.data as Map<String, dynamic>);
      });
}

final geoRepositoryProvider = Provider<GeoRepository>((ref) => GeoRepository(ref));

/// Districts of one region. Keyed by `region_code`.
final districtsProvider =
    FutureProvider.family<List<GeoDistrict>, String>((ref, regionCode) {
  ref.watch(authControllerProvider);
  return ref.read(geoRepositoryProvider).districts(regionCode);
});

/// Mahallas of one district. Keyed by `district_id`.
final mahallasProvider =
    FutureProvider.family<List<GeoMahalla>, String>((ref, districtId) {
  ref.watch(authControllerProvider);
  return ref.read(geoRepositoryProvider).mahallas(districtId);
});

/// Schools of one district. Keyed by `district_id`. Only reference-list
/// schools come back — a school typed into a profile has no `district_id`
/// and is deliberately not offered (§8).
final schoolsProvider =
    FutureProvider.family<List<GeoSchool>, String>((ref, districtId) {
  ref.watch(authControllerProvider);
  return ref.read(geoRepositoryProvider).schools(districtId);
});
