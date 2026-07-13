<h1 align="center">Osmira</h1>

<p align="center">
  A small, no-nonsense <b>AmneziaWG (AWG 2.0)</b> VPN client for Android.<br/>
  Drop in a <code>.vpn</code> config, pick which apps go through the tunnel, and forget about it.
</p>

<p align="center">
  <a href="README.md"><b>English</b></a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="Platform: Android" src="https://img.shields.io/badge/platform-Android%209%2B-3ddc84">
  <img alt="Protocol: AmneziaWG" src="https://img.shields.io/badge/protocol-AmneziaWG%202.0-3b82f6">
</p>

<p align="center">
  <img src="docs/screenshots/home.webp" width="260" alt="Home screen">
  &nbsp;&nbsp;
  <img src="docs/screenshots/connected.webp" width="260" alt="Connected">
</p>

## What it does

Osmira speaks AmneziaWG — WireGuard with the obfuscation layer that makes the
handshake look like nothing in particular on the wire (`Jc/Jmin/Jmax`,
`S1–S4`, `H1–H4`, `I1–I5`, all AWG2 fields supported). It's built to be boring
in the best way: import a config, tap connect, and it stays up.

- **Import anything AmneziaWG** — open a `.vpn` file, paste a `vpn://` link, or
  point it at a plain `.conf`.
- **Per-app routing, globally** — send everything through the tunnel, or keep a
  list of apps *out* of it (your bank, say), or route *only* the apps you pick.
- **Stays connected** — reconnects on its own when the network flips or the
  tunnel goes quiet, and survives deep sleep.
- **Quiet and light** — one ongoing notification, black edge-to-edge UI, no
  accounts, no analytics, no ads.

## Install

Osmira ships through **GitHub Releases**, so the GitHub-powered app stores pick
it up automatically:

- **[Obtainium](https://github.com/ImranR98/Obtainium)** — *Add App* and paste
  this repo's URL. You'll get every future release as an update.
- **[Komi Store](https://www.komistore.app) / RepoStore** — search for
  *Osmira*; they list repos that publish an APK.
- **Manually** — download `osmira-<version>.apk` from the
  [latest release](../../releases/latest) and open it.

> On Android 13+ the app asks for notification permission the first time — it's
> only used for the connection status notification.

## Updating

Every release bumps the version, so Obtainium/Komi Store flag the update the
moment it's out. Builds are always signed with the same key, so updates install
straight over the top — no uninstall dance.

## Build it yourself

```bash
cd app
flutter pub get
flutter build apk --release        # signed if android/key.properties exists
```

The native AmneziaWG backend (`libwg-go.so`, arm64-v8a + x86_64) is checked in
under `app/android/app/src/main/jniLibs/`. Rebuilding it needs the patched Go
toolchain and the AmneziaWG sources — see `build-libwg-go.sh`.

## Privacy & security

- No telemetry, no accounts, nothing phones home. The only traffic is your
  tunnel.
- Saved profiles carry WireGuard **private keys**, so they live in Android's
  encrypted storage (Keystore-backed), never in plain preferences.
- Release builds are **R8 + Dart-obfuscated**, backups are disabled, cleartext
  traffic is off, and the manifest asks for the bare minimum of permissions.

## License

MIT — see [`LICENSE`](LICENSE). The bundled AmneziaWG / WireGuard-Go backend is
© WireGuard LLC and Amnezia, also under the MIT License. "WireGuard" is a
registered trademark of Jason A. Donenfeld. Osmira is an independent client and
isn't affiliated with Amnezia or WireGuard.
