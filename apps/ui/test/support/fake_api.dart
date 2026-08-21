/// Подставной API для виджет-тестов.
library;

import 'package:perechen_ui/src/api/api_client.dart';
import 'package:perechen_ui/src/models/models.dart';

Map<String, dynamic> versionJson({
  int id = 1,
  String status = 'PENDING_REVIEW',
  Map<String, dynamic> counters = const {
    'total': 3,
    'new': 1,
    'changed': 1,
    'excluded': 0,
    'review': 1,
    'edited': 0,
  },
  String? publishedAt,
  String? publishedFileName,
  String? confirmedBy,
}) =>
    {
      'id': id,
      'actualityDate': '2026-08-14T17:28:00+03:00',
      'downloadedAt': '2026-08-14T06:00:00+03:00',
      'status': status,
      'counters': counters,
      'targetFileName': 'perechen_organizatsij_272_FZ_2026_08_14.csv',
      'publishedAt': publishedAt,
      'publishedFileName': publishedFileName,
      'confirmedBy': confirmedBy,
    };

Map<String, dynamic> recordJson({
  String orgKey = '1076-р__2015-07-29',
  int rowNum = 4,
  String targetNo = '1',
  String nameRus = 'Национальный фонд в поддержку демократии',
  String nameAdd = 'The National Endowment for Democracy',
  String country = '',
  String confidence = 'ok',
  bool isNew = false,
  bool isChanged = false,
  bool isExcluded = false,
  List<String> editedFields = const [],
  List<Map<String, dynamic>> staleCorrections = const [],
  List<String> notes = const [],
  String rawName = '«Национальный фонд в поддержку демократии» '
      '(The National Endowment for Democracy)',
  String? previousRawName,
}) =>
    {
      'orgKey': orgKey,
      'rowNum': rowNum,
      'values': {
        'target_no': targetNo,
        'incl_order': '№ 1076-р от 29.07.2015',
        'gp_decision': 'от 28.07.2015',
        'name_rus': nameRus,
        'name_add': nameAdd,
        'country': country,
        'excl_order': '',
        'gp_cancel': '',
      },
      'autoValues': {
        'name_rus': 'Национальный фонд в поддержку демократии',
        'name_add': 'The National Endowment for Democracy',
        'country': '',
      },
      'editedFields': editedFields,
      'staleCorrections': staleCorrections,
      'candidates': [
        {
          'value': 'Национальный фонд в поддержку демократии',
          'kind': 'cyrillic',
          'excludedReason': null,
        },
        {
          'value': 'NED',
          'kind': 'abbreviation',
          'excludedReason': 'аббревиатура (правило 9)',
        },
      ],
      'notes': notes,
      'confidence': confidence,
      'isNew': isNew,
      'isChanged': isChanged,
      'isExcluded': isExcluded,
      'rawName': rawName,
      'previousRawName': previousRawName,
    };

/// Подставной клиент API: запоминает вызовы и отдаёт заготовленные данные.
class FakeApi implements PerechenApi {
  FakeApi({
    List<Map<String, dynamic>>? versions,
    List<Map<String, dynamic>>? records,
    Map<String, dynamic>? health,
  })  : _versions = versions ?? [versionJson()],
        _records = records ?? [recordJson()],
        _health = health ??
            {
              'lastCheckAt': '2026-08-14T06:00:00+03:00',
              'lastCheckStatus': 'new_version',
              'nextRunAt': '2026-08-15T06:00:00+03:00',
              'downloadCron': '0 6 * * *',
              'autoPublishCron': '0 20 * * *',
              'cdiDropDir': '/mnt/cdi/inbox',
              'timeZone': 'Europe/Moscow',
            };

  List<Map<String, dynamic>> _versions;
  List<Map<String, dynamic>> _records;
  final Map<String, dynamic> _health;

  final List<String> calls = [];
  String lastFilter = '';
  String lastSearch = '';
  Map<String, String> lastSavedValues = const {};
  int confirmCalls = 0;
  int checkNowCalls = 0;
  ApiException? failWith;

  void setRecords(List<Map<String, dynamic>> records) => _records = records;

  void setVersions(List<Map<String, dynamic>> versions) => _versions = versions;

  @override
  Future<HealthInfo> health() async {
    calls.add('health');
    return HealthInfo.fromJson(_health);
  }

  @override
  Future<List<VersionSummary>> versions() async {
    calls.add('versions');
    if (failWith != null) throw failWith!;
    return _versions.map(VersionSummary.fromJson).toList();
  }

  @override
  Future<VersionSummary> version(int id) async {
    calls.add('version:$id');
    return VersionSummary.fromJson(
      _versions.firstWhere((v) => v['id'] == id, orElse: () => _versions.first),
    );
  }

  @override
  Future<List<RecordItem>> records(
    int versionId, {
    String filter = 'all',
    String search = '',
  }) async {
    calls.add('records:$versionId:$filter:$search');
    lastFilter = filter;
    lastSearch = search;
    return _records.map(RecordItem.fromJson).toList();
  }

  @override
  Future<RecordItem> saveCorrection(
    int versionId,
    String orgKey,
    Map<String, String> values,
  ) async {
    calls.add('save:$orgKey');
    lastSavedValues = values;
    final updated = Map<String, dynamic>.from(_records.first);
    updated['values'] = {
      ...(updated['values']! as Map).cast<String, dynamic>(),
      ...values,
    };
    updated['editedFields'] = values.keys.toList();
    _records = [updated, ..._records.skip(1)];
    return RecordItem.fromJson(updated);
  }

  @override
  Future<RecordItem> revertCorrection(
    int versionId,
    String orgKey,
    List<String> fields,
  ) async {
    calls.add('revert:$orgKey');
    final updated = Map<String, dynamic>.from(_records.first);
    updated['values'] = {
      ...(updated['values']! as Map).cast<String, dynamic>(),
      ...(updated['autoValues']! as Map).cast<String, dynamic>(),
    };
    updated['editedFields'] = <String>[];
    _records = [updated, ..._records.skip(1)];
    return RecordItem.fromJson(updated);
  }

  @override
  Future<PublishResultInfo> confirm(int versionId) async {
    calls.add('confirm:$versionId');
    confirmCalls++;
    final published = versionJson(
      status: 'PUBLISHED',
      publishedAt: '2026-08-14T18:00:00+03:00',
      publishedFileName: 'perechen_organizatsij_272_FZ_2026_08_14.csv',
      confirmedBy: 'admin',
    );
    _versions = [published];
    return PublishResultInfo.fromJson({
      'fileName': 'perechen_organizatsij_272_FZ_2026_08_14.csv',
      'rows': 390,
      'cdiPath': '/mnt/cdi/inbox/perechen_organizatsij_272_FZ_2026_08_14.csv',
      'warnings': <Map<String, dynamic>>[],
      'version': published,
    });
  }

  @override
  Future<CheckResultInfo> checkNow() async {
    calls.add('checkNow');
    checkNowCalls++;
    return CheckResultInfo.fromJson({
      'status': 'newVersion',
      'message': 'создана версия 14.08.2026',
      'versionId': 1,
    });
  }

  @override
  Future<List<EventItem>> events({int limit = 200}) async {
    calls.add('events');
    return [
      EventItem.fromJson({
        'id': 2,
        'ts': '2026-08-14T06:00:05+03:00',
        'type': 'version_created',
        'payload': {'counters': {}},
        'versionId': 1,
      }),
      EventItem.fromJson({
        'id': 1,
        'ts': '2026-08-14T06:00:00+03:00',
        'type': 'download_failed',
        'payload': {'error': 'таймаут'},
        'versionId': null,
      }),
    ];
  }

  @override
  Uri exportUri(int versionId) =>
      Uri.parse('http://localhost/api/versions/$versionId/export.csv');
}
