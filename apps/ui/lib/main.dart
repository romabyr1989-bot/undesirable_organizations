/// Точка входа Flutter Web UI.
///
/// UI раздаётся тем же сервером, что и API, поэтому базовый адрес берётся из
/// текущего URL. Для запуска на отдельном порту при разработке:
///   flutter run -d chrome --dart-define=API_BASE=http://localhost:8080/
library;

import 'package:flutter/material.dart';

import 'src/api/api_client.dart';
import 'src/app.dart';

void main() {
  const apiBase = String.fromEnvironment('API_BASE');
  runApp(PerechenApp(
    api: ApiClient(baseUri: apiBase.isEmpty ? null : Uri.parse(apiBase)),
  ));
}
