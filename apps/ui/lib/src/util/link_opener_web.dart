/// Веб-реализация: открывает ссылку в новой вкладке.
library;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

final openedLinks = <String>[];

void openLink(String url) {
  openedLinks.add(url);
  html.window.open(url, '_blank');
}
