/// Открытие ссылки (скачивание целевого CSV) с подстановкой реализации:
/// в вебе — через браузер, в тестах на VM — заглушка.
library;

export 'link_opener_stub.dart'
    if (dart.library.html) 'link_opener_web.dart';
