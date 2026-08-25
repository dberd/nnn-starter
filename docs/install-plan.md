# nnn-desktop: установка и устройство конфигурации

Форк [floatdrop/nnn-starter](https://github.com/floatdrop/nnn-starter) (NixOS + Niri + Noctalia),
адаптированный под AMD-десктоп и подготовленный к добавлению второго хоста — ThinkPad T480s.

Документ описывает состояние на момент первой установки: какие решения приняты, почему, и что
делать при повторении на другой машине.

> **Разделы 1 и 3 описывают прошлое.** 25.08.2026 система переехала на NVMe: другой диск,
> другие лейблы разделов, ESP на 2 ГиБ, в меню limine вместо CachyOS — откат на ADATA.
> Актуальная разметка и загрузчик — `hosts/nnn-desktop/disko.nix`, `modules/nixos/boot.nix`
> и [migrate-to-nvme.md](migrate-to-nvme.md). Всё остальное здесь по-прежнему в силе.

---

## 1. Железо и разметка

| | nnn-desktop | nnn-t480s (планируется) |
|---|---|---|
| CPU | AMD Ryzen 7 5700X | Intel Kaby Lake R |
| GPU | Radeon RX 7700/7800 XT (Navi 32), RADV | Intel iGPU, iHD |
| RAM | 16 GiB | — |
| Мониторы | `HDMI-A-2` 1920x1080@60 @1.0 + `DP-2` 2560x1440@75 @**1.2** | `eDP-1` |
| Игры | да | **нет** |

Диск `/dev/sda` (ADATA SU650, 447G), UEFI:

```
sda1  1G    vfat   /boot   ESP
sda2  446G  btrfs  сабволюмы @ @home @nix @log @snapshots
```

Опции btrfs: `compress=zstd:1,noatime,ssd,discard=async`.
Swap-раздела нет — 16 GiB RAM + `zramSwap`; гибернация поэтому недоступна.

```sh
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart ESP fat32 1MiB 1025MiB
parted -s /dev/sda set 1 esp on
parted -s /dev/sda mkpart nixos btrfs 1025MiB 100%
mkfs.fat -F32 -n NIXBOOT /dev/sda1
mkfs.btrfs -f -L nixos /dev/sda2
```

---

## 2. Как ставилось

Установка велась **из работающей CachyOS на другом диске** (nvme), без загрузочной флешки —
официально поддерживаемый путь «Installing from another Linux distribution».

Ключевой приём: **store сразу на целевом диске**.

```sh
sudo mount --bind /mnt/nix /nix     # ДО установки Nix
curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
```

Это решает две задачи разом: на системном разделе CachyOS оставалось всего 42 ГБ (замыкание —
около 18 ГБ), и `nixos-install` не копирует замыкание между дисками, потому что `/nix` и
`/mnt/nix` — один и тот же каталог.

Сборка и установка:

```sh
sudo nix build --print-build-logs \
  --option extra-substituters "https://niri.cachix.org https://noctalia.cachix.org" \
  --option extra-trusted-public-keys "niri.cachix.org-1:… noctalia.cachix.org-1:…" \
  /home/sundial/nixos-config#nixosConfigurations.nnn-desktop.config.system.build.toplevel

sudo env PATH=… nixos-install --root /mnt --flake …#nnn-desktop --no-channel-copy
sudo nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/sw/bin/passwd sundial'
```

### Грабли, на которые наступили

- **`sudo` сбрасывает PATH** (`secure_path`), и `nixos-install` не находит `nix`. Нужен
  `sudo env PATH=…`. В fish рецепт из мануала `sudo PATH="$PATH" …` не работает: `$PATH` там
  список, и он развернётся в несколько отдельных аргументов.
- **Кеши cachix игнорируются у недоверенного пользователя.** В `nix.conf` нет `trusted-users`,
  поэтому `--option extra-substituters` действует только из-под root — иначе noctalia
  собирается из исходников около часа.
- **Перезагрузка посреди процесса всё размонтирует.** Ни `/mnt`, ни bind-mount не в fstab; после
  ребута `/nix` превращается в пустой каталог на диске CachyOS и `nix` пропадает из PATH.
  Лечится повторным монтированием в том же порядке; ничего не теряется.
- `nixos-generate-config` пишет только `subvol=`, **теряя остальные опции монтирования**. Они
  восстановлены в `hosts/nnn-desktop/default.nix`, а не в сгенерированном файле, который
  перезапись затрёт.
- `neededForBoot` для `/var/log` и `/nix` **не нужен** — оба уже входят в `pathsNeededForBoot`.
- `passwd` внутри `nixos-enter` не находится: PATH в chroot пуст, нужен абсолютный путь.

---

## 3. Загрузчик

На машине три ESP и уже стоял limine:

| Раздел | PARTUUID | Что |
|---|---|---|
| `nvme0n1p1` 4G | `981dda21-…` | ESP CachyOS + его limine |
| `sda1` 1G | `7bffd8d6-…` | ESP NixOS |
| `sdb1` 100M | `1fef5bef-…` | ESP Windows 10 |

**Решение:** NixOS ставит свой limine на свой ESP и никогда не пишет в чужие. Основным пока
остаётся limine с nvme; в нём есть чейнлоад-запись на NixOS. Меню NixOS при этом уже содержит
записи на CachyOS и Windows (`extraEntries` в `modules/nixos/boot.nix`), так что когда nvme будет
снесён, останется только поднять NVRAM-запись NixOS наверх.

Синтаксис (сверено с актуальным limine `CONFIG.md`): протокол называется **`efi`** — `chainload`
из примера в модуле nixpkgs устарел и текущим limine не принимается. `image_path` — алиас `path`.
Ресурс `guid()`/`uuid()` принимает как UUID ФС, так и GPT-GUID раздела.

### Что пришлось чинить руками

Установщик limine **переиспользовал слот `Boot0001`**, где раньше была именованная запись limine
CachyOS, и встал первым в `BootOrder`. Восстановление:

```sh
sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L "Limine (CachyOS)" -l '\EFI\LIMINE\LIMINE_X64.EFI'
```

`limine-update` на стороне CachyOS **не** перепривязал свою auto-generated запись со стёртого
раздела, поэтому она правилась вручную в `/boot/limine.conf`:

```
/NixOS (ADATA)
protocol: efi
path: uuid(7bffd8d6-d1f6-4e83-a6f6-c9035367f86d):/EFI/limine/BOOTX64.EFI
```

Обрати внимание: limine от NixOS ставится как `BOOTX64.EFI`, а не `limine_x64.efi` — поменять
только UUID недостаточно. `limine-enroll-config` не нужен: `ENABLE_ENROLL_LIMINE_CONFIG` не задан.

> При каждом `nixos-rebuild switch` установщик снова лезет в NVRAM. Если надоест —
> `boot.loader.efi.canTouchEfiVariables = false` + `efiInstallAsRemovable = true`, тогда NixOS
> перестанет трогать NVRAM совсем и будет грузиться только чейнлоадом.

---

## 4. Устройство конфигурации

```
flake.nix                       mkHost -> nixosConfigurations.{nnn-desktop,nnn-t480s}
hosts/common/                   локаль, раскладка us,ru, stateVersion
hosts/nnn-desktop/              hostName, TZ, опции btrfs, hardware-configuration.nix, local.nix
modules/nixos/
  hardware/amd-desktop.nix      amdgpu, radeonsi, микрокод AMD
  hardware/intel-laptop.nix     бывший hardware.nix апстрима — готов для T480s
  gaming.nix                    Steam/gamescope/lutris/heroic — импортируется ТОЛЬКО десктопом
  vpn.nix                       throne + snx-rs + split-routing
  dev.nix                       nix-ld
  boot.nix                      limine + чейнлоад ADATA/Windows
modules/home/
  fish.nix                      замена zsh.nix
  dev.nix                       docker-clients, dbeaver, node, dotnet SDK
  ssh.nix, git.nix              две git-идентичности, libsecret
  files/docker-dev.yml          локальный dev-стек
```

Хост выбирает ровно один модуль из `hardware/`; всё машинно-зависимое — в `hosts/<host>/local.nix`.
Добавить T480s = создать `hosts/nnn-t480s/{default,local}.nix` + hardware-config и одну строку в
`flake.nix`; `gaming.nix` он просто не импортирует.

### Принятые решения

| Тема | Решение | Почему |
|---|---|---|
| Шелл | fish вместо zsh | автодополнения, подсветка, история — нативные, плагины не нужны. starship оставлен: у fish свой промпт, но Stylix его не темит |
| Шрифт | JetBrains Mono NF, Maple Mono NF в fallback | fontconfig берёт второй для отсутствующих глифов |
| GUI-редактор | mime-дефолт → VSCodium; Zed установлен, но не дефолт | `$EDITOR` в терминале остаётся neovim |
| Заметки | Trilium вместо Logseq | пакет logseq заморожен на файловой ветке 0.10.x и прибит к EOL Electron 39.8.10. У SiYuan синхронизация через S3/WebDAV — платная PRO-фича, у Trilium свой sync-сервер бесплатный (есть модуль `services.trilium-server`) |
| Фаервол | штатный `networking.firewall` | `ufw` отсутствует в nixpkgs целиком; плюс — работают `openFirewall` в модулях |
| Мониторы | per-output `local.monitors` | у панелей разные разрешения И разные масштабы, скаляр `monitorScale` из апстрима это не выражает |
| nixpkgs | unstable | niri и noctalia движутся быстро; niri/noctalia намеренно не `follows` наш nixpkgs, иначе теряется попадание в их cachix |

### Порталы

`xdg-desktop-portal-gnome` обязателен для screencast; начиная с версии 47 он же использует
**Nautilus как файловый диалог** — поэтому `FileChooser = gnome`, а не `gtk`. Secret-портал даёт
`gnome-keyring` (он же бэкенд для `git-credential-libsecret`). `NIXOS_OZONE_WL=1` включает
нативный Wayland для Electron-приложений. **`GDK_BACKEND` глобально ставить нельзя** — ломает
screencast.

### Секреты

В репозитории их нет и быть не должно:

- `/etc/snx-rs/snx-rs.conf` — логин и пароль корпоративного VPN, создаётся руками, режим `0600`;
- `~/.ssh/id_ed25519` — копируется руками;
- пароль GitLab уходит в gnome-keyring при первом `git push`.

Целевое состояние — `sops-nix`.

---

## 5. Проверка после установки

```sh
niri msg outputs                     # оба монитора со своими scale
vainfo | head                        # radeonsi
vulkaninfo --summary                 # RADV, Navi 32
busctl --user list | grep portal     # .Desktop / .Gnome / .Gtk
echo $SHELL                          # fish
git -C ~/Work/Repos/<any> config user.email    # рабочий адрес через includeIf
ssh -T git@github.com
systemctl status snx-rs snx-vpn-routing
ip rule                              # правила 4900+/5100 на месте
docker compose -f ~/docker/docker-dev.yml up -d && psql -h localhost -U postgres
steam && gamescope -- glxgears
```

File-picker проверяется нагляднее всего так: «Открыть файл» в chromium должен показать **окно
Nautilus**, а не GTK-диалог.

---

## 6. Что осталось

- Стереть ADATA, когда система на NVMe себя покажет, и убрать за ней хвосты:
  запись `/NixOS (ADATA, old disk)` из `modules/nixos/boot.nix` и `Limine (ADATA)`
  из NVRAM (`efibootmgr -b 0003 -B`). Диск после этого — под библиотеку Steam.
- `hosts/nnn-t480s/` по схеме из раздела 4.

Закрыто по ходу дела:

- ~~Убрать Nix с CachyOS~~ — диск стёрт целиком 25.08.2026.
- ~~Перенести с nvme `~/.claude`, `~/Work/vscode-settings`~~ — перенесено, диск сверен
  целиком (migrate-to-nvme.md §0).
- ~~`sops-nix` для `snx-rs.conf`~~ — `modules/nixos/secrets.nix`, три секрета.
- ~~`disko`~~ — `hosts/nnn-desktop/disko.nix`, им же и размечался NVMe.
- ~~Проверить `default_entry`~~ — да, limine считает группу `/+NixOS default profile`
  отдельным пунктом: модуль ставит `default_entry: 2` (или `3`, если у поколения есть
  специализации), и это указывает на самое свежее поколение. Плюс теперь включён
  `remember_last_entry: yes`.
