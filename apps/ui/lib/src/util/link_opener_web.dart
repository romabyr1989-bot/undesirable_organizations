/// Веб-реализация: скачивает файл по ссылке.
///
/// Раньше здесь был `window.open`: Flutter обрабатывает нажатие асинхронно,
/// браузер уже не считает открытие вкладки действием пользователя и глушит
/// его как всплывающее окно — кнопка «Скачать» молча ничего не делала.
/// Ссылка-якорь с атрибутом `download` в блокировщик не упирается, а имя
/// файла браузер берёт из заголовка `Content-Disposition`.
library;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

final openedLinks = <String>[];

void openLink(String url) {
  openedLinks.add(url);
  final anchor = html.AnchorElement(href: url)
    ..download = ''
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
}
