# Limón

Limón is a lightweight macOS menu bar app for managing a local
[Colima](https://github.com/abiosoft/colima) environment and its Docker
containers.

<p align="center">
  <img src=".github/limon.png" alt="Limón menu bar app" width="700">
</p>

From the menu bar, you can start or stop Colima, inspect containers, open
shells and logs, restart workloads, and review images and volumes.

## Requirements

- macOS 26 or later
- Xcode 26 or later (macOS 26 SDK) to build
- [Colima](https://github.com/abiosoft/colima) and the Docker CLI

## Build

```sh
make
open "Limón.app"
```
