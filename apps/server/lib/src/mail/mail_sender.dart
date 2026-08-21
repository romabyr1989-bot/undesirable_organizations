/// Отправка почты (FR-8).
library;

import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

import '../config/app_config.dart';

class EmailMessage {
  const EmailMessage({
    required this.subject,
    required this.text,
    required this.html,
  });

  final String subject;
  final String text;
  final String html;
}

abstract class MailSender {
  Future<void> send(EmailMessage message, List<String> recipients);
}

/// Отправка через SMTP из конфигурации.
class SmtpMailSender implements MailSender {
  SmtpMailSender(this.config);

  final AppConfig config;

  @override
  Future<void> send(EmailMessage message, List<String> recipients) async {
    if (!config.smtp.isConfigured) {
      throw StateError('SMTP не настроен: задайте SMTP_HOST');
    }
    if (recipients.isEmpty) return;
    final server = SmtpServer(
      config.smtp.host,
      port: config.smtp.port,
      username: config.smtp.user.isEmpty ? null : config.smtp.user,
      password: config.smtp.password.isEmpty ? null : config.smtp.password,
      ssl: config.smtp.useSsl,
      allowInsecure: config.smtp.allowInsecure,
      ignoreBadCertificate: config.smtp.allowInsecure,
    );
    final mail = mailer.Message()
      ..from = mailer.Address(config.smtp.from, 'Перечень 272-ФЗ')
      ..recipients.addAll(recipients)
      ..subject = message.subject
      ..text = message.text
      ..html = message.html;
    await mailer.send(mail, server);
  }
}

/// Отправитель, который только запоминает письма (тесты и сухой прогон).
class MemoryMailSender implements MailSender {
  final List<({EmailMessage message, List<String> recipients})> sent = [];

  @override
  Future<void> send(EmailMessage message, List<String> recipients) async {
    sent.add((message: message, recipients: recipients));
  }

  EmailMessage? get last => sent.isEmpty ? null : sent.last.message;

  void clear() => sent.clear();
}
