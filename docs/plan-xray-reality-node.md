# План: вернуть французскую REALITY-ноду, не возвращая Throne

**Отменён 22.08.2026.** Решили не тащить REALITY: рабочего набора без неё (`vavn-lv` +
`vavn-fr-hy2`) достаточно, а второй движок ради одного протокола не стоит своей сложности —
секреты вне `sing-box`'овской `_secret`-подстановки, отдельный юнит, отдельный конфиг. Разбор
вариантов и причина — `docs/proxy.md`, раздел 6. Файл оставлен для истории измерений ниже,
исполнять не нужно.

**Поправка 23.08:** таблица ниже называет Xray-core 26.3.27 "ядром, которое несёт в себе
Throne" — это неверно для сборки nixpkgs. `ThroneCore` собирается `buildGoModule` из
`github.com/sagernet/sing-box` (`pkgs/by-name/th/throne/package.nix`), никакого Xray-core в
пакете нет. Строка "Xray-core 26.3.27 | работает" ниже, видимо, была получена тестом отдельно
собранного/скачанного Xray-core, не через сам Throne — так что вариант "просто переключить
профиль на другое ядро внутри Throne" никогда не был доступен на этой системе.

Задача для отдельного агента. Всё, что нужно знать, — здесь; читать историю чата не требуется.

## Контекст

Прокси-стек уже переехал с Throne на sing-box:

- `modules/nixos/singbox.nix` — ядро: селектор из двух нод, mixed-инбаунд `127.0.0.1:2081`,
  Clash API `127.0.0.1:9091`, корпоративные исключения в `route.rules`;
- `modules/home/noctalia.nix` — виджет в баре (`mihomo-control`), говорит с Clash API;
- `modules/nixos/vpn.nix` — snx-rs и обход nftables-перехвата Throne (Throne пока ещё включён);
- ключи нод — в `secrets/secrets.yaml` (sops), в конфиг попадают через `_secret`.

Подписка провайдера содержит три ноды. Две работают под sing-box и уже в конфиге. Третья —
`🇫🇷 Vavn`, VLESS+REALITY на `fr.vavn.pro:443` — под sing-box **не поднимается**.

## Что уже измерено (не перепроверять с нуля)

Подписка перезабрана у провайдера 22.08, ключи актуальны. С ними:

| Клиент | Результат на REALITY-ноде |
|---|---|
| sing-box 1.13.14 | `reality verification failed` |
| sing-box 1.13.18 | `reality verification failed` |
| Xray-core 26.3.27 | **работает**, выход `217.60.63.38` |

У sing-box перебраны: с `flow` и без, `fingerprint` firefox и chrome, `sid` исходный и пустой,
`spiderX` есть и нет. Вывод: ограничение клиента, а не мёртвый сервер.

Почему нельзя просто перейти на xray целиком — тоже измерено:

- `xray -test` на конфиге с `protocol: "hysteria2"` → `unknown config id: hysteria2`. Hy2-нода
  была бы потеряна;
- в бинаре xray нет Clash API (его `xray api` — собственный gRPC). Виджет в баре перестал бы
  работать вообще, а он и был целью всей затеи.

Поэтому: sing-box остаётся главным, xray добавляется **только под одну ноду**.

## Что сделать

xray поднимает локальный SOCKS только для REALITY-ноды; sing-box включает его в свой селектор
обычным `socks`-аутбаундом. В виджете нода выглядит как третий пункт списка, переключается и
пингуется как остальные.

```
виджет ──Clash API 9091──▶ sing-box ──selector──┬── vavn-lv        (vless+tls, напрямую)
                                                ├── vavn-fr-hy2    (hysteria2, напрямую)
                                                └── vavn-fr-reality ──socks 127.0.0.1:2082──▶ xray ──▶ fr.vavn.pro
```

### 1. Секреты

Добавить в `secrets/secrets.yaml` (`nix develop`, затем `sops secrets/secrets.yaml`):

- `xray-reality-pbk` — `pbk` из ссылки подписки;
- `xray-reality-sid` — `sid` оттуда же.

`uuid` **не дублировать**: он совпадает с уже существующим `singbox-vavn-uuid` (проверено).

Ссылка берётся из подписки: URL лежит в базе Throne (`select url from groups;`), содержимое —
base64-список ссылок, разбор описан в `docs/proxy.md` §6.1. Забрать URL **до** сноса Throne и
положить его в sops отдельным ключом.

### 2. Новый модуль `modules/nixos/xray.nix`

Ключевая засада: модуль `services.xray` из nixpkgs кладёт конфиг **в стор** через
`writeTextFile`, то есть секреты стали бы всемирно читаемыми. Механизма `_secret`, как у
sing-box, у него нет. Поэтому конфиг рендерится sops-шаблоном, а модулю отдаётся путь:

```nix
sops.templates."xray.json" = {
  content = builtins.toJSON { … outbounds с ${config.sops.placeholder.xray-reality-pbk} … };
  mode = "0400";
};
services.xray = {
  enable = true;
  settingsFile = config.sops.templates."xray.json".path;
};
```

Юнит из nixpkgs читает файл через `LoadCredential` под root'ом и только потом уходит в
`DynamicUser`, так что права `0400 root` подходят. Это первое использование `sops.templates`
в репозитории — стоит объяснить в комментарии, зачем оно тут, а не `sops.secrets`.

Содержимое конфига xray:

- `inbounds`: socks на `127.0.0.1:2082`, `settings.udp = true`;
- `outbounds[0]`: `protocol = "vless"`, `address = "fr.vavn.pro"`, `port = 443`,
  `users[0] = { id = <uuid>, flow = "xtls-rprx-vision", encryption = "none" }`;
  `streamSettings = { network = "tcp"; security = "reality";
   realitySettings = { serverName = "fr.vavn.pro"; publicKey = <pbk>; shortId = <sid>;
   fingerprint = "firefox"; }; sockopt = { mark = 8228; } }`.

Про `mark = 8228`: это bypass-метка sing-box, которой обходятся nftables-цепочки Throne
(см. шапку `vpn.nix`). Пока Throne жив — без неё соединение уйдёт в его туннель. После сноса
Throne метка безвредна, убирать не обязательно.

Импортировать модуль в `modules/nixos/default.nix`.

### 3. Изменения в `modules/nixos/singbox.nix`

- новый аутбаунд:

  ```nix
  {
    type = "socks";
    tag = "vavn-fr-reality";
    server = "127.0.0.1";
    server_port = 2082;
  }
  ```

  `routing_mark` тут **не нужен** — соединение идёт на loopback, а метку ставит уже xray на
  своём внешнем сокете;
- добавить тег в список `outbounds` селектора `proxy`;
- `default` не менять: пусть остаётся Hy2.

### 4. Проверка

```fish
sudo nixos-rebuild switch --flake .#nnn-desktop
systemctl status xray sing-box --no-pager | head -20

# нода видна селектору
curl -s http://127.0.0.1:9091/proxies | jq '.proxies.proxy.all'

# и реально работает
curl -s -X PUT -H 'Content-Type: application/json' \
  -d '{"name":"vavn-fr-reality"}' http://127.0.0.1:9091/proxies/proxy
curl -s -x http://127.0.0.1:2081 https://ifconfig.me      # ожидается 217.60.63.38

# задержки всех трёх
curl -s 'http://127.0.0.1:9091/group/proxy/delay?url=http%3A%2F%2Fcp.cloudflare.com&timeout=5000'

# корпоративная сеть не пострадала
host gitlab.sddt.efko.ru 10.47.1.1
curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:2081 https://gitlab.sddt.efko.ru/

# секреты не утекли в стор
sudo grep -r "$(sops -d secrets/secrets.yaml | grep '^xray-reality-pbk' | cut -d' ' -f2)" /nix/store 2>/dev/null | head -1   # должно быть пусто
```

Вернуть селектор на `vavn-fr-hy2` после проверки.

### 5. Чего не делать

- не переносить на xray остальные ноды: Hy2 он не умеет, а VLESS+TLS-нода прекрасно работает
  под sing-box, и лишний прыжок через SOCKS только добавит задержку;
- не выносить Clash API или инбаунд в xray — у него нет Clash API, виджет говорит только с
  sing-box;
- не трогать `programs.throne` в этой задаче: снос Throne — отдельный шаг со своим порядком,
  описан в `docs/proxy.md` §9.

## Риски

- **Ротация ключей.** Провайдер уже менял `pbk`/`sid` этой ноды. Когда нода перестанет
  работать, чинится это обновлением двух секретов, а не переустановкой; в `docs/proxy.md` §6
  порядок описан.
- **Второй демон.** xray работает всегда, даже когда нода не выбрана; он ничего не делает, но
  слушает порт. Если это мешает, можно повесить его на socket-активацию — но это
  усложнение ради 15 МБ RSS.
- **Задержка.** Трафик через эту ноду идёт двумя процессами. По измерениям накладные расходы
  в пределах погрешности, но замер `/group/proxy/delay` для неё будет чуть выше «честного».
