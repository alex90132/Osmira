<h1 align="center">Osmira</h1>

<p align="center">
  Простой VPN-клиент <b>AmneziaWG (AWG 3.0)</b> для Android.<br/>
  Закинул <code>.vpn</code>-конфиг, выбрал, какие приложения пускать в туннель, и забыл.
</p>

<p align="center">
  <b>Русский</b> ·
  <a href="README.en.md">English</a>
</p>

<p align="center">
  <img alt="Лицензия: MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="Платформа: Android" src="https://img.shields.io/badge/platform-Android%209%2B-3ddc84">
  <img alt="Протокол: AmneziaWG" src="https://img.shields.io/badge/protocol-AmneziaWG%203.0-3b82f6">
</p>

<p align="center">
  <img src="docs/screenshots/home.webp" width="45%" alt="Главный экран">
  <img src="docs/screenshots/connected.webp" width="45%" alt="Подключено">
</p>

## Что умеет

Osmira работает по AmneziaWG. Это WireGuard с обфускацией, из-за которой
рукопожатие не выделяется в трафике. Поддержаны все параметры AWG2
(`Jc/Jmin/Jmax`, `S1-S4`, `H1-H4`, `I1-I5`) и AWG3: шифрование заголовков
(`HeaderProtectionKey`), добивка данных (`ContentPaddingAddition`) и настраиваемые
тайминги рукопожатия (`RekeyAfterTime`, `RekeyTimeout`, `RejectAfterTime`,
`KeepaliveTimeout`, `MaxHandshakeAttempts`), включая диапазоны вида `20-30`.
Ничего лишнего: импортировал конфиг, нажал «подключить», и он держит соединение.

- **Импорт чего угодно из AmneziaWG.** Открой `.vpn`-файл, вставь `vpn://`-ссылку
  или скорми обычный `.conf`.
- **Раздельный туннель, глобально.** Весь трафик через VPN, либо список
  приложений мимо туннеля (например, банк), либо только выбранные приложения.
- **Держит соединение.** Сам переподключается при смене сети или зависании
  туннеля, переживает глубокий сон устройства.
- **Тихий и лёгкий.** Одно уведомление, чёрный интерфейс во весь экран, без
  аккаунтов, аналитики и рекламы.

## Установка

Osmira распространяется через **GitHub Releases**, поэтому магазины на базе
GitHub подхватывают её сами:

- **[Obtainium](https://github.com/ImranR98/Obtainium):** *Add App*, вставь
  ссылку на этот репозиторий. Все будущие релизы прилетят как обновления.
- **[Komi Store](https://www.komistore.app) / RepoStore:** найди *Osmira*, они
  показывают репозитории, которые публикуют APK.
- **Вручную:** из [последнего релиза](../../releases/latest) скачай
  `osmira-<версия>-arm64.apk` (почти любой телефон) или `-x86_64.apk`
  (эмуляторы) и открой.

> На Android 13+ при первом запуске приложение попросит разрешение на
> уведомления. Оно нужно только для статуса подключения.

## Обновления

Каждый релиз поднимает версию, так что Obtainium/Komi Store видят обновление
сразу после публикации. Сборки всегда подписаны одним ключом, поэтому
обновление ставится поверх, без удаления.

## Собрать самому

```bash
cd app
flutter pub get
flutter build apk --release        # подпишется, если есть android/key.properties
```

Нативный бэкенд AmneziaWG (`libwg-go.so`, arm64-v8a + x86_64) лежит в
`app/android/app/src/main/jniLibs/`. Чтобы пересобрать его, нужен патченый
Go-тулчейн и исходники AmneziaWG. Как это делается, смотри в `build-libwg-go.sh`.

## Приватность и безопасность

- Никакой телеметрии и аккаунтов, наружу ничего не уходит, кроме твоего туннеля.
- Профили содержат приватные ключи WireGuard, поэтому хранятся в зашифрованном
  хранилище Android (на базе Keystore), а не в открытых настройках.
- Релизные сборки проходят **R8 + обфускацию Dart**, бэкапы отключены,
  открытый HTTP запрещён, а манифест просит минимум разрешений.

## Лицензия

Лицензия MIT, подробности в [`LICENSE`](LICENSE). Встроенный бэкенд
AmneziaWG / WireGuard-Go принадлежит © WireGuard LLC и Amnezia и тоже
распространяется под MIT. «WireGuard» является зарегистрированным товарным
знаком Jason A. Donenfeld. Osmira является независимым клиентом и не связана с
Amnezia или WireGuard.
