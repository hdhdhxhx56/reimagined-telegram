# Личный VPN с сервером в США (WireGuard)

Скрипт `wireguard-install.sh` превращает обычный VPS в США в ваш личный VPN-сервер
на WireGuard: весь трафик устройства идёт через американский IP.

## 1. Арендуйте VPS в США

Подойдёт самый дешёвый тариф (1 vCPU, 512 МБ–1 ГБ RAM, ~$4–6 в месяц). При создании выберите:

- **Регион:** США (например, New York, Ashburn, Dallas, Los Angeles, Silicon Valley)
- **ОС:** Ubuntu 24.04 (или 22.04 / Debian 12)

Примеры провайдеров: DigitalOcean, Vultr, Linode (Akamai), Hetzner (Ashburn/Hillsboro), AWS Lightsail.

После создания у вас будет IP-адрес сервера и пароль/SSH-ключ для `root`.

## 2. Установите VPN на сервер

Подключитесь к серверу (на Windows — через PowerShell или PuTTY):

```bash
ssh root@IP_СЕРВЕРА
```

Загрузите и запустите скрипт:

```bash
curl -fsSLO https://raw.githubusercontent.com/hdhdhxhx56/reimagined-telegram/main/vpn/wireguard-install.sh
sudo bash wireguard-install.sh
```

> Если репозиторий приватный, скопируйте файл вручную:
> `scp vpn/wireguard-install.sh root@IP_СЕРВЕРА:~` и затем `sudo bash wireguard-install.sh`.

Скрипт установит WireGuard, включит маршрутизацию и NAT, создаст первое устройство `phone`
и покажет **QR-код** прямо в терминале. Также он проверит, что IP сервера действительно в США.

Если у хостинга есть файрвол в панели управления — откройте порт **51820/UDP**.

## 3. Подключите устройства

Установите официальное приложение **WireGuard**:

| Устройство | Где взять |
|---|---|
| iPhone / iPad | App Store → «WireGuard» |
| Android | Google Play → «WireGuard» |
| Windows / macOS | https://www.wireguard.com/install/ |
| Linux | `sudo apt install wireguard` |

- **Телефон:** «+» → «Сканировать QR-код» → наведите на QR-код в терминале.
- **Компьютер:** скачайте конфиг и импортируйте его в приложение:
  ```bash
  scp root@IP_СЕРВЕРА:/etc/wireguard/clients/laptop.conf .
  ```

Проверка: включите VPN и откройте https://ipinfo.io — должна быть страна **US**.

## Управление устройствами

```bash
sudo bash wireguard-install.sh add laptop     # добавить устройство (покажет QR-код)
sudo bash wireguard-install.sh list           # список устройств
sudo bash wireguard-install.sh remove laptop  # отозвать доступ
```

Каждому устройству — свой конфиг; не используйте один конфиг на нескольких устройствах одновременно.

## Настройки (необязательно)

Перед установкой можно задать переменные:

```bash
sudo WG_PORT=443 CLIENT_DNS="8.8.8.8" bash wireguard-install.sh
```

- `WG_PORT` — UDP-порт сервера (по умолчанию `51820`).
- `CLIENT_DNS` — DNS для клиентов (по умолчанию Cloudflare `1.1.1.1, 1.0.0.1`).

## Если не подключается

- `sudo wg show` — у устройства должен появиться `latest handshake`. Если его нет — порт UDP закрыт
  (файрвол хостинга) или в вашей сети блокируется WireGuard.
- `sudo systemctl status wg-quick@wg0` — состояние сервиса.
- Сервер перезагрузился — VPN поднимется автоматически.

## Важно

- Приватные ключи и конфиги лежат в `/etc/wireguard` на сервере — не публикуйте их.
- Соблюдайте законы своей страны и правила хостинг-провайдера.
