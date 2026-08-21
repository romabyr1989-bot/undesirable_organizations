/// Заглушка для не-веб-платформ (используется в тестах).
library;

/// Ссылки, «открытые» во время теста.
final openedLinks = <String>[];

void openLink(String url) => openedLinks.add(url);
