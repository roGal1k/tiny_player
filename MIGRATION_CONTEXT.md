# Core Player — Полный контекст проекта и миграции (Migration & Handoff Guide)

> **Дата актуализации:** 13 октября 2026  
> **Репозиторий:** `git@github.com:roGal1k/tiny_player.git`  
> **Ветка:** `main`  
> **Последний стабильный коммит:** `b1218be` (хранение файлов пользователя на VPS, синхронизация артистов и медиатеки)

---

## 1. Сводка проекта и архитектура

**Core Player** (`com.gera.player.core_player`) — кроссплатформенный мультипровайдерный музыкальный плеер с открытой архитектурой, поддержкой облачной синхронизации, умного кэширования и приоритетной предзагрузки.

### Поддерживаемые платформы
- **Linux Desktop** (x64 GTK/Flutter bundle, Wayland / X11)
- **Android** (APK, API 21+, проверен на физическом Nothing Phone)
- **Web** (CanvasKit / Wasm / HTML5 Audio)
- **VPS Backend** (FastAPI, Python 3, Uvicorn, SQLite, Caddy reverse-proxy)

### Ключевые архитектурные модули
- `lib/data/providers/`: провайдеры музыки (Hitmo с зеркалами и CDN 302 redirect, YouTube Music via `youtube_explode_dart`, SoundCloud, Local Library).
- `lib/data/services/artist_service.dart`: работа с авторами через Deezer API, локальное хранение в SQLite (`favorite_artists`), связь с плеером.
- `lib/data/services/track_preload_manager.dart`: умная асинхронная предзагрузка следующих 10 треков очереди с абсолютным приоритетом текущего играющего трека.
- `lib/data/services/sync_service.dart`: клиент синхронизации медиатеки, избранных авторов, настроек и файлов бэкапа на VPS.
- `lib/data/local/database_helper.dart`: локальная SQLite база данных (`sqflite` на Android, `sqflite_common_ffi` на Linux/Desktop, WASM на Web).
- `server/main.py`: легковесный бэкенд на FastAPI для авторизации, синхронизации и файлового хранилища профилей пользователей.

---

## 2. Данные сервера VPS и сетевой инфраструктуры

### Доступ и хостинг
- **IP адрес:** `146.71.85.50`
- **Доменное имя:** `galik-tech.su` (порты `:80` HTTP и `:8443` HTTPS)
- **SSH доступ:** 
  ```bash
  ssh root@146.71.85.50
  ```
  *(Настроен беспарольный доступ по SSH-ключу с локальной машины пользователя)*

### Пути и файловая структура на сервере
| Назначение | Путь на VPS |
|---|---|
| Исходный код бэкенда | `/opt/core_player_server/main.py` |
| Виртуальное окружение Python | `/opt/core_player_server/venv/` |
| База данных SQLite | `/var/lib/core_player/core_player.db` |
| Физические файлы профилей пользователей | `/var/lib/core_player/user_files/{username}_data.json` |
| Версионированные архивы бэкапов | `/var/lib/core_player/user_files/backups/{username}_{timestamp}.json` |
| Веб-версия плеера (Flutter Web) | `/var/www/core_player_web/` |
| Публичный APK для скачивания | `/var/www/galik-tech.su/core_player.apk` |
| Лендинг и QR-код для установки | `/var/www/galik-tech.su/index.html` и `apk_qr.svg` |
| Конфигурация веб-сервера Caddy | `/etc/caddy/Caddyfile` |
| Системный юнит systemd | `/etc/systemd/system/core-player-sync.service` |

### Systemd сервис (`core-player-sync.service`)
```ini
[Unit]
Description=CorePlayer Sync and Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/core_player_server
ExecStart=/opt/core_player_server/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=3
Environment=DB_PATH=/var/lib/core_player/core_player.db

[Install]
WantedBy=multi-user.target
```

**Команды управления службой:**
```bash
systemctl status core-player-sync.service
systemctl restart core-player-sync.service
journalctl -u core-player-sync.service -n 50 -f
```

### Маршрутизация Caddy (`/etc/caddy/Caddyfile`)
- `/api/*` ➔ Проксируется на `http://127.0.0.1:8000` (FastAPI).
- `/core_player.apk` ➔ Отдает файл с заголовком `Content-Disposition: attachment`.
- `/about` и `/about/*` ➔ Лендинг установки приложения.
- `/` (корень) ➔ Хостинг Flutter Web приложения (`/var/www/core_player_web`).

---

## 3. Серверные API эндпоинты

Базовый URL: `http://galik-tech.su` (или локально на сервере `http://127.0.0.1:8000`)

| Метод | Эндпоинт | Назначение | Параметры / Тело |
|---|---|---|---|
| `GET` | `/api/health` | Проверка работоспособности | - |
| `POST` | `/api/auth/register` | Регистрация аккаунта | JSON: `{"username": "...", "password": "..."}` |
| `POST` | `/api/auth/login` | Авторизация (получение JWT) | JSON: `{"username": "...", "password": "..."}` |
| `POST` | `/api/sync/push` | Отправка медиатеки и артистов | Header: `Bearer <token>`, JSON: `{"library": [...], "artists": [...]}` (автоматически обновляет JSON-файл пользователя на диске VPS) |
| `GET` | `/api/sync/pull` | Получение облачных треков и артистов | Header: `Bearer <token>` |
| `GET` | `/api/user/file/info` | Получение метаданных файла бэкапа на VPS | Header: `Bearer <token>` (возвращает размер, дату, число треков и авторов) |
| `GET` | `/api/user/file/download` | Прямое скачивание `{username}_data.json` | Header: `Bearer <token>` |
| `POST` | `/api/user/file/upload` | Восстановление профиля из JSON | Header: `Bearer <token>`, JSON-тело полного профиля |

---

## 4. Локальное окружение разработки и переменные

- **Рабочая директория:** `/home/gera/player`
- **Flutter SDK:**
  ```bash
  export PATH="/home/gera/.local/share/antigravity-profiles/account-2/home/flutter/bin:$PATH"
  ```
- **Подключенный Android-девайс для отладки:**
  - Модель: Nothing Phone
  - Серийный номер ADB: `0011334AT002158`
  - Проверка связи: `adb -s 0011334AT002158 devices`
  - Application ID: `com.gera.player.core_player`
  - Main Activity: `com.gera.player.core_player/.MainActivity`
- **Локальный дисплей для десктопного приложения:**
  ```bash
  DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 ./build/linux/x64/release/bundle/core_player
  ```

---

## 5. Полный цикл сборки и развертывания (Deployment Runbook)

### 1. Тестирование
```bash
export PATH="/home/gera/.local/share/antigravity-profiles/account-2/home/flutter/bin:$PATH"
flutter test
# Проект содержит 104 теста, все должны завершаться с кодом 0 (100% pass)
```

### 2. Сборка и запуск Linux Desktop
```bash
flutter build linux --release
# Перезапуск запущенного процесса
killall -9 core_player 2>/dev/null || true
DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 ./build/linux/x64/release/bundle/core_player &
```

### 3. Сборка и установка на Android
```bash
flutter build apk --release
adb -s 0011334AT002158 install -r build/app/outputs/flutter-apk/app-release.apk
adb -s 0011334AT002158 shell am force-stop com.gera.player.core_player
adb -s 0011334AT002158 shell monkey -p com.gera.player.core_player -c android.intent.category.LAUNCHER 1
```

### 4. Сборка и деплой на VPS (Web + APK + Backend)
```bash
# 1. Сборка Web
flutter build web --release

# 2. Обновление Web и APK на VPS
scp -r build/web/* root@146.71.85.50:/var/www/core_player_web/
scp build/app/outputs/flutter-apk/app-release.apk root@146.71.85.50:/var/www/galik-tech.su/core_player.apk

# 3. Деплой изменений бэкенда (при модификации server/main.py)
scp server/main.py root@146.71.85.50:/opt/core_player_server/main.py
ssh root@146.71.85.50 "systemctl restart core-player-sync.service"
```

---

## 6. Ключевые фичи и история решений в текущей сессии

1. **Решение проблемы непрогрузки треков в плеере:**
   - Добавлена поддержка рабочих зеркал Hitmo (`https://ru.hitmoz.org`, `https://rur.hitmotop.com`) и обработка 302 Redirect в CDN потоки.
   - Улучшен fallback на YouTube при недоступности трека в других источниках.
2. **Вкладка «Артисты»:**
   - Добавлена в левый боковой сайдбар (Desktop) и нижний бар (Mobile).
   - Интегрирован поиск исполнителей по Deezer API и сохранение в SQLite таблицу `favorite_artists`.
3. **Фильтрация треков артиста по источникам без дублирования:**
   - После выбора артиста отображаются фильтры по источникам (`Все`, `Hitmo`, `YouTube`, `Медиатека`).
   - Исправлен баг задвоения названия источника вместо реального имени исполнителя в карточке трека.
4. **Приоритетная асинхронная предзагрузка треков (`TrackPreloadManager`):**
   - Автоматически предзагружает следующие 10 треков очереди при воспроизведении.
   - Приоритет текущего трека: старт предзагрузки через 3.5 секунды, пауза при буферизации, сброс сессии (эпоха) при ручном переключении.
   - Дросселирование запросов (400 мс) для защиты от блокировок провайдерами.
5. **Хранение файла пользователя на VPS и бэкап данных:**
   - Синхронизация объединяет лайки/медиатеку, любимых авторов и настройки.
   - На сервере VPS сохраняется отдельный физический JSON-файл пользователя по пути `/var/lib/core_player/user_files/{username}_data.json` и архивы в папке `backups/`.
   - В UI экрана аккаунта добавлены кнопки для принудительного сохранения на VPS, восстановления с VPS, а также локального экспорта и импорта `.json`.

---

## 7. Контрольный чек-лист для нового агента / сессии

При подключении к работе новому агенту достаточно выполнить:
1. Проверить статус Git: `git status` и ветку `main`.
2. Проверить доступность VPS: `ssh root@146.71.85.50 "systemctl is-active core-player-sync.service"`.
3. Запустить тесты: `export PATH="/home/gera/.local/share/antigravity-profiles/account-2/home/flutter/bin:$PATH" && flutter test`.
4. При необходимости отладки на телефоне убедиться, что `adb devices` видит `0011334AT002158`.
