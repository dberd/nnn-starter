# Переезд nnn-desktop с ADATA на NVMe

Система живёт на ADATA SU650 (`sda`, 447 ГБ), а 1 ТБ KINGSTON SNV3S (`nvme0n1`) занят
CachyOS, который больше не нужен. Цель — перенести NixOS на NVMe целиком, ADATA
на пару недель оставить загружаемым запасом, потом отдать под игры.

Документ рассчитан на выполнение подряд, сверху вниз, из работающей системы на ADATA.
Загрузочная флешка не нужна.

---

## 0. Состояние до переезда

```
sdb        447G  ADATA SU650      ← NixOS сейчас
├─sdb1       1G  vfat  ESP        partlabel ESP    → /boot
└─sdb2     446G  btrfs nixos      partlabel nixos  → @ @home @nix @log @snapshots
sda        480G  KINGSTON SA400   ← Windows 10, не трогаем
nvme0n1    932G  KINGSTON SNV3S   ← CachyOS, будет стёрт целиком
├─nvme0n1p1  4G  vfat             ESP CachyOS, GUID 981dda21-…
└─nvme0n1p2 928G btrfs            корень CachyOS
```

**Буквы дисков не постоянны.** До того как вынули флешку EndeavourOS, ADATA был `sda`,
а Windows — `sdb`; после — поменялись местами. Ни одна команда ниже не называет диск
по `sd*`: только `by-id` (disko) и GPT-GUID (limine). Проверять глазами `lsblk` перед
запуском — обязательно, но в командах эти буквы не появляются намеренно.

Занято на ADATA 89 ГБ, из них 76 ГБ — библиотека Steam.

### Что забрать с NVMe ДО стирания — ничего

Диск сверен целиком 25.08.2026 (`rsync --dry-run --ignore-existing` по всему хоуму
CachyOS против нашего). Перенесено:

| Что | Размер | |
|---|---|---|
| `~/Pictures/Wallpapers` | 38 МБ | 5 новых обоев — в `themes/wallpapers`, под git |
| `~/Work/Dumps` | 3.5 ГБ | в `~/Work/Dumps` |
| `~/PersonalProjects`, `~/claude-chat-export.md` | 64 КБ | |
| `~/docker/docker-dev.yml` | — | версия с memgraph — в `modules/home/files/` |
| сейвы Elden Ring Reforged | 802 МБ | уже были здесь, сверено по md5, включая 25 бэкапов ERR |

Осознанно **не** переносится:

| Что | Размер | Почему |
|---|---|---|
| Steam-библиотека | **466 ГБ** | BG3, Elden Ring, Arc Raiders, Ready Or Not, Nightreign, Helldivers 2… — скачаем заново |
| `~/Games` | 56 ГБ | ShadPS4, Amnesia, Elden Ring Reforged, PA TITANS |
| сейвы BG3 / BeamNG / shadPS4, база Anytype | 920 МБ | не нужны |
| `~/.thunderbird` | 689 МБ | пакет есть в конфиге, профиль не нужен |
| `Documents/Vaults` | 41 МБ | дубли того, что уже в `~/Notes` как git-репозитории |
| расширения Zen | — | пять из десяти вернулись через nix, остальные не нужны |

Всё прочее на том диске — кэши и сборочный мусор: `.angular` 3.7 ГБ, `node_modules`,
`bin`/`obj`, `umu` 1.7 ГБ, `Trash` 1.5 ГБ, `workspace-setup.zip` 1.5 ГБ (распакованная
копия есть), `.config/Code` 977 МБ, старый профиль zen, `.cargo`, `go`, `fvm`,
`.pub-cache`, `.net`, `.templateengine`.

Если всё же понадобится посмотреть на диск до стирания — монтировать только на чтение:

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

> **Не запускать `nixos-rebuild switch` на ADATA с этой правкой.** Живая система
> сразу перегенерирует fstab на `by-partlabel/nixos-root`, которого на ADATA нет,
> и следующая загрузка проваливается в initrd.
>
> Это не гипотеза: 25.08 правку закоммитили в рабочую ветку, следом сделали
> пересборку ради расширений Zen — и поколение 62 не загрузилось ровно так.
> Спасло меню limine: предыдущее поколение стартовало нормально. Поэтому правка
> и вынесена в отдельную ветку (§1.3).

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

Запись Windows (`1fef5bef-…`, сейчас `sda1`) остаётся как есть. Схему дисков в шапке модуля
тоже обновить.

### 1.3 Статус: правки применены

Обе лежат в рабочей ветке, коммит **`82b62b4`** («Move nnn-desktop to the NVMe»),
вместе с `remember_last_entry: yes` в `extraConfig`. Ветка `move-to-nvme` (`7ad3a4c`)
осталась как след того, где они жили, пока переезд был в планах.

С этого момента **`nixos-rebuild switch` на ADATA запрещён** — см. врезку выше.
Проверять конфигурацию только сборкой, без активации:

```sh
nix build ~/nixos-config#nixosConfigurations.nnn-desktop.config.system.build.toplevel \
  -o /tmp/nvme-system
```

Замыкание уже собрано этой командой, так что `nixos-install` ниже сведётся
к копированию store — сеть на шаге 3 не нужна.
---

## 2. День переезда

### Шаг 1. Разметка NVMe

Скрипт собирается из своего же flake, поэтому версия disko гарантированно совпадает
с версией модуля в `flake.lock`:

```sh
nix build ~/nixos-config#nixosConfigurations.nnn-desktop.config.system.build.diskoScript \
  -o /tmp/disko-nvme
sudo /tmp/disko-nvme                   # destroy + format + mount, СТИРАЕТ NVMe целиком
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

Состояние до переезда (снято 25.08). Обрати внимание на `BootCurrent`:

```
BootCurrent: 0002                     ← грузимся ЧЕРЕЗ limine с NVMe, он чейнлоадит наш NixOS
BootOrder:   0002,0001,0019,0000,0008,000D

0002* Limine (CachyOS)   NVMe  981dda21   → удалить, раздел стёрт
0019* UEFI OS            NVMe  981dda21   → удалить, туда же
0008  ubuntu             sda1  1fef5bef   → удалить, такого загрузчика там давно нет
0001* Limine             ADATA 7bffd8d6   → оставить: это путь отката
0000* Windows Boot Manager sda1 1fef5bef  → оставить
000D  Hard Drive         BBS-список       → не трогать
```

Порядок действий:

1. **Проверить, что `0001` цел.** Установщик limine однажды уже переиспользовал
   именно этот слот (`docs/install-plan.md` §3), а сейчас в нём запись на ADATA.
   Если её затёрло — пересоздать:
   ```sh
   … efibootmgr -c -d /dev/disk/by-id/ata-ADATA_SU650_2K2020015098 -p 1 \
       -L "Limine (ADATA)" -l '\EFI\limine\BOOTX64.EFI'
   ```
2. Удалить мёртвые записи: `… efibootmgr -b 0002 -B`, `-b 0019 -B`, `-b 0008 -B`.
3. Порядок — новый NixOS, ADATA, Windows:
   `… efibootmgr -o <новый>,0001,0000`

Пункта «настройки UEFI» в меню не будет: у limine 12.3.3 такого протокола нет
(валидные — `linux`, `limine`, `multiboot`, `multiboot2`, `efi`, `efi_boot_entry`,
`bios`), а NVRAM-записи для setup эта плата не заводит. Из системы то же самое
делает `systemctl reboot --firmware-setup`.

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

---

## 6. Как всё прошло (25.08.2026)

Переезд выполнен целиком из работающей системы на ADATA, флешка не понадобилась.
Шаги 1–8 отработали как написано; ниже — то, чего в плане не было.

### `/boot` вышел вдвое меньше заказанного

Disko создал раздел на 2 ГиБ, а `mkfs.vfat` разметил на нём файловую систему на 1 ГиБ:

```
$ lsblk -b -o SIZE /dev/nvme0n1p1 → 2147484160   (2 ГиБ, раздел)
$ df -B1 --output=size /boot      → 1071628288   (1 ГиБ, ФС)
$ fsck.fat -n -v                  → 2097152 sectors total
```

Раздел при этом размечен верно — расходится именно загрузочный сектор FAT. Лечится
пересозданием ФС; содержимое `/boot` целиком генерируемое, терять нечего:

```sh
sudo umount /boot
sudo mkfs.vfat -F 32 -n NIXBOOT /dev/disk/by-partlabel/nixos-esp
sudo mount /boot
sudo /run/current-system/bin/switch-to-configuration boot
```

После этого — 4194304 секторов, 2.0 ГиБ, меню и NVRAM-запись на месте, дублей
установщик не создал. **Проверять `df -h /boot` сразу после disko**, а не после того,
как накопится десяток поколений и место кончится.

### Скрипт disko не запускается через симлинк `-o`

`sudo /tmp/disko-nvme` отвечает `sudo: unable to execute: Permission denied`.
Выходной путь — сам исполняемый файл, а не каталог с `bin/`, и sudo спотыкается
о симлинк. Запускать по разрешённому пути:

```sh
sudo "$(readlink -f /tmp/disko-nvme)"
```

### NVRAM после установки

Установщик limine слот `Limine (ADATA)` не тронул — в отличие от первой установки,
описанной в `install-plan.md` §3. Записи CachyOS (`0002`) и `UEFI OS` (`0019`) исчезли
сами вместе с разделами, которые их держали. Итог без ручного вмешательства:

```
BootCurrent: 0001
BootOrder:   0001,0003,0000,0004,0005
0001* Limine           NVMe  1126122a-…   ← новая система
0003* Limine (ADATA)   ADATA 7bffd8d6-…   ← откат
0000* Windows Boot Manager                 
0004* ubuntu                               ← мусор, можно снести: efibootmgr -b 0004 -B
```

### Проверено на новой системе

`/` и `/home` на `nvme0n1p2`, секреты sops расшифрованы (три симлинка в `/run/secrets`),
Throne с TUN поднят, snx-rs и snx-vpn-routing активны, оба монитора со своими масштабами,
четыре контейнера dev-стека подняты вместе с томами (2.9 ГБ, `postgres_data` на месте),
.NET 6/8/9/10, Node 16 через fnm, `nixos-rebuild switch` собирает поколение 2.

Занято 26 ГБ из 930.

---

## 7. Правки меню limine (28.08.2026)

Три вещи, всплывшие через три дня после переезда.

### Windows 10 не грузился из меню

Путь в записи был `/EFI/MICROSOFT/BOOT/BOOTMGFW.EFI` — заглавными, как его пишет
собственная NVRAM-запись прошивки (`0000* Windows Boot Manager`). Прошивке всё равно:
её FAT-драйвер регистронезависим по спецификации UEFI. Драйверу limine — нет.

В `common/fs/fat32.s2.c` длинные имена сравниваются через `strcmp`, а
`case_insensitive_fopen` включается только пока limine ищет собственный конфиг. На
диске каталог называется `Microsoft` — девять символов, короткого 8.3-имени у него
нет, так что и запасного пути для сравнения не остаётся. Запись просто не
резолвилась. Сейчас путь записан ровно так, как лежит на диске:
`/EFI/Microsoft/Boot/bootmgfw.efi`.

### Меню запоминало прошлый выбор

`remember_last_entry: yes` в `extraConfig` убран. В `common/menu.c` эта переменная
(EFI-переменная `LimineLastBootedEntry`) читается *после* `default_entry` и
перекрывает её, поэтому меню всегда возвращалось на то, что выбрали в прошлый раз.
Без неё работает `default_entry: 2`, который генерирует модуль NixOS, — это верхний
пункт списка, самое свежее поколение.

Сама EFI-переменная осталась в NVRAM, но её больше никто не читает.

### Поколения ADATA переехали в это меню

Было: пункт `/NixOS (ADATA, старый диск)` чейнлоадил limine на ESP ADATA, то есть
открывал второе меню поверх первого. Единственная причина, по которой то limine
вообще требовалось, — limine не умеет btrfs и не может достать ядро с `sdb2`
напрямую; ядро обязано лежать на FAT.

Ядро и initrd (6.18.37, 80 МБ на все десять поколений — они различаются только
`init=`) скопированы на ESP NVMe:

```sh
sudo mkdir -p /boot/adata-legacy
sudo cp /mnt/adata-esp/limine/kernels/* /boot/adata-legacy/
```

Не в `/boot/limine`: `limine-install.py` обходит этот каталог и удаляет всё, что
записал не он сам, — файлы исчезли бы на первом же `nixos-rebuild switch`.

Теперь `/NixOS (ADATA, old disk)` — обычная директория с десятью подпунктами
`protocol: linux` прямо в этом меню. Список поколений и store-пути прибиты вручную
в `modules/nixos/boot.nix`: старая система больше не пересобирается, генерировать
нечего.

Поколения 1–52 в `/nix/var/nix/profiles` на sdb2 есть, но их ядра на ESP никогда не
попадали, поэтому в списке только десять — ровно те, что держало limine ADATA
(у него тоже `maxGenerations = 10`). Поколения 62 нет и там: `system-62-link`
не существует.

Fstab старой системы монтирует по `by-partlabel/nixos` и `by-partlabel/ESP`, а NVMe
использует `nixos-root`/`nixos-esp`, — пересечения нет, эти пункты действительно
грузят старый диск.

limine на ESP ADATA и запись NVRAM `0003* Limine (ADATA)` пока не тронуты: пока
новые пункты не проверены перезагрузкой, это единственный запасной вход. Когда
проверятся — сносить.

### `ubuntu` в NVRAM

Запись возвращалась после каждого удаления. Причина — не сама NVRAM, а остатки
Ubuntu на ESP **Windows** (`sda1`, `9ECC-07D0`):

```
/EFI/ubuntu/{BOOTX64.CSV,grub.cfg,grubx64.efi,mmx64.efi,shimx64.efi}
/EFI/Boot/{bootx64.efi,fbx64.efi,mmx64.efi}      ← bootx64.efi здесь был shim, не Microsoft
```

`\EFI\BOOT\BOOTX64.EFI` — путь, по которому прошивка грузит съёмный носитель
(в BootOrder это `0005* Hard Drive`). Там лежал shim Ubuntu; он запускает `fbx64.efi`,
тот сканирует `\EFI\*\BOOT*.CSV`, находит `shimx64.efi,Ubuntu,,This is the boot entry
for Ubuntu` и создаёт запись заново. Отсюда «опять появилась».

Удалено: весь `/EFI/ubuntu`, плюс `fbx64.efi` и `mmx64.efi` из `/EFI/Boot`. Запись
`0006* ubuntu` снята через `efibootmgr -b 0006 -B`, из BootOrder ушла сама.
`grub.cfg` ссылался на `fs_uuid 9f372a69-be15-4d41-a173-2e0fdd01047f` — такого
раздела на машине нет, всё это было мертво с сентября 2025.

Бэкап удалённого — 6.2 МБ, стоковые бинарники shim/grub из пакетов Ubuntu.

`/EFI/Boot/bootx64.efi` (сам shim) остался: без CSV и `fbx64.efi` он инертен —
grub рядом с ним нет, восстанавливать запись нечем. Windows его не использует,
у него своя NVRAM-запись прямо на `bootmgfw.efi`.

Побочный эффект: на `sda1` больше нет рабочего загрузчика по съёмному пути. Раньше
он тоже никуда не вёл (grub искал несуществующий раздел), так что потери нет, но
если хочется страховки на случай сброса NVRAM — у модуля limine есть
`boot.loader.limine.efiInstallAsRemovable`, он кладёт limine в
`<ESP>/efi/boot/BOOTX64.EFI` вместо `<ESP>/efi/limine/`.

### NVRAM сейчас

```
BootCurrent: 0001
BootOrder:   0001,0003,0000,0005
0001* Limine           NVMe  1126122a-…
0003* Limine (ADATA)   ADATA 7bffd8d6-…   ← запасной вход, снести после проверки
0000* Windows Boot Manager
0005* Hard Drive       (BBS, генерит прошивка)
```
