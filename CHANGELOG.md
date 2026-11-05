# Changelog

## Не выпущено

- `Haskimail::AccountClient#servers.issue_token(server_id, name:)` — выпуск дополнительного серверного API-ключа (`POST /servers/{id}/tokens/new`).
- Из `Servers::UPDATABLE` убрано `enable_smtp_api_error_hooks` — поле отсутствует в API и игнорировалось.

## 1.0.0 — 2026-10-31

Первый релиз.

- ActionMailer delivery method `:haskimail` (теги, метаданные, каналы, трекинг, вложения, inline-картинки, шаблоны Haskimail, SMTP-заголовки `X-HM-*`).
- `Haskimail::ServerClient`: письма, пакеты, шаблоны, сообщения, открытия, клики, входящие, возвраты, каналы, статистика, вебхуки, правила для входящих, стоп-листы.
- `Haskimail::AccountClient`: серверы, домены, перенос шаблонов.
- Ретраи без дублей писем, keep-alive соединения, безопасные для потоков и `fork`, инструментирование через ActiveSupport::Notifications.
- `Haskimail::Webhooks`: разбор событий и входящих писем, проверка подписи и Basic auth, Rack-эндпоинт.
- Генератор `rails g haskimail:install`.
- Поддержка Ruby 3.1+ и Rails 6.1–8.x.
