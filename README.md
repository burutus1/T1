# Менеджер APK/XAPK скриптами (PowerShell)

Набор PowerShell-скриптов для удобной установки Android-приложений (.apk / .xapk) на устройства через ADB.

## Требования

- Windows (PowerShell 5.1+ или PowerShell 7+).
- ADB (adb.exe) в папке `/adb` или в PATH.

## Быстрый старт

1. Скачайте данный репозиторий.
2. Запустите главный скрипт:

- Через командный файл: .\start.cmd

  (start.cmd вызывает скрипт PowerShell с нужными параметрами — удобно для пользователей Windows)

- Альтернативно, можно запустить напрямую PowerShell:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts_light\light_start.ps1

3. Если требуется — запустите `scripts_light\setup_light.ps1` для автоматической загрузки ADB.

## Структура репозитория

- /scripts_light/light_start.ps1 — главный меню-скрипт (интерфейс).
- /scripts_light/setup_light.ps1 — загрузка и настройка зависимостей.
- /_APPS_ — каталоги приложений.

## Устранение неполадок
- При проблемах с ADB убедитесь, что устройство доступно: `adb devices`.
