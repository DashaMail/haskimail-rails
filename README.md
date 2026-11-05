# haskimail-rails

Ruby on Rails SDK для [Haskimail](https://haskimail.ru), сервиса транзакционных писем.

* Метод доставки ActionMailer `:haskimail` с тегами, метаданными, каналами, трекингом, вложениями и inline-картинками.
* Полное покрытие HTTP API: письма, шаблоны, сообщения, возвраты, каналы, статистика, вебхуки, правила для входящих, стоп-листы, серверы и домены.
* Безопасные ретраи с экспоненциальной задержкой и jitter: письмо **никогда** не отправится дважды.
* Приём вебхуков: Rack-эндпоинт с Basic auth и проверкой подписи в постоянное время, типизированные события.
* Из зависимостей только ActionMailer и `base64`. Keep-alive соединения, безопасные для потоков и `fork`. TLS 1.2+.
* Токены не попадают в логи, `inspect`, `to_json` и трекеры ошибок.

Требования: Ruby 3.1+, Rails / ActionMailer 6.1+.

## Установка

```ruby
# Gemfile
gem "haskimail-rails"
```

```sh
bundle install
bin/rails generate haskimail:install   # создаст config/initializers/haskimail.rb
bin/rails credentials:edit
```

```yaml
haskimail:
  server_token: "серверный API-ключ"
  account_token: "API-ключ аккаунта"   # нужен только для серверов, доменов и переноса шаблонов
  webhook_key: "ключ подписи вебхуков"
  webhook_password: "пароль для Basic auth вебхуков"
```

## ActionMailer

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :haskimail
# Токен берётся из Haskimail.config. Можно задать явно:
# config.action_mailer.haskimail_settings = { api_token: Rails.application.credentials.dig(:haskimail, :server_token) }
```

```ruby
class OrderMailer < ApplicationMailer
  default from: "Магазин <shop@example.com>"

  def created(order)
    haskimail tag: "orders",
              metadata: { order_id: order.id.to_s },
              message_stream: "2081",
              track_opens: true,
              track_links: true

    attachments["invoice.pdf"] = order.invoice_pdf
    attachments.inline["logo.png"] = File.binread("app/assets/images/logo.png")
    # во вьюхе: image_tag attachments["logo.png"].url

    mail to: order.email, subject: "Заказ №#{order.number} оформлен"
  end

  # Шаблон, который хранится в Haskimail
  def welcome(user)
    haskimail_template "welcome", model: { "{{name}}" => user.name }, to: user.email
  end
end
```

`track_opens` и `track_links` для письма принимают `true`/`false`; без них действует настройка сервера. На уровне сервера `TrackLinks` задаётся строкой (`None`, `HtmlAndText`, `HtmlOnly`, `TextOnly`) через `account.servers.update(id, track_links: "None")`; `true` и `false` там тоже принимаются.

После отправки ответ API доступен в `message.haskimail.response`, ID письма в `message.haskimail.message_id`.

Поддерживаются и SMTP-заголовки Haskimail (`X-HM-Tag`, `X-HM-Metadata`, `X-HM-TrackOpens`, `X-HM-No-Track-Opens`, `X-HM-No-Track-Click`), поэтому один и тот же мейлер работает и через SMTP, и через API. Явные настройки `haskimail(...)` важнее заголовков. Остальные заголовки, включая `X-HM-Domain` и `X-HM-MessageID`, передаются в Haskimail как есть.

В development и test удобен тестовый токен: API проверяет запрос, но ничего не отправляет.

```ruby
Haskimail.config.server_token = Haskimail::TEST_TOKEN if Rails.env.development? || Rails.env.test?
```

## HTTP API

```ruby
client = Haskimail::ServerClient.new            # токен из Haskimail.config / ENV["HASKIMAIL_SERVER_TOKEN"]

client.deliver(
  from: "Магазин <shop@example.com>",
  to: "ivan@example.com",
  subject: "Ваш заказ №1042 оформлен",
  html_body: "<p>Здравствуйте!</p>",
  text_body: "Здравствуйте!",
  tag: "orders",
  metadata: { order_id: "1042" },
  headers: { "X-Order-Id" => "1042" },
  attachments: [Haskimail::Attachment.from_file("invoice.pdf")],
  message_stream: "2081"
)
# => { to: "ivan@example.com", submitted_at: "2026-10-07 14:30:12", message_id: "6f1c…", error_code: 0, message: "OK" }
```

Ключи можно передавать в Ruby-стиле (`html_body:` или `"html_body"`, подходят и `params`) или ровно как в API (`"HtmlBody"`). Если одно поле задано дважды, SDK выдаст ошибку, а не выберет одно молча. Получателей можно передать строкой через запятую или массивом. Ответы приходят как Hash с ключами-символами в snake_case. Пользовательские данные (`Metadata`, `TemplateModel`, `TestRenderModel`) передаются как есть, без преобразования ключей.

Вложения проще всего передавать через `Haskimail::Attachment`: он сам кодирует содержимое в Base64. В Hash-вложениях `content` уже должен быть в Base64. Для картинки внутри письма укажите `content_id: "logo.png"` и сошлитесь на неё в HTML как `<img src="cid:logo.png">`. Haskimail использует `ContentID` как Content-ID без изменений, поэтому SDK убирает префикс `cid:` и угловые скобки.

### Пакетная отправка

```ruby
results = client.deliver_batch(messages)              # до 500 писем
failed  = results.reject { |r| r[:error_code].zero? } # API отвечает 200, даже если часть писем отклонена

client.deliver_with_template(template_alias: "order-created",
                             template_model: { "{{name}}" => "Иван" },
                             from: "shop@example.com", to: "ivan@example.com")
client.deliver_batch_with_templates([...])
```

### Ресурсы сервера (`ServerClient`)

| Ресурс | Методы |
|---|---|
| `emails` | `deliver`, `deliver_batch`, `deliver_with_template`, `deliver_batch_with_templates` |
| `templates` | `get`, `list`, `each`, `create`, `update`, `patch`, `delete`, `validate` |
| `messages` | `outbound`, `each_outbound`, `outbound_details`, `opens`, `each_open`, `opens_for`, `clicks`, `each_click`, `clicks_for`, `inbound`, `each_inbound`, `inbound_details`, `bypass_inbound`, `retry_inbound` |
| `bounces` | `delivery_stats`, `list`, `each` |
| `message_streams` | `list`, `get`, `create`, `update`, `archive`, `unarchive` |
| `stats` | `overview`, `sends`, `bounces`, `spam_complaints`, `opens`, `clicks`, `open_platforms`, `click_platforms`, `email_clients`, `browser_families` |
| `webhooks` | `list`, `get`, `create`, `update`, `delete` |
| `inbound_rules` | `list`, `each`, `create`, `delete` |
| `suppressions` | `list` (`dump`), `create` (`suppress`), `delete` (`unsuppress`) |

### Ресурсы аккаунта (`AccountClient`)

| Ресурс | Методы |
|---|---|
| `servers` | `get`, `list`, `each`, `create`, `update`, `delete` |
| `domains` | `list`, `each`, `get`, `create`, `delete`, `verify_dkim`, `verify_spf` |
| `templates` | `list`, `each` (шаблоны всех серверов), `validate`, `create`, `push` (перенос шаблонов между серверами) |

```ruby
account = Haskimail::AccountClient.new
account.templates.push(source_server_id: 1, destination_server_id: 2, perform_changes: false) # сначала предпросмотр
```

### Фильтры, даты и пагинация

```ruby
client.messages.outbound(tag: "orders", recipient: "ivan@example.com",
                         from_date: 1.week.ago, to_date: Date.current, count: 100)

# Ленивый обход всех страниц (с учётом лимита API count + offset ≤ 10 000)
client.bounces.each(type: "HardBounce").each { |bounce| ... }
client.messages.each_outbound(tag: "orders").first(1_000)
```

`Date`, `Time` и `ActiveSupport::TimeWithZone` переводятся в московское время, как требует API. Неизвестные фильтры, ошибки в датах и нарушения лимитов API ловятся ещё до запроса с понятным `ArgumentError`.

### Шаблоны

`templates.update` перезаписывает шаблон целиком (так работает API), поэтому все четыре поля обязательны. Чтобы поменять одно поле, есть `templates.patch(id, subject: "…")`: он читает шаблон и сохраняет остальные поля.

## Ошибки

```
Haskimail::Error
├── ConfigurationError
├── ConnectionError
│   └── TimeoutError
├── InvalidResponseError
├── WebhookVerificationError
└── ApiError                    # #status, #error_code, #body, #headers, #code?
    ├── UnauthorizedError       # 401
    ├── ForbiddenError          # 403, IP не в списке разрешённых
    ├── NotFoundError           # 404
    ├── PayloadTooLargeError    # 413, пакет больше 50 МБ
    ├── UnprocessableEntityError# 422
    ├── RateLimitError          # 429
    └── ServerError             # 5xx
        ├── InternalServerError       # 500
        └── ServiceUnavailableError   # 503
```

```ruby
begin
  client.deliver_with_template(...)
rescue Haskimail::UnprocessableEntityError => e
  raise unless e.code?(Haskimail::ErrorCodes::TEMPLATE_NOT_FOUND)
end
```

## Ретраи и надёжность

| Ситуация | GET, PUT | POST (отправка), DELETE |
|---|---|---|
| Соединение не открылось (DNS, refused, open timeout) | повтор | повтор: запрос точно не ушёл |
| Таймаут чтения, обрыв, 5xx, 429 | повтор | **без повтора**: запрос мог быть обработан |

По умолчанию 2 повтора, экспоненциальная задержка с jitter, `Retry-After` учитывается (не дольше `retry_max_delay`). `PUT /messages/inbound/{id}/retry|bypass` не повторяются: повтор отправил бы письмо на ваш вебхук ещё раз.

```ruby
Haskimail.configure do |c|
  c.open_timeout = 5
  c.read_timeout = 30
  c.max_retries = 2
  c.default_message_stream = "2081"
  c.logger = Rails.logger          # логируются только метод, путь, статус и время
end
```

Каждый запрос публикуется в `ActiveSupport::Notifications` как `request.haskimail` с полями `method`, `path`, `attempt` и `status`, без токенов и персональных данных.

Keep-alive соединения хранятся отдельно для каждого потока и файбера и не переиспользуются после `fork` (Puma, Unicorn). Для серверов с файбером на запрос (Falcon) поставьте `persistent_connections = false`.

## Вебхуки

```ruby
# config/routes.rb
mount Haskimail::Webhooks::Endpoint.new(
  username: "haskimail",
  password: Rails.application.credentials.dig(:haskimail, :webhook_password),
  signature_key: Rails.application.credentials.dig(:haskimail, :webhook_key)
) { |event| HaskimailWebhook.create!(payload: event.to_h).enqueue_processing }, at: "/haskimail/webhooks"
```

Входящее письмо с вложениями может весить около 14 МБ, поэтому лучше сначала сохранить его в базу или хранилище, а в очередь передать только ID записи.

В Haskimail укажите URL `https://haskimail:ПАРОЛЬ@example.com/haskimail/webhooks`.

```ruby
class HaskimailWebhookJob < ApplicationJob
  def perform(webhook_id)
    event = Haskimail::Webhooks.parse(HaskimailWebhook.find(webhook_id).payload)
    case event
    when Haskimail::Webhooks::InboundMessage
      Ticket.reply!(event.mailbox_hash, event.stripped_text_reply, event.attachments)
    else
      return if WebhookEvent.exists?(key: event.idempotency_key) # Haskimail может прислать событие повторно
      User.find_by(email: event.recipient)&.disable_email! if event.hard_bounce? || event.complained?
    end
  end
end
```

Безопасность эндпоинта:

* Basic auth обязателен: без него эндпоинт не запустится. Принимать события только по подписи можно с явным `allow_signature_only: true`, входящие письма тогда отклоняются. Для локальной разработки есть `allow_unauthenticated: true`. Заданный `signature_key` проверяется всегда.
* Basic auth проверяется до чтения тела запроса. Сравнение идёт в постоянное время.
* Событие с ключом подписи принимается, только если поле `secret` совпадает с `MD5(recipient + message_id + ключ)`.
* Входящие письма Haskimail не подписывает, поэтому они принимаются только при включённом Basic auth.
* Подпись Haskimail покрывает только `recipient` и `message_id`: перехваченный `secret` можно переиспользовать с другим типом события. Поэтому рекомендуем Basic auth вместе с подписью и HTTPS.
* Ответы: 200 — обработано, 401 — неверный логин или пароль, 403 — неверная подпись, 500 — упал ваш обработчик. Haskimail повторяет 5xx для всех вебхуков. Для входящих писем он повторяет и другие ответы, кроме 2xx и 403.

Все события также публикуются в `ActiveSupport::Notifications` как `webhook.haskimail` с полями `{ type:, event: }`.

Методы событий: `type` (`:delivered`, `:bounced`, `:complained`, `:opened`, `:clicked`, `:subscription_change`), предикаты (`bounced?`, `hard_bounce?`, …), `recipient`, `message_id`, `tag`, `metadata` (уже распарсенный Hash), `occurred_at` (UTC), `bounce_code`, `bounce_description`, `clicked_url`, `suppress_sending?`, `idempotency_key`.

Если обрабатываете вебхуки в своём контроллере, используйте `Haskimail::Webhooks.parse(request.raw_post)`, `Haskimail::Webhooks.verify_signature!(event, key:)` и `Haskimail::Webhooks.valid_basic_auth?(request.authorization, username:, password:)`.

## Разработка

```sh
bundle install
bundle exec rake        # RSpec (покрытие ≥ 98% строк) + RuboCop
```

## Лицензия

MIT
