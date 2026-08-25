# Переезд nnn-desktop с ADATA на NVMe

Система живёт на ADATA SU650 (`sda`, 447 ГБ), а 1 ТБ KINGSTON SNV3S (`nvme0n1`) занят
CachyOS, который больше не нужен. Цель — перенести NixOS на NVMe целиком, ADATA
на пару недель оставить загружаемым запасом, потом отдать под игры.

Документ рассчитан на выполнение подряд, сверху вниз, из работающей системы на ADATA.
Загрузочная флешка не нужна.

---

## 0. Состояние до переезда

```
sda        447G  ADATA SU650      ← NixOS сейчас
├─sda1       1G  vfat  ESP        partlabel ESP    → /boot
└─sda2     446G  btrfs nixos      partlabel nixos  → @ @home @nix @log @snapshots
sdb        480G  KINGSTON SA400   ← Windows 10, не трогаем
nvme0n1    932G  KINGSTON SNV3S   ← CachyOS, будет стёрт целиком
├─nvme0n1p1  4G  vfat             ESP CachyOS, GUID 981dda21-…
└─nvme0n1p2 928G btrfs            корень CachyOS
```

Занято на ADATA 89 ГБ, из них 76 ГБ — библиотека Steam.

### Что забрать с NVMe ДО стирания

Проверено 25.08.2026; всё остальное на том диске либо уже перенесено, либо генерируется
заново (`.cargo`, `go`, `fvm`, `.pub-cache`, `.vscode`, `.net`, `.templateengine`).

| Что | Размер | Решение |
|---|---|---|
| `~/Pictures/Wallpapers` | 38 МБ | **сделано** — 5 новых обоев лежат в `themes/wallpapers` |
| `~/Work/Dumps` | 3.5 ГБ | **сделано** — в `~/Work/Dumps` |
| `~/PersonalProjects`, `~/claude-chat-export.md` | 64 КБ | **сделано** |
| `~/Games` | **56 ГБ** | не-Steam игры: ShadPS4, Amnesia, Elden Ring Reforged, PA TITANS. Нужно решить |
| `~/.thunderbird` | 689 МБ | профиль почты; в конфиге NixOS thunderbird нет. Нужно решить |

Монтировать источник только на чтение:

```sh
sudo mkdir -p /mnt/cachy
sudo mount -o ro,subvolid=5 \
  /dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7283A9CB50-part2 /mnt/cachy
# домашний каталог CachyOS: /mnt/cachy/@home/sundial
```

---

## 1. Правки конфигурации (делаются заранее, применяются НЕ на ADATA)

### 1.1 `hosts/nnn-desktop/disko.nix`

```diff
-    device = "/dev/disk/by-id/ata-ADATA_SU650_2K2020015098";
+    device = "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7283A9CB50";
@@ ESP
-          label = "ESP";
+          label = "nixos-esp";
           start = "1M";
-          end = "1025M";
+          end = "2049M";
@@ nixos
-          label = "nixos";
+          label = "nixos-root";
```

Почему лейблы меняются. Disko собирает `fileSystems.*.device` из **partlabel**, и сейчас
в `/etc/fstab` стоит `/dev/disk/by-partlabel/nixos`. Если новый диск получит те же имена,
пока ADATA подключён, `by-partlabel/nixos` будет указывать то на один диск, то на другой —
udev выбирает произвольно. Загрузка со старого корня в такой схеме — вопрос везения.
Уникальные имена снимают вопрос полностью и позволяют держать ADATA как запасной вход.

Btrfs-лейбл (`-L nixos`) можно не трогать: по `by-label` в этой конфигурации ничего
не монтируется.

> **Не запускать `nixos-rebuild switch` на ADATA после этой правки.** Живая система
> сразу перегенерирует fstab на `by-partlabel/nixos-root`, которого на ADATA нет,
> и следующая загрузка провалится в initrd.

### 1.2 `modules/nixos/boot.nix`

Убрать чейнлоад CachyOS (его ESP исчезнет) и поставить вместо него запись на старый диск —
это и есть путь отката на время обкатки:

```diff
-      /CachyOS (NVMe)
-          comment: chainloads the limine on the CachyOS ESP
+      /NixOS (ADATA, старый диск)
+          comment: чейнлоад limine со старого ESP; удалить, когда ADATA уйдёт под игры
           protocol: efi
-          path: guid(981dda21-1797-4914-bda8-f62c5d5e6d7c):/EFI/LIMINE/LIMINE_X64.EFI
+          path: guid(7bffd8d6-d1f6-4e83-a6f6-c9035367f86d):/EFI/limine/BOOTX64.EFI
```

Запись Windows (`1fef5bef-…`, `sdb1`) остаётся как есть. Схему дисков в шапке модуля
тоже обновить.

### 1.3 Коммит

```sh
cd ~/nixos-config && git add -A && git commit -m "Move nnn-desktop to the NVMe"
```

Устанавливаемая система должна ссылаться на чистое дерево — иначе `nixos-install`
ругается на dirty git tree, а `nixos-rebuild` на новом диске будет собирать не то,
что закоммичено.

---

## 2. День переезда

### Шаг 1. Разметка NVMe

Скрипт собирается из своего же flake, поэтому версия disko гарантированно совпадает
с версией модуля в `flake.lock`:

```sh
nix build ~/nixos-config#nixosConfigurations.nnn-desktop.config.system.build.diskoScript \
  -o /tmp/disko-nvme
sudo /tmp/disko-nvme/bin/disko          # destroy + format + mount, СТИРАЕТ NVMe целиком
```

Проверка — должны появиться новые лейблы и смонтированное дерево в `/mnt`:

```sh
lsblk -o NAME,SIZE,PARTLABEL,FSTYPE,MOUNTPOINT /dev/nvme0n1
findmnt -R /mnt
```

### Шаг 2. Ключ sops — ДО установки

`nixos-install` прогоняет activation, а в нём `sops-install-secrets`. Без ключа этот
шаг падает и установка обрывается.

```sh
sudo mkdir -p /mnt/var/lib/sops-nix
sudo install -m600 -o root -g root /var/lib/sops-nix/key.txt /mnt/var/lib/sops-nix/key.txt
```

### Шаг 3. Установка

Замыкание уже собрано на ADATA — качать нечего, установка сводится к копированию store:

```sh
sudo nixos-install --root /mnt --flake ~/nixos-config#nnn-desktop --no-channel-copy
```

В конце установщик спросит **пароль root**.

### Шаг 4. Пароль пользователя

Пароля `sundial` нет ни в одном `.nix` (`modules/nixos/users.nix` объявляет только
`isNormalUser`), а `/etc/shadow` со старого диска не переносится. Без этого шага
в greeter войти нечем:

```sh
sudo nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/sw/bin/passwd sundial'
```

### Шаг 5. Домашний каталог

Снимок нужен, чтобы не копировать живые sqlite Zen и Telegram:

```sh
sudo btrfs subvolume snapshot -r /home /.snapshots/migrate

sudo rsync -aHAX --numeric-ids --info=progress2 \
  --exclude '.local/share/Steam/' \
  --exclude '.cache/' \
  /.snapshots/migrate/sundial/ /mnt/home/sundial/

sudo btrfs subvolume delete /.snapshots/migrate
```

Около 16 ГБ вместо 90: библиотека Steam (76 ГБ) остаётся на ADATA и подключится второй
Steam Library, когда диск будет переразмечен.

`-H/-A/-X` сохраняют жёсткие ссылки, ACL и xattrs — на btrfs это бесплатно и убирает
целый класс сюрпризов при копировании кэшей и архивов.

### Шаг 6. Тома Docker

826 МБ, в них `docker_postgres_data` и `docker_redis_data` — те самые локальные базы,
на которые смотрят конфиги отладки Calendar и Committees (пароль `1234`):

```sh
sudo systemctl stop docker.service docker.socket
sudo rsync -aHAX --numeric-ids /var/lib/docker/ /mnt/var/lib/docker/
```

Пропустить = получить пустые базы; `docker compose up -d` создаст тома с нуля, дампы
для наполнения лежат в `~/Work/Dumps`.

### Шаг 7. NVRAM

`efibootmgr` в системе не установлен, поэтому через `nix shell`:

```sh
nix shell nixpkgs#efibootmgr -c sudo efibootmgr -v
```

Установщик limine создал запись для нового ESP. Нужно:

1. удалить запись `Limine (CachyOS)` — раздел, на который она ссылается, стёрт:
   `… efibootmgr -b <NNNN> -B`
2. поставить новую запись первой, старую NixOS второй, Windows следом:
   `… efibootmgr -o <новый>,<ADATA>,<Windows>`

### Шаг 8. Перезагрузка

```sh
sudo reboot
```

В меню limine нового диска будут: NixOS (поколения), `/NixOS (ADATA, старый диск)`,
`/Windows 10`.

---

## 3. Состояние после переезда

### Диски

```
nvme0n1    932G  ← NixOS
├─nvme0n1p1  2G  vfat   partlabel nixos-esp   → /boot   (limine, ESP)
└─nvme0n1p2 930G btrfs  partlabel nixos-root  → @ / , @home /home, @nix /nix,
                                                 @log /var/log, @snapshots /.snapshots
sda        447G  ← старый NixOS, загружаемый запас; ~/.local/share/Steam на месте
sdb        480G  ← Windows 10
```

Опции монтирования btrfs: `compress=zstd:1,noatime,ssd,discard=async`.
Раздела подкачки нет — 16 ГБ RAM + `zramSwap`, гибернация недоступна.

### Система

| | |
|---|---|
| hostname | `nnn-desktop` |
| stateVersion | `25.05` (и системный, и home-manager) |
| часовой пояс | `Europe/Moscow` |
| ядро/канал | nixpkgs unstable, flake `~/nixos-config` |
| DE | niri + noctalia, greeter noctalia на `DP-2` |
| мониторы | `HDMI-A-2` 1920×1080@60 scale 1.0 · `DP-2` 2560×1440@75 scale 1.2 |
| загрузчик | limine на своём ESP, чейнлоад Windows и старого NixOS |

### Пользователи

| Пользователь | Что |
|---|---|
| `root` | пароль задан на шаге 3. Логин по ssh невозможен — sshd в конфигурации нет |
| `sundial` | uid **1000**, shell fish, группы `wheel networkmanager video audio input docker`, sudo **без пароля**, пароль задан на шаге 4 |

Членство в `docker` root-эквивалентно — это осознанный размен, тот же, что и с
беспарольным sudo (см. комментарий в `modules/nixos/docker.nix`).

### Секреты

`/var/lib/sops-nix/key.txt` (age, `root:root 0600`) расшифровывает `secrets/secrets.yaml`
в activation. Три секрета раскладываются симлинками в домашний каталог:

```
~/.config/snx-rs/snx-rs.conf     → /run/secrets/snx-rs-conf
~/.ssh/id_ed25519_github_dberd   → /run/secrets/ssh-github
~/.ssh/id_ed25519_gitlab_efko    → /run/secrets/ssh-gitlab
```

Отдельного юнита у sops-nix нет — если что-то пошло не так, смотреть `journalctl -b`
по activation, а не `systemctl status sops-nix`.

### Что переехало как есть

Throne (подписка, ноды, TUN), Zen, Helium, Telegram, Trilium (`~/.local/share/trilium-data`),
`~/.claude`, `~/Work` целиком, `~/Notes`, `~/Documents`, dumps. Переустанавливать
и перенастраивать ничего не нужно.

### Что осталось на ADATA

Библиотека Steam (76 ГБ) и полная копия системы на момент переезда. Диск остаётся
загружаемым через запись `/NixOS (ADATA, старый диск)` в меню limine.

Когда новая система подтверждена (неделя-другая):

```sh
sudo wipefs -a /dev/disk/by-id/ata-ADATA_SU650_2K2020015098
```

…и убрать запись отката из `modules/nixos/boot.nix`, а её NVRAM-запись — через
`efibootmgr -B`.

---

## 4. Проверка

```sh
findmnt -no SOURCE /                      # /dev/nvme0n1p2 — НЕ sda2
lsblk -o NAME,PARTLABEL,MOUNTPOINT        # nixos-root / nixos-esp
ls -l ~/.ssh/id_ed25519_github_dberd ~/.config/snx-rs/snx-rs.conf   # → /run/secrets/*
nix shell nixpkgs#efibootmgr -c sudo efibootmgr    # NixOS первым, Windows на месте, CachyOS нет

niri msg outputs                          # оба монитора со своими scale
systemctl status snx-rs snx-vpn-routing
snxctl connect && git ls-remote https://gitlab.sddt.efko.ru/committees/backend.git | head -1
curl -s https://ifconfig.me               # Throne на месте

dotnet --list-sdks                        # 6.x 8.x 9.x 10.x
dotnet --list-runtimes | grep AspNetCore  # включая 7.0.x
docker compose -f ~/docker/docker-dev.yml up -d
docker compose -f ~/docker/docker-dev.yml ps       # postgres, redis, memgraph, memgraph-lab
psql -h localhost -U postgres -c '\l'
cd ~/Work/Repos/Backend/notifications && dotnet build Notifications.sln
cd ~/Work/Repos/Frontend/Calendar/frontend && node -v   # v16.x от fnm по .nvmrc
```

Отдельно: в VSCodium открыть `~/Work/Repos/Backend/notifications` и нажать F5 —
задача `build` должна отработать, отладчик подняться на 5299.

---

## 5. Если что-то пошло не так

До шага 8 старая система не изменена вообще: перезагрузка возвращает на ADATA.
После — выбрать в меню limine `/NixOS (ADATA, старый диск)`; там всё ровно в том
состоянии, в каком было в момент снимка.

Единственная точка невозврата — шаг 1: он стирает CachyOS. К этому моменту всё нужное
с того диска должно быть уже забрано (раздел 0).
