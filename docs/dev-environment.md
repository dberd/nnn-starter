# Рабочее окружение: .NET, Angular, локальная инфраструктура

Что нужно, чтобы одиннадцать репозиториев из `~/Work/Repos` собирались и запускались
на этой машине. Декларативная часть — в `modules/home/dev.nix`, `modules/nixos/dev.nix`
и `flake.nix`; здесь объяснено, почему именно так, и что осталось руками.

---

## .NET: один комбинированный SDK

`modules/home/dev.nix` собирает `dotnetCorePackages.combinePackages` из SDK **6, 8, 9, 10**
плюс рантайм **ASP.NET 7**, и на него же указывает `DOTNET_ROOT`. Проверено:

```
$ dotnet --list-sdks
6.0.428  8.0.422  9.0.315  10.0.301
$ dotnet --list-runtimes | grep AspNetCore
6.0.36  7.0.20  8.0.28  9.0.17  10.0.9
```

SDK 7 не нужен: `net7.0`-проекты (Calendar, `Committees.WebApi`) собираются десятым SDK,
ref-паки приходят из NuGet. А вот **рантайм** 7 обязателен — без него собранное не стартует.
Ровно тот же размен, что делала установка на Arch (`~/Work/workspace-setup/SETUP.md` §02),
только записанный в конфигурации.

.NET 6 и 7 сняты с поддержки, поэтому nixpkgs помечает их insecure. Исключение объявлено
в `flake.nix` через `allowInsecurePredicate` — по **имени**, а не по версии, чтобы правило
переживало обновления nixpkgs. Там же лежит исключение для `pnpm` (сборка vesktop).

`Calendar/backend/global.json` требует SDK 7 с `rollForward: latestMajor` — десятый
подходит, ничего править не нужно.

## Конфиги отладки VSCodium

Синхронизируемый профиль (`~/Work/vscode-settings`) прописывал пути Arch:
`"/usr/bin/dotnet"` в `tasks.json` и `"DOTNET_ROOT": "/usr/share/dotnet"` в `launch.json`.
На NixOS обоих не существует — задачи `build`/`watch` и отладчик не запускались вовсе.

Заменено во всех одиннадцати каталогах `.vscode` (и в репозитории синхронизации,
и в живых репозиториях):

| Было | Стало |
|---|---|
| `"command": "/usr/bin/dotnet"` | `"command": "dotnet"` — из PATH сессии |
| `"DOTNET_ROOT": "/usr/share/dotnet"` | `"DOTNET_ROOT": "${env:DOTNET_ROOT}"` |
| `dotnetAcquisitionExtension.existingDotnetPath` | `/etc/profiles/per-user/sundial/bin/dotnet` |

Последний путь — стабильный симлинк профиля home-manager: он переживает и пересборки,
и обновления SDK. `existingDotnetPath` заставляет расширения `muhammad-sammy.csharp`,
`icsharpcode.ilspy-vscode` и `tintoy.msbuild-project-tools` брать системный .NET вместо
скачивания собственной копии.

## Node: fnm вместо nodejs_16

Оба фронтенда (Angular 14 в Committees, 16 в Calendar) требуют Node 16, а в nixpkgs
осталось только 20 и новее. `fnm` качает официальную сборку; она работает благодаря
`nix-ld` из `modules/nixos/dev.nix` — тому же, что нужен расширениям VSCodium.

Инициализация вынесена в `programs.fish.shellInit` (а не `interactiveShellInit`)
намеренно: задачи редактора запускают fish **неинтерактивно** и иначе версию не увидят.
`--use-on-cd` читает `.nvmrc`, которые уже лежат в обоих фронтендах.

Один раз руками:

```sh
fnm install 16
fnm default system     # системный Node остаётся дефолтным
```

Проверка: `cd ~/Work/Repos/Frontend/Calendar/frontend` → `node -v` даёт `v16.20.2`.
Переключение односторонее: выйдя из каталога, шелл остаётся на 16 до перезапуска.

### Токен npm для @efko

`Calendar/frontend/.npmrc` берёт авторизацию к корпоративному nexus из `${NPM_TOKEN}`,
и без переменной `npm ci` падает на пакетах `@efko/*`. В `Committees/frontend/.npmrc`
тот же токен вписан открытым текстом — он и подходит:

```sh
set -gx NPM_TOKEN <base64 login:password из Committees/frontend/.npmrc>
```

Просится в sops (`secrets/secrets.yaml` + экспорт из `/run/secrets`), но это чужой
корпоративный секрет — решение за владельцем.

## Локальная инфраструктура

`~/docker/docker-dev.yml` (из `modules/home/files/docker-dev.yml`) поднимает четыре
контейнера в сети `dev-network` (`172.28.0.0/16`), все с `restart: unless-stopped`:

| Сервис | Порт на хосте | Примечание |
|---|---|---|
| postgres 18 | 5432 | `postgres` / `1234`, тот же пароль в конфигах отладки |
| redis 8.4 | 6379 | |
| memgraph 3.11 | **7867** → 7687 | внутри сети слушает 7687 |
| memgraph-lab | 3000 | UI, автоподключение к memgraph |

Между собой контейнеры общаются по именам, приложения с хоста — через `localhost`.
Дампы для наполнения баз лежат в `~/Work/Dumps`.

## Порты бэкендов и две коллизии

`applicationUrl` из `launchSettings.json`:

| Проект | http | https |
|---|---|---|
| Committees/backend | 5001 | 44381 |
| Calendar/export-calendar | 5294 | 7135 |
| PW/authentification | 5056 | 7092 |
| PW/node-manager | 5209 | 7165 |
| Skud/backend | 5054 | 7299 |
| Calendar/sync-users | 5156 | — |
| notifications **и** PW/notifications | 5299 | 7270 |
| Calendar/backend **и** Calendar/sync-external-calendar-job | 5150 | 7150 |

Две последние строки — одинаковые порты у разных сервисов. Пока они не запускаются
одновременно, это не мешает; если понадобится — проще всего разойтись через
`ASPNETCORE_URLS` в `launch.json` соответствующего проекта, не трогая `launchSettings.json`
(он в git и общий с коллегами).

## Мелочь, без которой не стартует

```sh
mkdir -p ~/Work/Repos/Backend/notifications/src/Efko.Notifications.Api/wwwroot
```

Git пустых каталогов не хранит, а приложение в Development на него рассчитывает.

## Проверено на этой машине

```
dotnet build Notifications.sln                    # net9.0        — 0 errors
dotnet build Committees.sln                       # net6.0+net7.0 — 0 errors
npm ci && npm run build  (Committees, Angular 14, Node 16)        — dist собран
npm ci                   (Calendar,   Angular 16, Node 16)        — ok
docker compose -f ~/docker/docker-dev.yml ps                      — 4 контейнера Up
```
