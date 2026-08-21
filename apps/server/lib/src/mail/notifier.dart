/// Формирование и отправка писем ответственному (FR-8, п. 9 ТЗ).
library;

import 'package:perechen_core/perechen_core.dart';

import '../config/app_config.dart';
import '../db/database.dart';
import '../util/logging.dart';
import '../util/moscow_time.dart';
import 'mail_sender.dart';

class Notifier {
  Notifier({
    required this.config,
    required this.sender,
    required this.db,
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger();

  final AppConfig config;
  final MailSender sender;
  final AppDatabase db;
  final AppLogger _logger;

  String versionUrl(int versionId, {String filter = 'new'}) =>
      '${config.uiBaseUrl}/#/versions/$versionId?filter=$filter';

  /// 1. Новая версия обнаружена (основное письмо).
  Future<void> newVersionFound({
    required PerechenVersion version,
    required List<ParsedRecord> addedRecords,
    required List<ParsedRecord> excludedRecords,
    required DateTime autoPublishDeadline,
    List<String> warnings = const [],
  }) async {
    final counters = version.counters;
    final subject = 'Перечень 272-ФЗ: новая версия от '
        '${formatRuDate(version.actualityDate)} '
        '(+${counters.added} / -${counters.excluded})';

    String namesOf(List<ParsedRecord> records) {
      if (records.isEmpty) return '  (нет)';
      return records
          .take(30)
          .map((r) => '  - ${_recordTitle(r)}')
          .join('\n');
    }

    final text = StringBuffer()
      ..writeln('Обнаружена новая версия перечня «нежелательных организаций».')
      ..writeln()
      ..writeln('Дата актуальности данных: '
          '${formatRuDate(version.actualityDate)} '
          '${_time(version.actualityDate)}')
      ..writeln('Скачано: ${MoscowTime.format(version.downloadedAt)}')
      ..writeln()
      ..writeln('Итоги автоматического разбора:')
      ..writeln('  всего записей: ${counters.total}')
      ..writeln('  новых: ${counters.added}')
      ..writeln('  исключённых: ${counters.excluded}')
      ..writeln('  изменённых: ${counters.changed}')
      ..writeln('  требуют проверки: ${counters.review}')
      ..writeln('  с ручными правками: ${counters.edited}')
      ..writeln()
      ..writeln('Новые организации:')
      ..writeln(namesOf(addedRecords))
      ..writeln()
      ..writeln('Исключённые организации:')
      ..writeln(namesOf(excludedRecords));

    if (warnings.isNotEmpty) {
      text
        ..writeln()
        ..writeln('Предупреждения разбора:')
        ..writeln(warnings.take(20).map((w) => '  - $w').join('\n'));
    }

    text
      ..writeln()
      ..writeln('Проверить и подтвердить: ${versionUrl(version.id)}')
      ..writeln('Если версия не будет подтверждена до '
          '${MoscowTime.format(autoPublishDeadline)}, файл будет опубликован '
          'автоматически в том виде, как разобрался.');

    final html = _html(
      title: 'Новая версия перечня 272-ФЗ',
      body: '''
<p>Обнаружена новая версия перечня «нежелательных организаций».</p>
<table>
  <tr><td>Дата актуальности данных</td><td><b>${formatRuDate(version.actualityDate)} ${_time(version.actualityDate)}</b></td></tr>
  <tr><td>Скачано</td><td>${MoscowTime.format(version.downloadedAt)}</td></tr>
  <tr><td>Всего записей</td><td>${counters.total}</td></tr>
  <tr><td>Новых</td><td>${counters.added}</td></tr>
  <tr><td>Исключённых</td><td>${counters.excluded}</td></tr>
  <tr><td>Изменённых</td><td>${counters.changed}</td></tr>
  <tr><td>Требуют проверки</td><td>${counters.review}</td></tr>
  <tr><td>С ручными правками</td><td>${counters.edited}</td></tr>
</table>
<h3>Новые организации</h3>
<ul>${_htmlList(addedRecords)}</ul>
<h3>Исключённые организации</h3>
<ul>${_htmlList(excludedRecords)}</ul>
<p><a href="${versionUrl(version.id)}">Проверить и подтвердить версию</a></p>
<p>Если версия не будет подтверждена до
<b>${MoscowTime.format(autoPublishDeadline)}</b>, файл будет опубликован
автоматически в том виде, как разобрался.</p>
''',
    );

    await _send(
      EmailMessage(subject: subject, text: text.toString(), html: html),
      versionId: version.id,
      kind: 'new_version',
    );
  }

  /// 2. Ошибка: не скачалось или структура файла не распознана.
  Future<void> failure({
    required String reason,
    required String details,
    int? versionId,
  }) async {
    final subject = 'Перечень 272-ФЗ: ОШИБКА — $reason';
    final text = '''
При обработке перечня произошла ошибка.

Причина: $reason
Подробности: $details
Время: ${MoscowTime.format(MoscowTime.now())}

Журнал событий: ${config.uiBaseUrl}/#/events
''';
    await _send(
      EmailMessage(
        subject: subject,
        text: text,
        html: _html(
          title: 'Ошибка обработки перечня 272-ФЗ',
          body: '<p><b>Причина:</b> ${_escape(reason)}</p>'
              '<p><b>Подробности:</b> ${_escape(details)}</p>'
              '<p><a href="${config.uiBaseUrl}/#/events">Журнал событий</a></p>',
        ),
      ),
      versionId: versionId,
      kind: 'error',
    );
  }

  /// 3. Опционально: проверка выполнена, новой версии нет.
  Future<void> noChanges({required DateTime checkedAt, DateTime? lastActuality}) async {
    if (!config.notifyOnNoChanges) return;
    final text = 'Проверка выполнена ${MoscowTime.format(checkedAt)}. '
        'Новой версии перечня нет'
        '${lastActuality == null ? '' : ' (актуальная версия от '
            '${formatRuDate(lastActuality)})'}.';
    await _send(
      EmailMessage(
        subject: 'Перечень 272-ФЗ: новой версии нет',
        text: text,
        html: _html(title: 'Проверка перечня 272-ФЗ', body: '<p>$text</p>'),
      ),
      kind: 'no_changes',
    );
  }

  /// 4. Авто-публикация без подтверждения.
  Future<void> autoPublished({
    required PerechenVersion version,
    required String fileName,
  }) async {
    final text = '''
Версия перечня от ${formatRuDate(version.actualityDate)} не была подтверждена
до контрольного времени, поэтому опубликована автоматически в том виде,
как разобралась.

Файл: $fileName
Записей: ${version.counters.total}
Требовали проверки: ${version.counters.review}

Карточка версии: ${versionUrl(version.id, filter: 'review')}
''';
    await _send(
      EmailMessage(
        subject: 'Перечень 272-ФЗ: выполнена авто-публикация версии от '
            '${formatRuDate(version.actualityDate)}',
        text: text,
        html: _html(
          title: 'Авто-публикация версии перечня',
          body: '<p>Версия от <b>${formatRuDate(version.actualityDate)}</b> '
              'не была подтверждена до контрольного времени и опубликована '
              'автоматически.</p>'
              '<p>Файл: <code>${_escape(fileName)}</code><br>'
              'Записей: ${version.counters.total}<br>'
              'Требовали проверки: ${version.counters.review}</p>'
              '<p><a href="${versionUrl(version.id, filter: 'review')}">'
              'Открыть версию</a></p>',
        ),
      ),
      versionId: version.id,
      kind: 'auto_published',
    );
  }

  /// Содержимое перечня изменилось без смены даты актуальности (FR-2).
  ///
  /// Сравниваются хэши данных (строки первоисточника), а не байты файла:
  /// реестр собирает xlsx на каждый запрос, и байтовый хэш меняется всегда.
  Future<void> contentChangedWithoutDate({
    required DateTime actualityDate,
    required String previousDataSha,
    required String currentDataSha,
  }) async {
    final text = '''
Данные перечня изменились, но дата актуальности осталась прежней
(${formatRuDate(actualityDate)}). Версия помечена как требующая проверки.

SHA-256 данных предыдущей версии: $previousDataSha
SHA-256 данных нового файла:      $currentDataSha
''';
    await _send(
      EmailMessage(
        subject: 'Перечень 272-ФЗ: файл изменился без смены даты актуальности',
        text: text,
        html: _html(
          title: 'Файл изменился без смены даты актуальности',
          body: '<p>Дата актуальности: '
              '<b>${formatRuDate(actualityDate)}</b></p>'
              '<p>SHA-256 данных предыдущей версии: '
              '<code>$previousDataSha</code><br>'
              'SHA-256 данных нового файла: <code>$currentDataSha</code></p>',
        ),
      ),
      kind: 'content_changed_same_date',
    );
  }

  /// Эскалация: сайт недоступен несколько суток подряд (Р-5).
  Future<void> unavailableEscalation({
    required int days,
    required String lastError,
  }) async {
    final text = 'Сайт Минюста недоступен $days сут. подряд. '
        'Последняя ошибка: $lastError';
    await _send(
      EmailMessage(
        subject: 'Перечень 272-ФЗ: сайт недоступен $days сут.',
        text: text,
        html: _html(
          title: 'Сайт Минюста недоступен',
          body: '<p>${_escape(text)}</p>',
        ),
      ),
      kind: 'unavailable_escalation',
    );
  }

  Future<void> _send(
    EmailMessage message, {
    int? versionId,
    required String kind,
  }) async {
    if (config.notifyEmails.isEmpty) {
      _logger.warning('список получателей пуст, письмо не отправлено', {
        'kind': kind,
        'subject': message.subject,
      });
      return;
    }
    try {
      await sender.send(message, config.notifyEmails);
      db.addEvent(
        EventType.emailSent,
        payload: {
          'kind': kind,
          'subject': message.subject,
          'to': config.notifyEmails,
        },
        versionId: versionId,
      );
      _logger.info('письмо отправлено', {'kind': kind});
    } catch (error) {
      db.addEvent(
        EventType.emailFailed,
        payload: {
          'kind': kind,
          'subject': message.subject,
          'error': '$error',
        },
        versionId: versionId,
      );
      _logger.error('не удалось отправить письмо', {
        'kind': kind,
        'error': '$error',
      });
    }
  }

  static String _recordTitle(ParsedRecord record) {
    final rus = record.value(RecordField.nameRus);
    final add = record.value(RecordField.nameAdd);
    final country = record.value(RecordField.country);
    final name = [rus, add].where((v) => v.isNotEmpty).join(' / ');
    final title = name.isEmpty ? record.sourceRow.rawName : name;
    return country.isEmpty ? title : '$title ($country)';
  }

  static String _htmlList(List<ParsedRecord> records) {
    if (records.isEmpty) return '<li>(нет)</li>';
    return records
        .take(30)
        .map((r) => '<li>${_escape(_recordTitle(r))}</li>')
        .join();
  }

  static String _time(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _html({required String title, required String body}) => '''
<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><title>$title</title>
<style>
body{font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;font-size:14px;color:#1f2933}
table{border-collapse:collapse;margin:12px 0}
td{border:1px solid #d7dce2;padding:4px 10px}
h3{margin:18px 0 6px}
ul{margin:6px 0 0 18px;padding:0}
code{background:#f2f4f7;padding:1px 4px;border-radius:3px}
</style></head>
<body><h2>$title</h2>$body</body></html>
''';
}
