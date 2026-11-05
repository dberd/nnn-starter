# План миграции на CachyOS (Niri + Noctalia)

Этот документ содержит полную архитектуру, сравнение с апстримом CachyOS, руководство по сохранению настроек и пошаговый процесс установки.

---

## 1. Найденные материалы предыдущего перехода (CachyOS → NixOS)

В данном репозитории сохранились все ключевые документы и скрипты, написанные во время предыдущего переезда:

1. **`docs/migrate-from-cachyos.sh`** — скрипт переноса данных пользователя:
   - Содержит точные списки того, что переносилось (сейвы Steam, `.claude`, профиль Zen, Fish history, Work, Documents, Pictures), и списки мусора, который исключался (`node_modules`, `.angular`, кэши build/obj).
   - Готовый алгоритм слияния истории Fish (`stage_fish_history`).
2. **`docs/install-plan.md`** — полный отчет об исходной установке, разметке разделов, структуре Limine и всех встреченных «граблях».
3. **`docs/migrate-to-nvme.md`** — детальный лог переноса системы на Kingston NVMe (932G).
4. **`docs/install-t480s.md`** — специфика второго устройства (ThinkPad T480s: LUKS, swap под гибернацию, Intel iGPU).

---

## 2. Анализ дисков, Windows 10 и загрузчика Limine

Перед переустановкой на тот же диск (`nvme0n1`) мы провели детальную проверку таблицы разделов и загрузчика.

### Физическое распределение дисков:
* **`sda` (Kingston SA400, SATA SSD):** **Диск Windows 10.**
  * `sda1` (FAT32, PARTUUID: `1fef5bef-7f01-4f77-a93d-a61b09e5af04`) — **ESP-раздел Windows 10** (`bootmgfw.efi`).
  * `sda3` (NTFS) — системный диск Windows (`C:\`).
* **`sdb` (ADATA SU650, SATA SSD):**
  * `sdb2` (NTFS, PARTUUID: `8882125e-f5e2-413c-b468-1f4f1c905644`) — **`Additional_500`** (свободно ~60 ГБ, сюда делаем бэкап).
* **`nvme0n1` (Kingston SNV3S 1TB, NVMe):** **Диск под CachyOS.**
  * `nvme0n1p1` — текущий ESP NixOS (`/boot`).
  * `nvme0n1p2` — текущий Btrfs корень NixOS.

### Безопасность Windows 10:
> [!IMPORTANT]
> **Windows 10 находится на отдельном физическом диске (`sda`) со своим собственным независимым ESP-разделом.**
> Форматирование и шифрование NVMe-диска (`nvme0n1`) **никак не затронет диск Windows 10**.

### Как настроить загрузку Windows 10 в CachyOS (Limine / GRUB / systemd-boot):
1. **В UEFI:** в любой момент при включении ПК клавиша F11 / F12 откроет Boot Menu материнской платы, где `Windows Boot Manager` доступен напрямую.
2. **Если в CachyOS выбран Limine:** в `/boot/limine.conf` просто добавляется проверенная рабочая запись:
   ```
   /Windows 10
       protocol: efi
       path: guid(1fef5bef-7f01-4f77-a93d-a61b09e5af04):/EFI/Microsoft/Boot/bootmgfw.efi
   ```
3. **Если выбран GRUB или systemd-boot:** утилита `os-prober` (включена по умолчанию в CachyOS) автоматически обнаружит `sda1` и добавит строку Windows 10 в меню.

---

## 3. Резервное копирование на `/run/media/sundial/Additional_500`

Создан готовый скрипт **`scripts/backup-to-additional500.sh`**, который переносит на диск `Additional_500`:
* `~/Documents`, `~/Pictures`, `~/Notes`
* `~/Work` (с автоматическим исключением кэшей `node_modules`, `.angular`, `bin/`, `obj/`)
* Сохранения всех игр:
  * Явные архивы `~/Games/SaveFiles/` и `Save_backups/` (включая Elden Ring).
  * Сейвы из префиксов `~/Games/*` (`Saved Games`, `AppData/Roaming`, `AppData/Local`).
  * Сейвы STALKER Anomaly.
  * Сейвы из Steam `compatdata` (`Saved Games` и `Roaming`).
* База данных библиотеки Lutris (`~/.local/share/lutris/pga.db` и метаданные игр).
* Ключи `~/.ssh`, `~/.gnupg`, проекты `~/.claude`.
* Историю Fish (`fish_history`), профили Zen, Vesktop, Obsidian, Element.

### Запуск бэкапа:
```bash
./scripts/backup-to-additional500.sh
```

---

## 4. Шифрование диска через LUKS при установке CachyOS

При установке CachyOS на `nvme0n1` рекомендуется использовать **LUKS2 + Btrfs**:

### Вариант через Calamares (Графический установщик):
1. На шаге разметки выберите диск **`nvme0n1`**.
2. Выберите пункт **«Стереть диск»** (Erase disk) и выберите файловую систему **Btrfs**.
3. **Обязательно поставьте галочку «Шифровать систему» (Encrypt system)** и введите пароль шифрования.
4. Calamares автоматически:
   * Создаст ESP-раздел `nvme0n1p1` на 1–2 ГБ (не зашифрован, монтируется в `/boot`).
   * Создаст LUKS2-контейнер на `nvme0n1p2`.
   * Внутри контейнера создаст Btrfs со всеми нужными подтомами (`@`, `@home`, `@snapshots`, `@cache`, `@log`).
   * Пропишет нужные хуки `sd-encrypt` в `mkinitcpio.conf` и создаст запись в `/etc/crypttab`.

---

## 5. Сравнение текущего конфига и CachyOS/cachyos-niri-noctalia

Апстрим-репозиторий CachyOS (`CachyOS/cachyos-niri-noctalia`) предоставляет базовую модульную структуру, но не содержит глубоких оптимизаций под реальный рабочий процесс.

| Параметр | Upstream CachyOS (`cachyos-niri-noctalia`) | Наша текущая конфигурация (NixOS) | Что берем в новый сетап |
| :--- | :--- | :--- | :--- |
| **Структура файлов** | **Модульная (`cfg/*.kdl`)**: `animation.kdl`, `autostart.kdl`, `display.kdl`, `input.kdl`, `keybinds.kdl`, `layout.kdl`, `misc.kdl`, `rules.kdl`. | Сгенерированный из Nix монолитный `config.kdl`. | **Берем модульную структуру CachyOS**: она намного чище, читаемее и идеально подходит для синхронизации через Git/Chezmoi. |
| **Noctalia Config** | Почти пустой `config.toml` (`[shell] polkit_agent = true`). | Детальный `config.toml`: темы, обои, позиционирование login_box для lockscreen, параметры баров. | Начинаем с дефолтного `config.toml` CachyOS, подтягивая кастомизации Noctalia (панели, обои, login box) по мере необходимости. |
| **IPC Noctalia в биндах** | Стандартные вызовы. | Полный набор шорткатов через современный IPC v5: `noctalia msg panel-toggle <launcher/clipboard/control-center/session/wallpaper>` + плагин заметок `Mod+Shift+N` (`noctalia/notes:panel`). | **Переносим наши бинды**, так как они настроены под реальное использование всех панелей Noctalia. |
| **Правила окон (Rules)** | Базовый глобальный радиус 20, глобальный blur, простейшее плавающее правило Steam. | **Продвинутые правила**: Nautilus (плавающий оверлей 1200x760, свойства 480x710), File Roller (900x600), Gamescope (полный экран на игровой монитор), VSCodium/Zen/DBeaver (максимизация колонки), PiP (плавающий 480px). | **Переносим наши правила окон** — они избавляют от хаоса при открытии диалогов, браузера и игр. |
| **Раскладка и ввод** | Стандартный us. | `us,ru` с переключением `Alt+Shift` (`grp:alt_shift_toggle`), `track-layout "global"`, touchpad natural-scroll/tap, отключен focus-follows-mouse. | **Переносим наши настройки ввода**. |
| **XWayland & Activation** | Дефолты. | `honor-xdg-activation-with-invalid-serial` (критично для кликов по уведомлениям и таскбару Noctalia), явный `xwayland-satellite`. | **Обязательно переносим** фикс активации токенов для Noctalia. |
| **Лейаут колонок** | Дефолтный скроллинг Niri. | `always-center-single-column = true`, пропорции колонок `1/3, 1/2, 2/3`, дефолтная ширина `1/2`. | **Переносим наши пропорции**, это делает тайлинг аккуратным на одном окне. |

---

## 3. Архитектура конфигурации для двух ThinkPad

Чтобы чисто совместить дефолты CachyOS и наши доработки на двух ноутбуках, используем модульную структуру `cfg/` с отдельным подключением настроек хоста:

```text
~/.config/niri/
├── config.kdl             # Главный вход (подключает cfg/* и host.kdl)
├── host.kdl -> hosts/thinkpad-desktop.kdl  # Симлинк на текущее железо
├── hosts/
│   ├── desktop.kdl        # Мониторы для десктопа (DP-2, HDMI-A-2, ddcutil)
│   ├── thinkpad-t480s.kdl # Экран eDP-1, скейлинг, тачпад
│   └── thinkpad-x1.kdl    # Специфика X1 (разрешение/скейлинг)
└── cfg/
    ├── animation.kdl      # Дефолт CachyOS (или наши slowdown 0.7)
    ├── autostart.kdl      # Запуск noctalia, polkit, xwayland-satellite
    ├── display.kdl        # Общие параметры дисплеев
    ├── input.kdl          # Клавиатура us,ru, Alt+Shift, тачпад
    ├── keybinds.kdl       # Все бинды Niri + вызовы noctalia msg
    ├── layout.kdl         # Центрирование, пропорции 1/3, 1/2, 2/3, gaps
    ├── misc.kdl           # honor-xdg-activation-with-invalid-serial
    └── rules.kdl          # Правила окон (Nautilus, Steam, Gamescope, Zen, Codium)
```

В конце `~/.config/niri/config.kdl` просто добавляется:
```kdl
include "host.kdl"
```

---

## 4. Синхронизация VS Codium (Настройки и Расширения)

В текущей NixOS конфигурации синхронизация VSCodium была устроена императивно через расширение **`zokugun.sync-settings`** и персональный git-репозиторий:

* **Репозиторий настроек:** `git@github.com:dberd/vscode-settings.git`
* **Ветка:** `main`
* **Профиль:** `vscodium`
* **Синхронизируются:** `settings.json`, `keybindings.json`, `snippets/`, список установленных расширений и локальные настройки воркспейсов.

### Скрипт быстрого восстановления VSCodium на CachyOS:
Создайте и выполните скрипт после установки системы:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== 1. Установка VSCodium ==="
paru -S --needed --noconfirm vscodium-bin

echo "=== 2. Настройка связки ключей (gnome-keyring) ==="
mkdir -p "$HOME/.vscode-oss"
ARGV="$HOME/.vscode-oss/argv.json"
if [ ! -f "$ARGV" ]; then
    echo '{"password-store": "gnome-libsecret"}' > "$ARGV"
else
    sed -i 's/"password-store": "basic"/"password-store": "gnome-libsecret"/' "$ARGV"
fi

echo "=== 3. Конфигурация Sync Settings ==="
CFG_DIR="$HOME/.config/VSCodium/User/globalStorage/zokugun.sync-settings"
mkdir -p "$CFG_DIR"
cat > "$CFG_DIR/settings.yml" << 'EOF'
profile: vscodium
repository:
  type: git
  url: git@github.com:dberd/vscode-settings.git
  branch: main
EOF

echo "=== 4. Установка базовых расширений ==="
codium --install-extension zokugun.sync-settings || true
codium --install-extension Noctalia.noctaliatheme || true

echo "=== Готово! ==="
echo "Откройте VSCodium, нажмите Ctrl+Shift+P и выберите 'Sync Settings: Download'."
```

---

## 5. Пошаговый план чистой установки CachyOS на этот же диск

### Шаг 0. Резервное копирование состояния NixOS
Поскольку установка будет производиться на этот же диск:
1. Запушьте все актуальные изменения текущего git-репозитория (`nixos-config`):
   ```bash
   git add .
   git commit -m "chore: save state before migration to CachyOS"
   git push origin main
   ```
2. Скопируйте важные несинхронизированные данные (SSH-ключи из `~/.ssh`, GPG, локальные заметки `~/Notes`, документы) на внешний накопитель или отдельный неформатируемый раздел.

### Шаг 1. Загрузка с ISO CachyOS
1. Скачайте образ **CachyOS Handheld / Desktop (x86-64-v3 или v4)** и запишите на флешку через `dd` или `Ventoy`.
2. Загрузитесь в Live-окружение в режиме UEFI.

### Шаг 2. Разметка диска в Calamares (Установщик CachyOS)
При установке на целевой NVMe накопитель:
* **Схема разметки:**
  * `ESP` (FAT32, точка монтирования `/boot`, размер 1024–2048 МБ, флаги `boot, esp`).
  * `Корень` (Btrfs, точка монтирования `/`).
* **Файловая система:** Обязательно выберите **Btrfs**. 
  * CachyOS автоматически создаст сабволюмы `@`, `@home`, `@snapshots`, `@cache`, `@log`.
  * Установщик автоматически настроит **Snapper** и интеграцию с загрузчиком (Limine или GRUB) для мгновенного отката в случае сбоев.
* **Выбор окружения:** При установке пакетов можно выбрать установку без DE (минимальную) либо выбрать базовый WM, так как Niri и Noctalia будут устанавливаться начисто.

### Шаг 3. Первичная инициализация в CachyOS
После первой загрузки в установленную CachyOS:

1. **Обновление и установка Niri + Noctalia:**
   ```bash
   sudo pacman -Syu
   sudo pacman -S --needed niri xwayland-satellite alacritty ghostty nautilus
   paru -S --needed noctalia-shell-git # или пакет noctalia из репозитория CachyOS
   ```
2. **Клонирование базового репозитория CachyOS для Niri:**
   ```bash
   git clone https://github.com/CachyOS/cachyos-niri-noctalia.git /tmp/cachy-niri
   cp -r /tmp/cachy-niri/etc/skel/.config/niri ~/.config/
   cp -r /tmp/cachy-niri/etc/skel/.config/noctalia ~/.config/
   ```
3. **Накатывание наших проверенных настроек:**
   - В `~/.config/niri/cfg/input.kdl` переносим раскладку `us,ru` и параметры тачпада.
   - В `~/.config/niri/cfg/rules.kdl` добавляем наши правила для Steam, Gamescope, Nautilus, Zen, VSCodium.
   - В `~/.config/niri/cfg/keybinds.kdl` проверяем бинды для Noctalia IPC (`noctalia msg panel-toggle ...`).
   - В `~/.config/niri/cfg/misc.kdl` добавляем `honor-xdg-activation-with-invalid-serial`.
4. **Восстановление VSCodium:**
   - Запустить bootstrap-скрипт из Раздела 4.
5. **Создание первого Btrfs-снапшота:**
   ```bash
   sudo snapper -c root create -d "Clean install with Niri + Noctalia configured"
   ```
