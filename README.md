# Zync

Zync is a cross-platform peer-to-peer (P2P) file-sharing application designed for fast, local transfers between Android, Windows, and Linux devices. Built with Flutter.

## Features

- Cross-Platform Support: Seamlessly share files between Android, Windows, and Linux.
- QR Code Pairing: Quickly connect devices by scanning a dynamically generated QR code containing the server connection details (Camera scanning available on Android).
- Direct File Transfers: Hosts a local HTTP server on the sender device for direct, high-speed file transfers.
- Activity History: Maintains a persistent local record of shared files.

## Installation

### Prerequisites

For Linux builds, `libsecret-devel` is a required dependency. Install it using your distribution's package manager before building the project.

### Building and Running

1. Ensure you have the Flutter SDK installed and configured.
2. Clone the repository.
3. Fetch the dependencies:
   ```bash
   flutter pub get
   ```
4. Run the project:
   ```bash
   flutter run
   ```
