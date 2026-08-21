/// Модели версии перечня и статистики (п. 7, 8.7 ТЗ).
library;

/// Статусы версии (п. 7 ТЗ).
enum VersionStatus {
  downloading('DOWNLOADING'),
  parsed('PARSED'),
  pendingReview('PENDING_REVIEW'),
  confirmed('CONFIRMED'),
  autoPublished('AUTO_PUBLISHED'),
  published('PUBLISHED'),
  error('ERROR');

  const VersionStatus(this.id);

  final String id;

  static VersionStatus byId(String id) => VersionStatus.values.firstWhere(
        (s) => s.id == id,
        orElse: () => VersionStatus.error,
      );
}

/// Счётчики версии (идут в письмо и в UI).
class VersionCounters {
  const VersionCounters({
    this.total = 0,
    this.added = 0,
    this.excluded = 0,
    this.changed = 0,
    this.review = 0,
    this.edited = 0,
  });

  /// Всего записей в первоисточнике.
  final int total;

  /// Новых записей относительно предыдущей версии.
  final int added;

  /// Исчезнувших записей (в CSV не попадают, Р-1).
  final int excluded;

  /// Изменившихся записей.
  final int changed;

  /// Записей, требующих проверки (confidence = review).
  final int review;

  /// Записей с применёнными ручными правками.
  final int edited;

  Map<String, Object?> toJson() => {
        'total': total,
        'new': added,
        'excluded': excluded,
        'changed': changed,
        'review': review,
        'edited': edited,
      };

  static VersionCounters fromJson(Map<String, Object?> json) => VersionCounters(
        total: _int(json['total']),
        added: _int(json['new']),
        excluded: _int(json['excluded']),
        changed: _int(json['changed']),
        review: _int(json['review']),
        edited: _int(json['edited']),
      );

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  @override
  String toString() => 'total=$total new=$added excluded=$excluded '
      'changed=$changed review=$review edited=$edited';
}

/// Версия перечня.
class PerechenVersion {
  PerechenVersion({
    required this.id,
    required this.actualityDate,
    required this.downloadedAt,
    required this.fileSha256,
    required this.sourcePath,
    required this.status,
    this.counters = const VersionCounters(),
    this.errorText,
    this.publishedAt,
    this.publishedFileName,
    this.confirmedBy,
  });

  final int id;

  /// Дата актуальности данных (ячейка A2) — по ней сравниваются версии.
  final DateTime actualityDate;

  final DateTime downloadedAt;
  final String fileSha256;
  final String sourcePath;
  final VersionStatus status;
  final VersionCounters counters;
  final String? errorText;
  final DateTime? publishedAt;
  final String? publishedFileName;
  final String? confirmedBy;

  bool get isPublished =>
      status == VersionStatus.published || publishedAt != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'actualityDate': actualityDate.toIso8601String(),
        'downloadedAt': downloadedAt.toIso8601String(),
        'fileSha256': fileSha256,
        'sourcePath': sourcePath,
        'status': status.id,
        'counters': counters.toJson(),
        'errorText': errorText,
        'publishedAt': publishedAt?.toIso8601String(),
        'publishedFileName': publishedFileName,
        'confirmedBy': confirmedBy,
      };
}
