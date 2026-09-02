# nnn-t480s: установка с флешки

Второй хост — ThinkPad T480s. NixOS ставится **единственной системой**: диск размечается
с нуля, ничего сохранять не нужно.

Ноутбук при этом ничего не качает из сети. Всё замыкание собрано на nnn-desktop и лежит на
той же флешке, с которой ноутбук загружается, — как локальный бинарный кеш. Причины две:
не тянуть больше двадцати гигабайт по второму разу и не зависеть от того, поднимется ли
Wi-Fi в установочном ISO.

**Флешка уже подготовлена** (см. §1) и рассчитана на **один рейс**: всё, что нужно, на ней
уже есть, и возвращаться к десктопу не придётся. Это возможно потому, что замыкание системы
**не зависит** ни от идентификатора диска, ни от размера swap — проверено сравнением
`drvPath`. От них зависит только скрипт разметки, а он собирается на самом ноутбуке за
секунды, офлайн, из того же кеша.

---

## 1. Что на флешке

Один носитель, три раздела:

| Раздел | Что |
|---|---|
| `sdX1` | NixOS 26.11 minimal ISO — загрузочный, iso9660 |
| `sdX2` | `EFIBOOT`, 3 МБ — служебный, от ISO |
| `sdX3` | `NNN-STORE`, ext4, 27 ГиБ — всё остальное |

На `NNN-STORE`:

```
store/                  бинарный кеш: замыкание nnn-t480s + скрипт disko + исходники
                        всех входов флейка (nix flake archive), сжато zstd
nixos-config/           клон репозитория на коммите, из которого собрано замыкание
secrets/t480s-age-key.txt   приватный age-ключ ноутбука, 0600
```

> Ключ — единственное, чего нет в репозитории, и единственное, что нельзя восстановить.
> Его копия остаётся на десктопе в `~/secrets-backup/`.

---

## 2. Перед установкой: BIOS

Загрузиться с флешки (F12 — меню загрузки, F1 — BIOS) и проверить:

- **Secure Boot выключен.** limine не подписан, с включённым Secure Boot он не стартует.
- Режим SATA — **AHCI**, не RST. В RST ядро не увидит NVMe вообще.
- UEFI-only, без CSM.

---

## 3. Установка

Всё под root: `sudo -i`.

> Раздел переписан **по факту установки 31.08.2026**. Первоначальная версия была
> написана до неё и разошлась с реальностью в шести местах — все они ниже, с
> объяснением, а не просто исправленной командой.

### 3.1 Смонтировать флешку

Три неочевидности подряд, и каждая стоила времени.

**Метку `mount -L` не откроет.** Гибридный ISO — это валидная iso9660 **с нулевого
сектора всего устройства**, и установщик монтирует `/dev/sdb` целиком. Диск оказывается
занят монопольно, а `mount` требует именно монопольного доступа к разделу — отсюда
`fsconfig failed: can't open blockdev`. Проверить можно так:

```sh
findmnt -o TARGET,SOURCE,FSTYPE | grep -iE "sdb|loop|iso"
```

Если источник — `/dev/sdb` без цифры, это он. Обход: подсунуть разделу loop-устройство,
потому что loop открывает диск неэксклюзивно.

```sh
losetup -f --show -o 1727004672 /dev/sdb
```

Смещение — начало третьего раздела (сектор 3373056 × 512). Границу сверху задавать не
надо, раздел идёт до конца носителя. Команда напечатает имя вида `/dev/loop1` (`loop0`
занят squashfs установщика).

**Монтировать в `/run`, а не в `/mnt`.** `disko` монтирует новый корень в `/mnt` и
накрыл бы собой точку `/mnt/nnn` ровно тогда, когда кеш нужен для `nixos-install`.

**Тип указывать явно.** Без `-t ext4` mount перебирает типы и промахивается.

```sh
mkdir -p /run/nnn
mount -t ext4 /dev/loop1 /run/nnn
ls /run/nnn
```

Ожидается `lost+found  nixos-config  secrets  store`.

> `mount --move` из `/mnt/nnn` в `/run/nnn` не работает: systemd делает `/` разделяемым,
> а из-под shared-точки перенос запрещён. Отмонтировать и смонтировать заново.

### 3.2 Снять три значения

```sh
ls /dev/disk/by-id/ | grep '^nvme-' | grep -v part
free -g
nixos-generate-config --show-hardware-config | grep -E "KernelModules|hostPlatform"
```

Первое — идентификатор диска (годится и `nvme-eui.…`), второе — объём RAM для размера
swap, третье — сверка с написанным вручную `hardware-configuration.nix`.

### 3.3 Настроить nix и подставить диск

```sh
mkdir -p /root/.config/nix
printf 'experimental-features = nix-command flakes\nsubstituters = file:///run/nnn/store\nrequire-sigs = false\n' >/root/.config/nix/nix.conf
```

Затем в копии репозитория **на флешке**:

```sh
cd /run/nnn/nixos-config
sed -i 's|REPLACE-ME[^"]*|<by-id диска>|' hosts/nnn-t480s/disko.nix
grep -n 'device = ' hosts/nnn-t480s/disko.nix
```

При необходимости там же поправить `size` swap-тома: он обязан быть **не меньше RAM**.

### 3.4 Взять скрипт разметки из кеша

**Офлайновое вычисление флейка не работает.** `nix flake archive` кладёт исходники входов
в кеш, но nix при вычислении с этим кешем их не связывает и идёт за ними на GitHub —
`nix build` падает с «failed to download». Сети на ноутбуке нет, и это тупик.

Обход: не вычислять флейк вообще. И скрипт разметки, и система уже собраны на десктопе и
лежат в кеше по конкретным путям, а разметка отличается от заготовки ровно строкой с
диском.

```sh
nix-store -r /nix/store/c2l6scpj2x5386yr4q4mr82ya66sgclf-disko
sed "s|REPLACE-ME-nvme-[^\"';# ]*|<by-id диска>|g" /nix/store/c2l6scpj2x5386yr4q4mr82ya66sgclf-disko > /tmp/disko-t480s
chmod +x /tmp/disko-t480s
```

Эквивалентность подстановки честной пересборке **проверена побайтово**: скрипт, собранный
с реальным диском, и заготовка с подставленным диском совпали (md5
`967b1f72f95503c03e1b6f9452707aa5`). Класс `[^\"';# ]` обязателен — он не даёт замене
съесть закрывающую кавычку и хвост комментария.

Обязательная проверка перед запуском:

```sh
grep -c REPLACE-ME /tmp/disko-t480s          # 0
grep -c '<by-id диска>' /tmp/disko-t480s     # 17
bash -n /tmp/disko-t480s && echo SYNTAX-OK
grep -o "for dev in [^;]*" /tmp/disko-t480s  # нацелен на нужный диск
```

Если первое число не ноль — замена не прошла, запускать нельзя.

### 3.5 Разметить

```sh
/tmp/disko-t480s
```

**Стирает диск целиком.** Пароль LUKS спрашивается **один раз, без подтверждения** —
опечатка даёт диск с неизвестным паролем. Раскладка US, и сейчас, и в initrd при каждой
загрузке. Ввод невидимый.

### 3.6 Проверить разметку и пароль

```sh
lsblk
cryptsetup luksOpen --test-passphrase /dev/nvme0n1p2 && echo PAROL-OK
```

Проверку пароля **не пропускать**: пока установка не началась, переразметить — минута.

### 3.7 Установить

По той же причине, что в 3.4, — не через `--flake`, а по готовому пути:

```sh
nixos-install --root /mnt --no-channel-copy --system <путь к toplevel> --option substituters file:///run/nnn/store --option require-sigs false
```

`--system` ставит уже собранное замыкание: ничего не вычисляется и в сеть не идёт.
Путь берётся с десктопа (`nix eval --raw '.#nixosConfigurations.nnn-t480s.config.system.build.toplevel'`)
и записывается на флешку заранее.

### 3.8 Ключ, репозиторий, пароль

```sh
install -Dm600 -o root -g root /run/nnn/secrets/t480s-age-key.txt /mnt/var/lib/sops-nix/key.txt
mkdir -p /mnt/home/sundial && cp -r /run/nnn/nixos-config /mnt/home/sundial/
chown -R 1000:100 /mnt/home/sundial/nixos-config
nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/sw/bin/passwd sundial'
```

Ключ обязательно до перезагрузки, иначе `sops-nix` упадёт и система приедет без
ssh-ключей и конфига VPN.

### 3.9 Перед перезагрузкой — три проверки

```sh
ls /mnt/boot                                              # EFI и limine
grep -o 'resume=[^ ]*' /mnt/boot/limine/limine.conf       # resume=/dev/t480s/swap
ls -l /mnt/var/lib/sops-nix/key.txt                       # -rw------- root
```

Конфиг limine лежит в **`/boot/limine/limine.conf`**, не в `/boot/limine.conf`.

### Грабли

Те же, что и на первой установке — подробности в [install-plan.md](install-plan.md) §2:

- **`sudo` сбрасывает PATH** (`secure_path`), и `nixos-install` не находит `nix`. Отсюда
  `sudo -i` в начале. Рецепт `sudo PATH="$PATH" …` во fish не работает: `$PATH` там
  список и развернётся в несколько аргументов; нужен `sudo env PATH=…`.
- **Внутри `nixos-enter` PATH пуст** — `passwd` только по абсолютному пути.
- **Перезагрузка посреди процесса всё размонтирует.** Лечится повторным монтированием в
  том же порядке; ничего не теряется.

### Если ESP побился

На первой же загрузке T480s `/boot` оказался повреждён: `fsck.vfat` сыпал «cluster out of
range», systemd вечно ждал устройство (`A start job is running… no limit`). Систему это не
тронуло — пострадал только загрузочный раздел. Восстановление с флешки:

```sh
mkfs.vfat -F 32 -n NIXBOOT /dev/nvme0n1p1
# открыть LUKS, смонтировать корень и /boot, затем:
nixos-enter --root /mnt -c 'NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot'
```

**Причина не установлена.** Подозрение на `mkfs.vfat`, который выбирает ширину FAT по
размеру раздела и, как уже отмечено в `hosts/nnn-desktop/disko.nix`, умеет положить
файловую систему меньше выданного раздела. С тех пор в обоих `disko.nix` стоит явный
`extraArgs = ["-F" "32"]` — это дешёвая страховка, а не доказанное исправление.

## 4. После первой загрузки

Вернуть в репозиторий то, что было угадано. До этого момента в `local.nix` стоит
предположение о панели:

```sh
niri msg outputs     # имя выхода, режим, частота
```

T480s выпускался с разными панелями (1920x1080 — обычная, на части SKU 2560x1440). Если
не совпало — поправить `monitors."eDP-1"` в `hosts/nnn-t480s/local.nix` и пересобрать. Имя
выхода тоже стоит сверить: правило для gamescope и настройка greeter'а ссылаются на
`eDP-1` по имени.

Заодно перенести правки с флешки обратно:

```sh
cd ~/nixos-config
git diff /mnt/nnn/nixos-config/hosts/nnn-t480s/disko.nix hosts/nnn-t480s/disko.nix
```

Реальные `device` и размер swap должны попасть в коммит — иначе следующая переустановка
начнётся с того же гадания.

---

## 5. Проверка

```sh
# базовое
niri msg outputs                     # eDP-1 со своим scale
vainfo | head                        # iHD (Kaby Lake R — Gen9)
echo $SHELL                          # fish
busctl --user list | grep portal     # .Desktop / .Gnome / .Gtk

# секреты
systemctl status sops-nix
ls -l ~/.ssh/id_ed25519_github_dberd ~/.config/snx-rs/snx-rs.conf   # 0600, владелец sundial
ssh -T git@github.com

# ноутбучное
cat /sys/class/power_supply/BAT0/charge_control_end_threshold       # 80
upower -i /org/freedesktop/UPower/devices/battery_BAT0 | head
fprintd-enroll && sudo -k && sudo true                              # палец вместо пароля

# работа
systemctl status snx-rs snx-vpn-routing
docker compose -f ~/docker/docker-dev.yml up -d && psql -h localhost -U postgres
```

### Гибернация — проверять первой

```sh
cat /sys/power/resume            # не должно быть 0:0
systemctl hibernate
```

Машина должна погаснуть и при следующем включении вернуться в ту же сессию, а не
загрузиться заново. Если загрузилась заново — swap-том меньше RAM либо `boot.resumeDevice`
не доехал.

**Проверять до того, как на ноутбуке появится что-то несохранённое.** Неудачная гибернация
выглядит как обычная загрузка с нуля, то есть как потеря всего открытого.

### Что заведомо не работает

- **Гейминг.** `modules/nixos/gaming.nix` этот хост не импортирует: ни Steam, ни gamescope,
  ни lutris. Так задумано.

Стоит проверить отдельно, потому что настройка общая для обоих хостов:

- **Яркость.** `brightness.enable_ddcutil` в `modules/home/noctalia.nix` включён — он нужен
  десктопу, у которого своей подсветки нет и яркость идёт по DDC/CI во внешние мониторы. У
  ноутбука есть штатный backlight, а `ddcutil` тут даже не установлен (он ставится из
  `hardware/amd-desktop.nix`). Если клавиши яркости не заработают или в журнале Noctalia
  появятся жалобы на ddcutil — вынести этот ключ в per-host настройку.

---

## 6. Как флешка готовилась

На случай, если её придётся собрать заново (другой ноутбук, повреждённый носитель).

```sh
# 1. ISO. Сверить сумму с опубликованной — она рядом, .sha256
curl -LO https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso
sha256sum nixos-minimal-*.iso

# 2. Записать. ВНИМАНИЕ на устройство: адресовать по by-id, а не по /dev/sdX
sudo wipefs -a /dev/disk/by-id/usb-<...>
sudo dd if=nixos-minimal-*.iso of=/dev/disk/by-id/usb-<...> bs=4M status=progress conv=fsync

# 3. Третий раздел в остатке. --append дописывает запись, не переписывая
#    существующие: MBR-код и флаг загрузки на первом разделе остаются как есть.
echo 'start=3373056, type=83' | sudo sfdisk --append /dev/sdX
sudo mkfs.ext4 -L NNN-STORE -m 0 /dev/sdX3
sudo mount -t ext4 /dev/sdX3 /mnt/nnn

# 4. Наполнить
nix flake archive --to "file:///mnt/nnn/store?compression=zstd"
nix copy --to "file:///mnt/nnn/store?compression=zstd&parallel-compression=true" \
  --no-check-sigs \
  "$(nix eval --raw '.#nixosConfigurations.nnn-t480s.config.system.build.toplevel')" \
  "$(nix eval --raw '.#nixosConfigurations.nnn-t480s.config.system.build.diskoScript')"
git clone --no-hardlinks ~/nixos-config /mnt/nnn/nixos-config
install -Dm600 ~/secrets-backup/t480s-age-key.txt /mnt/nnn/secrets/t480s-age-key.txt
```

`compression=zstd` не косметика: замыкание — 22.6 ГиБ, и в несжатом виде оно на 28-гигабайтную
флешку рядом с ISO не помещается. Умолчание у `file://`-кеша — xz, который жмёт лучше, но на
таком объёме считается неприлично долго.

Дерево репозитория при копировании **обязано быть чистым**. Замыкание собирается из рабочего
дерева, и если в нём есть незакоммиченные правки, то клон на флешке (он всегда на коммите)
вычислится в другие деривации — и `nixos-install` полезет в сеть за тем, чего в кеше нет.
