# nnn-t480s: установка с флешки

Второй хост — ThinkPad T480s. NixOS ставится **единственной системой**: диск размечается
с нуля, ничего сохранять не нужно.

Особенность процедуры — ноутбук ничего не качает из сети. Всё замыкание собирается на
nnn-desktop и переезжает на флешке как локальный бинарный кеш. Причины две: не тянуть
несколько гигабайт по второму разу и не зависеть от того, поднимется ли Wi-Fi в
установочном ISO.

> Разделы ниже нумерованы в том порядке, в котором выполняются. Порядок не произвольный:
> собрать замыкание на десктопе нельзя, пока неизвестны `by-id` диска ноутбука и объём
> его памяти, а узнать их можно только на самом ноутбуке. Отсюда два рейса флешки.

---

## 0. Что должно быть под рукой

- Флешка под установочный ISO (≈1 ГБ).
- Вторая флешка или внешний диск под замыкание — **не меньше 16 ГБ**, отформатированный
  во что угодно, что понимает Linux (ext4/btrfs). **Не FAT32**: в замыкании есть файлы
  крупнее 4 ГБ, и `nix copy` на FAT32 упадёт на середине.
- `~/secrets-backup/t480s-age-key.txt` — приватный age-ключ ноутбука, созданный при
  добавлении хоста. Без него sops-nix на ноуте не расшифрует ничего.

Записать ISO (minimal или graphical, с https://nixos.org/download):

```sh
sudo dd if=<iso> of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## 1. Рейс первый: ноутбук → десктоп (разведка)

В `hosts/nnn-t480s/` два значения помечены `PLACEHOLDER`, и оба узнаются только здесь.

Загрузиться с ISO на T480s. Сеть не нужна.

```sh
# идентификатор диска — идёт в hosts/nnn-t480s/disko.nix, поле device
ls -l /dev/disk/by-id/ | grep -v part

# объём RAM — определяет размер swap-тома (нужно >= RAM, иначе гибернация не запишется)
free -g

# реальное железо — заменит написанный от руки hardware-configuration.nix
nixos-generate-config --show-hardware-config
```

Перенести вывод на десктоп: смонтировать флешку и записать туда, либо просто переписать
`by-id` и объём памяти на бумажку — их всего два.

```sh
mkdir -p /mnt/usb && mount /dev/sdX1 /mnt/usb
nixos-generate-config --show-hardware-config > /mnt/usb/hardware-configuration.nix
ls -l /dev/disk/by-id/ | grep -v part > /mnt/usb/disk-ids.txt
umount /mnt/usb
```

Заодно, пока ноутбук загружен, стоит зайти в BIOS (F1) и убедиться:

- **Secure Boot выключен.** limine не подписан, с включённым Secure Boot он не стартует.
- Режим SATA — **AHCI**, не RST. В RST ядро не увидит NVMe вообще.
- UEFI-only, без CSM.

---

## 2. На десктопе: подставить значения и собрать

Подставить в `hosts/nnn-t480s/disko.nix`:

```nix
device = "/dev/disk/by-id/nvme-<то, что показал ls>";   # без суффикса -partN
```

и там же размер swap — RAM + 2 ГиБ:

```nix
swap.size = "18G";   # для 16 ГиБ RAM
```

Заменить `hosts/nnn-t480s/hardware-configuration.nix` сгенерированным. Из него надо
**убрать `fileSystems` и `swapDevices`** — их даёт `disko.nix`, и две декларации на один
и тот же путь конфликтуют.

Собрать систему и скрипт разметки:

```sh
cd ~/nixos-config
git add -A          # nix читает флейк через git; неотслеженные файлы для него не существуют

nix build .#nixosConfigurations.nnn-t480s.config.system.build.toplevel     -o /tmp/t480s-sys
nix build .#nixosConfigurations.nnn-t480s.config.system.build.diskoScript  -o /tmp/t480s-disko
```

Выложить всё на флешку как локальный бинарный кеш:

```sh
mount /dev/sdX1 /mnt/usb

nix copy --to file:///mnt/usb/store --no-check-sigs /tmp/t480s-sys /tmp/t480s-disko
cp -r ~/nixos-config /mnt/usb/nixos-config        # вместе с flake.lock и .git
cp ~/secrets-backup/t480s-age-key.txt /mnt/usb/

# путь к скрипту разметки понадобится на ноуте — записать его рядом
readlink -f /tmp/t480s-disko > /mnt/usb/disko-path.txt

umount /mnt/usb
```

`--no-check-sigs` здесь безопасно: подписи не проверяются потому, что пути собраны локально
и не подписаны, а не потому, что доверяем чужому кешу.

---

## 3. Рейс второй: десктоп → ноутбук (установка)

Загрузиться с ISO на T480s, **всё под root** (`sudo -i`).

```sh
mkdir -p /mnt/usb && mount /dev/sdX1 /mnt/usb
```

### 3.1 Разметка

Скрипт **стирает диск целиком** и спрашивает парольную фразу LUKS — дважды, второй раз
на подтверждение. Ввести её надо будет при каждой загрузке, так что стоит подумать
заранее и проверить, что раскладка в этот момент US (в initrd она всегда US).

```sh
$(cat /mnt/usb/disko-path.txt)
```

После него: `lsblk` должен показать ESP, `cryptroot`, и внутри — `t480s-swap` и
`t480s-root`; `/mnt` уже смонтирован со всеми сабволюмами.

### 3.2 Установка

```sh
nixos-install --root /mnt --flake /mnt/usb/nixos-config#nnn-t480s --no-channel-copy \
  --option substituters file:///mnt/usb/store \
  --option require-sigs false
```

Флаги делают ровно одно: заставляют nix брать пути из флешки, а не из сети.

### 3.3 Ключ и пароль

```sh
install -Dm600 -o root -g root /mnt/usb/t480s-age-key.txt /mnt/var/lib/sops-nix/key.txt
nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/sw/bin/passwd sundial'
```

Порядок важен: без ключа первая же загрузка не разложит секреты, и `sops-nix.service`
упадёт (система при этом загрузится — но без ssh-ключей и конфига VPN).

### Грабли

Те же, что и на первой установке — подробности в [install-plan.md](install-plan.md) §2:

- **`sudo` сбрасывает PATH**, и `nixos-install` не находит `nix`. Отсюда `sudo -i` выше.
  Рецепт из мануала `sudo PATH="$PATH" …` во fish не работает: `$PATH` там список и
  развернётся в несколько отдельных аргументов; нужен `sudo env PATH=…`.
- **Внутри `nixos-enter` PATH пуст** — `passwd` только по абсолютному пути.
- **Перезагрузка посреди процесса всё размонтирует.** Лечится повторным монтированием
  в том же порядке (`disko-mount`, затем флешка); ничего не теряется.

---

## 4. После первой загрузки

Снять реальные значения и вернуть их в репозиторий — до этого момента в `local.nix`
стоят предположения:

```sh
niri msg outputs     # имя выхода, режим и частота → hosts/nnn-t480s/local.nix
```

Если панель оказалась не 1920x1080@60 — поправить `monitors."eDP-1"` и пересобрать.
Имя выхода тоже стоит сверить: правило для gamescope и настройка greeter'а ссылаются
на `eDP-1` по имени.

---

## 5. Проверка

```sh
# базовое
niri msg outputs                     # eDP-1 со своим scale
vainfo | head                        # должен быть iHD (Kaby Lake R — Gen9)
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
загрузиться заново. Если загрузилась заново — `boot.resumeDevice` не доехал или swap-том
меньше RAM.

**Проверять до того, как на ноутбуке появится что-то несохранённое.** Неудачная
гибернация выглядит как обычная загрузка с нуля, то есть как потеря всего открытого.

### Что заведомо не будет работать

- **Гейминг.** `modules/nixos/gaming.nix` этот хост не импортирует: ни Steam, ни
  gamescope, ни lutris. Так задумано.

Стоит проверить отдельно, потому что настройка общая для обоих хостов:

- **Яркость.** `brightness.enable_ddcutil` в `modules/home/noctalia.nix` включён — он
  нужен десктопу, у которого своей подсветки нет и яркость идёт по DDC/CI во внешние
  мониторы. У ноутбука есть штатный backlight, а `ddcutil` тут даже не установлен (он
  ставится из `hardware/amd-desktop.nix`). Если клавиши яркости не заработают или в
  журнале Noctalia появятся жалобы на ddcutil — вынести этот ключ в per-host настройку.
