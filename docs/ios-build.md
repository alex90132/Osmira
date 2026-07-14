# Сборка iOS-версии Osmira

Этот документ — пошаговая инструкция для сборки iOS-приложения на **Mac**.
Каркас, нативный слой (Swift), entitlements и Info.plist уже лежат в репозитории;
на Mac остаётся создать в Xcode таргет расширения, подключить бэкенд AmneziaWG и
настроить подпись. Всё, что перечислено ниже, делается один раз.

> На Linux/Windows iOS собрать нельзя — нужен macOS + Xcode.

## Что уже готово в репозитории

```
app/ios/
├── Runner/
│   ├── AppDelegate.swift            # регистрирует нативные бриджи, ловит открытие .vpn/vpn://
│   ├── OsmiraVpnPlugin.swift        # канал osmi.awg2/vpn (+ osmi.awg2/vpn_status): управляет NETunnelProviderManager
│   ├── OsmiraImportPlugin.swift     # канал osmi.awg2/import: getInitial/pickFile/onImport
│   ├── Runner.entitlements          # Network Extensions + App Group
│   └── Info.plist                   # имя Osmira, ассоциация .vpn, схема vpn://
└── PacketTunnel/                    # содержимое будущего таргета-расширения
    ├── PacketTunnelProvider.swift   # NEPacketTunnelProvider → wgTurnOn(uapi, tunFd)
    ├── PacketTunnel-Bridging-Header.h  # extern-объявления C-функций AmneziaWG-Go
    ├── Info.plist                   # NSExtension (packet-tunnel)
    └── PacketTunnel.entitlements    # Network Extensions + App Group
```

Bundle ID приложения — `osmi.awg2` (как на Android). Bundle ID расширения —
`osmi.awg2.PacketTunnel`. App Group — `group.osmi.awg2`. Минимальная iOS — 15.0.

## Предварительные требования

- macOS + **Xcode 15+**, установленные Command Line Tools.
- **Flutter** (та же версия, что в CI — 3.44.4) и CocoaPods (`sudo gem install cocoapods`).
- **Платный Apple Developer Program** — без него недоступен entitlement
  `packet-tunnel-provider`.
- Реальное устройство iPhone/iPad — VPN-расширения **не работают в симуляторе**.

## Шаг 1. Подготовить Flutter-часть

```bash
cd app
flutter pub get
flutter precache --ios
flutter build ios --config-only   # сгенерит Pods/xcconfig без полной сборки
```

Если в `ios/Podfile` не задан минимум — впишите `platform :ios, '15.0'` и
выполните `cd ios && pod install`.

## Шаг 2. Открыть проект

```bash
open ios/Runner.xcworkspace
```

Всегда открывайте **`.xcworkspace`**, а не `.xcodeproj` (иначе не подхватятся Pods).

## Шаг 3. Подпись Runner

1. Target **Runner → Signing & Capabilities**.
2. Выберите свою **Team**, убедитесь, что Bundle Identifier = `osmi.awg2`.
3. Добавьте capability **App Groups** → `group.osmi.awg2`.
4. Добавьте capability **Network Extensions**.
5. Убедитесь, что build setting `Code Signing Entitlements` для Runner указывает на
   `Runner/Runner.entitlements` (файл уже в репозитории; Xcode обычно проставляет
   путь сам при добавлении capability — если создал новый, замените его нашим).

## Шаг 4. Создать таргет расширения

1. **File → New → Target… → Network Extension** (тип **Packet Tunnel Provider**).
   - Product Name: `PacketTunnel`
   - Bundle Identifier: `osmi.awg2.PacketTunnel`
   - Embed in Application: **Runner**
2. Xcode создаст болванку `PacketTunnelProvider.swift` и `Info.plist` внутри новой
   папки таргета. **Удалите их** (Move to Trash) и вместо них **добавьте в таргет
   существующие файлы** из `app/ios/PacketTunnel/`:
   - `PacketTunnelProvider.swift`
   - `Info.plist` (в настройках таргета `Info.plist File` → `PacketTunnel/Info.plist`)
   - `PacketTunnel.entitlements` (`Code Signing Entitlements` → путь к нему)
3. Bridging header: build setting `Objective-C Bridging Header` таргета PacketTunnel →
   `PacketTunnel/PacketTunnel-Bridging-Header.h`.
4. **Signing & Capabilities** таргета PacketTunnel: та же Team, добавьте
   **App Groups** (`group.osmi.awg2`) и **Network Extensions**.

## Шаг 5. Подключить бэкенд AmneziaWG-Go

Нужна нативная библиотека AmneziaWG-Go для Apple (аналог нашей `libwg-go.so` на
Android). Берём из форка Amnezia:

1. **File → Add Package Dependencies…**, URL:
   `https://github.com/amnezia-vpn/amneziawg-apple`
   (если структура пакета отличается — можно вендорить исходники
   `amneziawg-go-apple` и собрать `libwg-go.a` его `Makefile`).
2. Продукт с Go-ядром (WireGuardKitGo / бэкенд-таргет) подключите **к таргету
   PacketTunnel**, чтобы Go-архив линковался именно в расширение.
3. Проверьте имена экспортируемых C-символов. Наш bridging header объявляет
   `wgTurnOn/wgTurnOff/wgGetConfig/...`. Если конкретный форк экспортирует их как
   `awg*`, отредактируйте `PacketTunnel-Bridging-Header.h` и вызовы в
   `PacketTunnelProvider.swift` под фактические имена.

> AWG2-параметры (`Jc/Jmin/Jmax`, `S1–S4`, `H1–H4`, `I1–I5`) уже приходят внутри
> строки `uapi` из Dart и передаются в `wgTurnOn` — отдельно настраивать их не
> нужно.

## Шаг 6. App ID и App Group в портале разработчика

При автоматической подписи Xcode создаст App ID для `osmi.awg2` и
`osmi.awg2.PacketTunnel` сам. **App Group `group.osmi.awg2`** нужно создать в
[developer.apple.com](https://developer.apple.com/account/resources/identifiers)
и включить для обоих App ID (Xcode обычно предлагает сделать это в один клик).

## Шаг 7. Сборка и запуск

```bash
flutter run --release        # на подключённом устройстве
# или архив для распространения:
flutter build ipa --release
```

Первый запуск попросит подтвердить добавление VPN-конфигурации — это системный
диалог iOS.

## Распространение

В отличие от Android APK, `.ipa` нельзя просто положить в GitHub Releases и
поставить в один тап. Варианты:

- **TestFlight** — до 10 000 тестеров, но нужен App Store Connect и ревью беты.
- **App Store** — публичная раздача; VPN-приложения проходят усиленную модерацию
  (нужно обосновать назначение и политику приватности).
- **Сайдлоад** (AltStore/Sideloadly) — для себя/друзей без App Store.

## Ограничения iOS (отличия от Android)

- **Нет пофайлового/поприложенчатого сплит-туннеля.** На iOS для обычных
  приложений его нет (только через MDM). Dart-метод `listApps` на iOS возвращает
  пустой список, экран «Приложения» будет пустым, а туннель работает как полный
  (маршрутизация только по IP/подсетям через `routes`).
- **Лимит памяти расширения** (~50 МБ у packet-tunnel). Go-ядро тяжёлое; если
  упрётесь в лимит — включите в бэкенде тюнинг `GOGC`/`madvdontneed` (как в
  amneziawg-apple по умолчанию).
- Статус подключения приходит из системного `NEVPNStatusDidChange`; счётчики
  rx/tx/handshake расширение отдаёт хосту по запросу `sendProviderMessage`.

## Карта каналов (общая с Android)

| Канал | Методы | Кто реализует на iOS |
|---|---|---|
| `osmi.awg2/vpn` | `prepare`, `connect`, `disconnect`, `status`, `listApps` | `OsmiraVpnPlugin` |
| `osmi.awg2/vpn_status` (event) | поток `{state,id,rxBytes,txBytes,lastHandshake,error}` | `OsmiraVpnPlugin` |
| `osmi.awg2/import` | `getInitial`, `pickFile`, `onImport` | `OsmiraImportPlugin` |

Формат `connect`-payload и строка `uapi` идентичны Android — Dart-код не меняется.
