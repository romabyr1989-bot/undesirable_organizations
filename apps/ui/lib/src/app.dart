/// Приложение: тема, локаль, маршрутизация (п. 10 ТЗ).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/api_client.dart';
import 'screens/events_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/version_screen.dart';
import 'screens/versions_screen.dart';

/// Насколько крупнее показывать текст относительно базовых размеров.
/// Умножается на системный масштаб, поэтому настройка ОС продолжает работать.
const uiTextScale = 1.5;

class PerechenApp extends StatelessWidget {
  const PerechenApp({super.key, required this.api});

  final PerechenApi api;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Перечень 272-ФЗ',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1857B6)),
          visualDensity: VisualDensity.compact,
        ),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(media.textScaler.scale(uiTextScale)),
            ),
            child: child!,
          );
        },
        onGenerateRoute: (settings) => generateRoute(settings, api),
      );

  /// Разбор маршрутов вида `/versions/12?filter=new` (hash-навигация).
  static Route<dynamic> generateRoute(
    RouteSettings settings,
    PerechenApi api,
  ) {
    final uri = Uri.parse(settings.name ?? '/');
    final segments = uri.pathSegments;

    if (segments.length == 2 && segments.first == 'versions') {
      final id = int.tryParse(segments[1]);
      if (id != null) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => VersionScreen(
            api: api,
            versionId: id,
            initialFilter: uri.queryParameters['filter'] ?? 'all',
          ),
        );
      }
    }
    if (segments.isNotEmpty && segments.first == 'settings') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => SettingsScreen(api: api),
      );
    }
    if (segments.isNotEmpty && segments.first == 'events') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => EventsScreen(api: api),
      );
    }
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => VersionsScreen(api: api),
    );
  }
}
