# Выпуск версии

Гем публикуется на [RubyGems](https://rubygems.org/gems/haskimail-rails) из GitHub Actions
(`.github/workflows/release.yml`) через
[trusted publishing](https://guides.rubygems.org/trusted-publishing/): API-ключ RubyGems нигде не хранится.

## Один раз перед первым выпуском

1. На rubygems.org в аккаунте, который будет владельцем гема, добавьте pending trusted publisher
   для гема `haskimail-rails`: репозиторий `DashaMail/haskimail-rails`, workflow `release.yml`,
   окружение `release`.
2. В настройках репозитория на GitHub создайте окружение `release` (Settings → Environments):
   - Deployment branches and tags → только теги `v*`;
   - Required reviewers — тот, кто подтверждает каждую публикацию.

## Каждый выпуск

1. Обновите версию в `lib/haskimail/version.rb` и перенесите записи из «Не выпущено» в новый
   раздел `CHANGELOG.md`.
2. Убедитесь, что всё зелёное локально:
   ```bash
   bundle exec rspec
   gem build --strict haskimail-rails.gemspec
   ```
3. Закоммитьте в `main`, дождитесь зелёного CI и поставьте тег:
   ```bash
   git tag -a v1.0.0 -m "Haskimail Rails v1.0.0"
   git push origin v1.0.0
   ```
4. Workflow `release.yml` проверит, что тег стоит на коммите из `main` и совпадает с версией гема,
   прогонит тесты в отдельном задании без прав на публикацию и опубликует гем.

## Ручной выпуск (запасной вариант)

Если GitHub Actions недоступен. Тег после ручной публикации запустит `release.yml`, и тот
завершится ошибкой (версия уже на RubyGems) — это ожидаемо, гем от этого не меняется.

```bash
gem build --strict haskimail-rails.gemspec
gem push haskimail-rails-1.0.0.gem   # нужен аккаунт RubyGems с правами на гем и включённой MFA
git tag -a v1.0.0 -m "Haskimail Rails v1.0.0" && git push origin v1.0.0
```
