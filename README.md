# FluffyChat RedForged

A customized fork of FluffyChat, the cute Matrix client, tailored for the RedForged community.

## About

FluffyChat RedForged is an open source Matrix client written in Flutter. This fork includes custom features and configurations specific to the RedForged ecosystem while maintaining the user-friendly and secure nature of the original FluffyChat.

## Features

- 📩 Send all kinds of messages, images and files
- 🎙️ Voice messages
- 📍 Location sharing
- 🔔 Push notifications
- 💬 Unlimited private and public group chats
- 📣 Public channels with thousands of participants
- 🛠️ Feature rich group moderation including all matrix features
- 🔍 Discover and join public groups
- 🌙 Dark mode
- 🎨 Material You design
- 📟 Hides complexity of Matrix IDs behind simple QR codes
- 😄 Custom emotes and stickers
- 🌌 Spaces
- 🔄 Compatible with Element, Nheko, NeoChat and all other Matrix apps
- 🔐 End to end encryption
- 🔒 Encrypted chat backup
- 🔑 Secure recovery key storage with auto-unlock
- 😀 Emoji verification & cross signing

... and much more.

## 🚀 RedForged Exclusive Features

This fork adds several enhancements not available in the original FluffyChat:

- 🔐 **OIDC Authentication** - Support for OpenID Connect authentication with Matrix servers
- 🔑 **Secure Recovery Key Storage** - Store recovery keys securely on device with automatic SSSS unlock on startup
- 👤 **User Biographies** - View and edit user profile biographies for richer social profiles

These features enhance security, convenience, and social interaction within the Matrix ecosystem.

## Installation

This is a customized fork. For installation instructions and downloads, please visit:

- https://redforged.eu

## How to Build

1. To build FluffyChat RedForged you need [Flutter](https://flutter.dev) and [Rust](https://www.rust-lang.org/tools/install)

2. Clone this repository:
```bash
git clone https://github.com/AxoIsAxo/fluffychat-redforged.git
cd fluffychat-redforged
```

3. Choose your target platform below and enable support for it.
3.1 If you want, enable Googles Firebase Cloud Messaging:

```bash
./scripts/add-firebase-messaging.sh
```

4. Debug with: `flutter run`

### Android

* Build with: `flutter build apk`

### iOS / iPadOS

* Have a Mac with Xcode installed, and set up for Xcode-managed app signing
* If you want automatic app installation to connected devices, make sure you have Apple Configurator installed, with the Automation Tools (`cfgutil`) enabled
* Set a few environment variables
    * FLUFFYCHAT_NEW_TEAM: the Apple Developer team that your certificates should live under
    * FLUFFYCHAT_NEW_GROUP: the group you want App IDs and such to live under (ie: com.example.fluffychat)
    * FLUFFYCHAT_INSTALL_IPA: set to `1` if you want the IPA to be deployed to connected devices after building, otherwise unset
* Run `./scripts/build-ios.sh`

### Web

* Build with:
```bash
./scripts/prepare-web.sh # To install Vodozemac
flutter build web --release
```

* Optionally configure by serving a `config.json` at the same path as fluffychat.
  An example can be found at `config.sample.json`. All values there are optional.
  **Please only the values, you really need**. If you e.g. only want
  to change the default homeserver, then only modify the `defaultHomeserver` key.

### Desktop (Linux, Windows, macOS)

* Enable Desktop support in Flutter: https://flutter.dev/desktop

#### Install custom dependencies (Linux)

```bash
sudo apt install libjsoncpp1 libsecret-1-dev libsecret-1-0 librhash0 libwebkit2gtk-4.0-dev lld
```

* Build with one of these:
```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

## Fork Information

This is a fork of the original FluffyChat project with customizations for the RedForged community. The original project can be found at: https://github.com/krille-chan/fluffychat

### Changes in this Fork

- **OIDC Authentication Support** - Full OpenID Connect integration for modern authentication
- **Secure Recovery Key Storage** - Device-local secure storage with automatic SSSS unlock
- **User Biographies** - Enhanced profile system with user biographies
- **Custom Branding** - RedForged-specific theming and configuration
- **Bug Fixes & Improvements** - Various stability and usability enhancements
- **Version 0.1.0** - Initial stable release of the RedForged fork

## License

This project maintains the same license as the original FluffyChat project. Please refer to the LICENSE file for details.

## Contributing

Contributions to this fork are welcome. Please ensure any contributions align with the RedForged community goals and standards.
