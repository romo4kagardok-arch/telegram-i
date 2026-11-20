# telegram i

Сборка Android-клиента **telegram i** из исходников [teamgram-android](https://github.com/teamgram/teamgram-android)
(форк официального Telegram для Android, GPL-2.0) для своего сервера [Teamgram](https://github.com/teamgram/teamgram-server).

## Что меняется в исходниках

Всё делает [`branding/rebrand.sh`](branding/rebrand.sh) во время сборки:

- название приложения → `APP_NAME`;
- package id → `APP_PACKAGE` (ставится рядом с обычным Telegram);
- адрес сервера → `SERVER_IP:SERVER_PORT`, пустой `SERVER_IP` оставляет тестовый сервер Teamgram;
- иконка из [`branding/icon.webp`](branding/icon.webp);
- архитектуры → `ABIS` (по умолчанию только ARM, чтобы сборка шла быстрее).

Настройки лежат в [`config.env`](config.env).

## Как собрать

1. Один раз: секрет `KEYSTORE_PASSWORD`, затем workflow «Создать ключ подписи», содержимое ключа в base64 в секрет `KEYSTORE_B64`.
2. Actions → «Сборка Android (APK)» → Run workflow. Сборка также запускается при изменении `config.env` или `branding/`.
3. Готовый APK появляется в Releases.

Сборка идёт 1–3 часа.

## Лицензия

GPL-2.0, как у исходного Telegram для Android.
