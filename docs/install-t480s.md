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

### 3.1 Смонтировать флешку

Установочный ISO монтирует свой раздел сам; нужен третий.

```sh
mkdir -p /mnt/nnn
mount -L NNN-STORE /mnt/nnn
```

Монтирование по метке, а не по `/dev/sdX3`: имя устройства зависит от порядка опроса, и
угадывать его не надо.

### 3.2 Снять два значения

Оба помечены в репозитории как `PLACEHOLDER`, и оба узнаются только здесь.

```sh
# идентификатор диска — БЕЗ суффикса -partN
ls -l /dev/disk/by-id/ | grep -v part

# объём памяти — от него размер swap-тома
free -g
```

### 3.3 Подставить их

Правится копия **на флешке**, не где-то ещё:

```sh
cd /mnt/nnn/nixos-config
nano hosts/nnn-t480s/disko.nix
```

Две строки:

```nix
device = "/dev/disk/by-id/nvme-<то, что показал ls>";
...
        size = "18G";     # >= RAM. 8 GiB RAM -> 10G, 16 -> 18G, 24 -> 26G
```

Swap **обязан** быть не меньше RAM, иначе образ гибернации некуда писать и
`systemctl hibernate` откажет ровно тогда, когда он был нужен.

### 3.4 Собрать скрипт разметки — офлайн

```sh
nix build --offline \
  --option substituters file:///mnt/nnn/store \
  --option require-sigs false \
  --extra-experimental-features 'nix-command flakes' \
  '/mnt/nnn/nixos-config#nixosConfigurations.nnn-t480s.config.system.build.diskoScript' \
  -o /tmp/disko-t480s
```

Собирается за секунды: сам скрипт — это подстановка двух строк, а все инструменты, которые
он вызывает (`cryptsetup`, `lvm2`, `btrfs-progs`, `sgdisk`, `mkfs.vfat`), уже лежат в кеше
на флешке.

### 3.5 Разметить

```sh
/tmp/disko-t480s
```

**Стирает диск целиком.** Спросит парольную фразу LUKS дважды — второй раз на
подтверждение. Её придётся вводить при каждой загрузке, так что стоит подумать заранее и
помнить: **в initrd раскладка всегда US**, что бы ни стояло в системе.

После него `lsblk` должен показать ESP, `cryptroot`, внутри — `t480s-swap` и `t480s-root`;
`/mnt` уже смонтирован со всеми сабволюмами.

### 3.6 Установить

```sh
nixos-install --root /mnt --flake /mnt/nnn/nixos-config#nnn-t480s --no-channel-copy \
  --option substituters file:///mnt/nnn/store \
  --option require-sigs false
```

Флаги делают ровно одно: заставляют nix брать пути с флешки, а не из сети. `require-sigs
false` здесь безопасно — пути не подписаны потому, что собраны локально на десктопе, а не
потому, что доверяем чужому кешу.

### 3.7 Ключ и пароль

```sh
install -Dm600 -o root -g root /mnt/nnn/secrets/t480s-age-key.txt /mnt/var/lib/sops-nix/key.txt
nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/sw/bin/passwd sundial'
```

Порядок важен: без ключа первая загрузка не разложит секреты и `sops-nix.service` упадёт.
Система при этом загрузится — но без ssh-ключей и конфига корпоративного VPN.

Затем `reboot` и вынуть флешку.

### Грабли

Те же, что и на первой установке — подробности в [install-plan.md](install-plan.md) §2:

- **`sudo` сбрасывает PATH** (`secure_path`), и `nixos-install` не находит `nix`. Отсюда
  `sudo -i` в начале. Рецепт из мануала `sudo PATH="$PATH" …` во fish не работает: `$PATH`
  там список и развернётся в несколько отдельных аргументов; нужен `sudo env PATH=…`.
- **Внутри `nixos-enter` PATH пуст** — `passwd` только по абсолютному пути.
- **Перезагрузка посреди процесса всё размонтирует.** Лечится повторным монтированием в том
  же порядке (`disko-mount`, затем флешка); ничего не теряется.

---

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
