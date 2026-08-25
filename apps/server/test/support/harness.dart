/// Тестовая обвязка: конфигурация во временных папках, БД в памяти,
/// подменённые HTTP-клиент и отправитель почты.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perechen_core/perechen_core.dart';
import 'package:perechen_server/src/app.dart';
import 'package:perechen_server/src/config/app_config.dart';
import 'package:perechen_server/src/db/database.dart';
import 'package:perechen_server/src/mail/mail_sender.dart';
import 'package:perechen_server/src/util/logging.dart';

/// Путь к каталогу эталонных файлов.
const referenceDir = '../../reference';

Uint8List referenceXlsx() => File('$referenceDir/export.xlsx').readAsBytesSync();

/// Заголовки колонок первоисточника.
const sourceHeaders = <String>[
  '№ п/п',
  'Дата распоряжения Минюста России о включении в перечень',
  'Номер распоряжения Минюста России о включении в перечень',
  'Дата принятия решения Генеральной прокуратурой Российской Федерации '
      'о признании деятельности организации нежелательной',
  'Наименование организации',
  'Дата обнародования информации',
  'Дата распоряжения Минюста России об исключении из перечня',
  'Номер распоряжения Минюста России об исключении из перечня',
  'Дата принятия решения Генеральной прокуратурой Российской Федерации '
      'об отмене решения',
  'Статус',
];

/// Строка первоисточника для тестового файла.
List<String> row({
  required String ordinal,
  required String inclusionNumber,
  String inclusionDate = '29.07.2015',
  String gpDecisionDate = '28.07.2015',
  required String rawName,
  String exclusionDate = '',
  String exclusionNumber = '',
  String gpCancelDate = '',
  String status = 'Включена',
}) =>
    [
      ordinal,
      inclusionDate,
      inclusionNumber,
      gpDecisionDate,
      rawName,
      '',
      exclusionDate,
      exclusionNumber,
      gpCancelDate,
      status,
    ];

/// Собирает xlsx-файл первоисточника с заданной датой актуальности.
Uint8List buildSourceXlsx({
  required DateTime actualityDate,
  required List<List<String>> rows,
  List<String> headers = sourceHeaders,
  String title = 'Реестр иностранных и международных организаций',
  DateTime? generatedAt,
}) {
  String cell(String reference, String value) {
    final escaped = value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<c r="$reference" t="inlineStr"><is><t>$escaped</t></is></c>';
  }

  String columnName(int index) {
    var value = index;
    var name = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      name = String.fromCharCode(65 + remainder) + name;
      value = (value - 1) ~/ 26;
    }
    return name;
  }

  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main"><sheetData>')
    ..write('<row r="1">${cell('A1', title)}</row>')
    ..write('<row r="2">${cell('A2', _formatDateTime(actualityDate))}</row>')
    ..write('<row r="3">');
  for (var index = 0; index < headers.length; index++) {
    sheet.write(cell('${columnName(index + 1)}3', headers[index]));
  }
  sheet.write('</row>');

  var rowIndex = 3;
  for (final dataRow in rows) {
    rowIndex++;
    sheet.write('<row r="$rowIndex">');
    for (var index = 0; index < dataRow.length; index++) {
      sheet.write(cell('${columnName(index + 1)}$rowIndex', dataRow[index]));
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');

  final archive = Archive();
  void addFile(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addFile(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.'
        'openxmlformats.org/package/2006/content-types"/>',
  );
  addFile(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.'
        'openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.'
        'openxmlformats.org/officeDocument/2006/relationships">'
        '<workbookPr date1904="false"/><sheets>'
        '<sheet name="Лист 1" r:id="rId1" sheetId="1"/></sheets></workbook>',
  );
  addFile(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://'
        'schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Target="worksheets/sheet1.xml" Type="http://'
        'schemas.openxmlformats.org/officeDocument/2006/relationships/'
        'worksheet"/></Relationships>',
  );
  addFile(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.'
        'openxmlformats.org/spreadsheetml/2006/main"><cellXfs count="1">'
        '<xf numFmtId="0"/></cellXfs></styleSheet>',
  );
  addFile('xl/worksheets/sheet1.xml', sheet.toString());

  // Реестр Минюста собирает xlsx на каждый запрос и записывает в него время
  // генерации: два скачивания подряд дают разные байты при одних и тех же
  // данных. [generatedAt] воспроизводит это в тестах.
  if (generatedAt != null) {
    addFile(
      'docProps/core.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
          '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/'
          'package/2006/metadata/core-properties" xmlns:dcterms="http://'
          'purl.org/dc/terms/"><dcterms:created>'
          '${generatedAt.toUtc().toIso8601String()}'
          '</dcterms:created></cp:coreProperties>',
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

String _formatDateTime(DateTime value) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

/// Обвязка теста: временные каталоги, приложение и подменённые зависимости.
class TestHarness {
  TestHarness._({
    required this.app,
    required this.mail,
    required this.tempDir,
    required this.responses,
    required this.requestedUrls,
  });

  final PerechenApp app;
  final MemoryMailSender mail;
  final Directory tempDir;

  /// Очередь ответов «сайта»: каждый вызов забирает следующий (последний
  /// повторяется).
  final List<Object> responses;

  /// Адреса, по которым сервис ходил на «сайт».
  final List<String> requestedUrls;

  AppDatabase get db => app.db;

  AppConfig get config => app.config;

  /// Действующая папка CDI (правка из UI перекрывает конфигурацию).
  String get cdiDir => app.settings.cdiDropDir;

  /// Создаёт обвязку. В [responses] кладут `Uint8List` (тело файла) либо
  /// `Exception`/код ошибки (`int`) для имитации сбоя.
  static TestHarness create({
    List<Object>? responses,
    bool notifyOnNoChanges = false,
    List<String> notifyEmails = const ['otvetstvennyi@corp.example'],
    DateTime Function()? clock,
  }) {
    final tempDir = Directory.systemTemp.createTempSync('perechen_test_');
    final queue = <Object>[...?responses];
    final requestedUrls = <String>[];

    final client = MockClient((request) async {
      requestedUrls.add(request.url.toString());
      if (queue.isEmpty) {
        return http.Response('not found', 404);
      }
      final next = queue.length == 1 ? queue.first : queue.removeAt(0);
      if (next is Exception) throw next;
      if (next is int) return http.Response('error', next);
      if (next is String) {
        return http.Response(next, 200, headers: {
          'content-type': 'text/html; charset=utf-8',
        });
      }
      return http.Response.bytes(next as Uint8List, 200, headers: {
        'content-type':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
    });

    final mail = MemoryMailSender();
    final config = AppConfig.load(environment: {
      'DATA_DIR': '${tempDir.path}/data',
      'CDI_DROP_DIR': '${tempDir.path}/cdi',
      'MINJUST_EXPORT_URL': 'https://minjust.example/export.xlsx',
      'COUNTRIES_FILE': '../../packages/core/assets/countries_ru.txt',
      'NOTIFY_EMAILS': notifyEmails.join(','),
      'NOTIFY_ON_NO_CHANGES': '$notifyOnNoChanges',
      'RETRY_DELAYS_MIN': '0,0,0',
      'SCHEDULER_ENABLED': 'false',
      'UI_BASE_URL': 'http://ui.example',
      'BASIC_AUTH_USER': 'admin',
      'BASIC_AUTH_PASS': 'secret',
      'PORT': '0',
      'UI_DIR': '${tempDir.path}/web',
    });

    final app = PerechenApp.create(
      config,
      mailSender: mail,
      httpClient: client,
      logger: AppLogger(minLevel: LogLevel.error),
      database: AppDatabase.memory(),
      clock: clock,
      sleep: (_) async {},
    );

    return TestHarness._(
      app: app,
      mail: mail,
      tempDir: tempDir,
      responses: queue,
      requestedUrls: requestedUrls,
    );
  }

  /// Подменяет очередь ответов «сайта».
  void serve(List<Object> newResponses) {
    responses
      ..clear()
      ..addAll(newResponses);
  }

  List<String> get cdiFiles {
    final directory = Directory(cdiDir);
    if (!directory.existsSync()) return const [];
    return directory
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();
  }

  String cdiFileContent(String name) {
    const encoder = Cp1251Encoder();
    return encoder.decode(File('$cdiDir/$name').readAsBytesSync());
  }

  Future<void> dispose() async {
    await app.stop();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}
