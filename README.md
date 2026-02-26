<img width="128" height="128" src="./docs/mactrix-icon.webp">

# Mactrix

[![Mactrix chatroom](https://img.shields.io/badge/matrix-%23mactrix-blue?logo=matrix)](https://matrix.to/#/%23mactrix:qpqp.dk)

A native macOS client for [Matrix](https://matrix.org) – an open protocol for decentralised, secure communications.

## Overview

Mactrix is built with Apple's [SwiftUI](https://developer.apple.com/swiftui/) framework to provide seamless native integration with macOS. It leverages the robust [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk) for stability and performance.

Feel free to join our Matrix room at [#mactrix:qpqp.dk](https://matrix.to/#/#mactrix:qpqp.dk).

![Screenshot of the app](docs/screenshot-main.png)

## Installation

Mactrix is currently in early development, which means that distribution with auto-updates does not exist yet. However, the latest version is built automatically and can be [downloaded here](https://github.com/viktorstrate/mactrix/actions/workflows/xcode-build.yml?query=branch%3Amain+event%3Apush). Simply select the latest build and download `Mactrix.app` under Artifacts.

## Build From Source

### Requirements

- macOS 15 or later
- Up-to-date Xcode installed

Xcode will automatically download all dependencies when building the project for the first time.

### Building

```bash
git clone https://github.com/viktorstrate/mactrix.git
cd mactrix
xed .
```

Then open the project in Xcode and build using `Cmd+B`.

### Completed Feature List

- [ ] Authentication
  - [x] Password
  - [x] OAuth
  - [ ] Email and Phone
- [ ] Multi account
- [ ] Timeline
  - [x] Messages
    - [ ] Send attachments
    - [x] Markdown formatting
  - [ ] Message actions
    - [x] Add reactions
    - [x] Reply to
    - [x] Pin
    - [ ] Edit
  - [x] Show reactions
  - [ ] Group timeline virtual items:
    - Removed messages, user join / leave, username change, profile picture change
  - [x] Show read receipts
  - [ ] Attachments
    - [ ] Support all formats (video, audio, files)
    - [ ] Download attachment to file
    - [x] Preview attachments
- [ ] Rooms
  - [x] New room,
  - [ ] Room settings,
  - [ ] Invite to room
- [x] Threads
  - [x] Focus thread
  - [x] Reply in thread
- [ ] Spaces
  - [x] Show spaces in sidebar
  - [ ] Details view when selecting a space
  - [ ] Drag and drop to organize spaces
- [ ] Search bar
  - [ ] Search in joined rooms and directs
  - [x] Search for users
  - [x] Search for public rooms
  - [ ] Search for messages
  - [x] Search for room or user ID directly
- [ ] Settings
  - [x] Account details
  - [x] Sign out
  - [ ] Sessions
    - [x] Emoji verification
    - [x] See verified / unverified status
    - [ ] Verify with recovery key
    - [ ] Change recovery key
    - [ ] Rename current and other sessions
    - [ ] Sign out other sessions
    - [ ] Send only to verified users
    - [ ] Export / import encryption keys
  - [ ] Start on login
  - [ ] Presence
    - [ ] Read receipts and typing indicator toggles
- [ ] Notifications
  - [x] Message notification
  - [ ] Verify session notification
- [x] Multiple windows and tabs
- [ ] Navigation: forwards and backwards button
- [x] Support matrix URLs
- [ ] Keyboard navigation and accessibility
- [ ] Video and voice chat

## Screenshots

### Main Chat Interface

![Screenshot of the app](docs/screenshot-main.png)

### Device Verification

The app supports device verification by comparing emojis with another client.

![Screenshot of device emoji verification](docs/screenshot-verification.png)

### Create Room

Creation

![Screenshot of room creation page](docs/screenshot-create-room.png)

### Search

Find specific rooms, users, and public communities directly from the search bar.

![Screenshot of search for specific room](docs/screenshot-search.png)
