#!/usr/bin/env bash
# Установка личного VPN-сервера WireGuard на VPS (Ubuntu 22.04/24.04, Debian 11/12).
# Запуск на сервере в США:   sudo bash wireguard-install.sh
# Добавить ещё устройство:   sudo bash wireguard-install.sh add <имя>
# Список устройств:          sudo bash wireguard-install.sh list
# Удалить устройство:        sudo bash wireguard-install.sh remove <имя>
set -euo pipefail

WG_IF="wg0"
WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/$WG_IF.conf"
CLIENT_DIR="$WG_DIR/clients"
PARAMS="$WG_DIR/params"
WG_PORT="${WG_PORT:-51820}"
WG_NET="10.66.66"          # подсеть VPN: 10.66.66.0/24
CLIENT_DNS="${CLIENT_DNS:-1.1.1.1, 1.0.0.1}"

die() { echo "Ошибка: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "запустите через sudo"
[[ -r /etc/os-release ]] || die "не удалось определить ОС"
. /etc/os-release
[[ "$ID" == "ubuntu" || "$ID" == "debian" ]] || die "поддерживаются только Ubuntu и Debian (у вас: $ID)"

valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "имя устройства: латиница, цифры, _ и -, до 32 символов"; }

install_server() {
  if [[ -f "$WG_CONF" ]]; then
    echo "WireGuard уже установлен. Используйте: add <имя> | list | remove <имя>"
    exit 0
  fi

  echo "==> Установка пакетов"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard qrencode iptables curl

  PUB_NIC="$(ip -4 route show default | awk '{print $5; exit}')"
  [[ -n "$PUB_NIC" ]] || die "не найден сетевой интерфейс по умолчанию"
  PUB_IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org || ip -4 addr show "$PUB_NIC" | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')"
  [[ -n "$PUB_IP" ]] || die "не удалось определить публичный IP"

  echo "==> Публичный IP: $PUB_IP, интерфейс: $PUB_NIC, порт: $WG_PORT/udp"
  COUNTRY="$(curl -fsS --max-time 5 "https://ipinfo.io/$PUB_IP/country" 2>/dev/null || true)"
  [[ -n "$COUNTRY" && "$COUNTRY" != "US" ]] && echo "ВНИМАНИЕ: сервер определяется как '$COUNTRY', а не US. Проверьте регион VPS."

  umask 077
  mkdir -p "$CLIENT_DIR"
  SERVER_PRIV="$(wg genkey)"
  SERVER_PUB="$(echo "$SERVER_PRIV" | wg pubkey)"

  cat > "$PARAMS" <<EOF
PUB_IP=$PUB_IP
PUB_NIC=$PUB_NIC
WG_PORT=$WG_PORT
SERVER_PUB=$SERVER_PUB
EOF

  cat > "$WG_CONF" <<EOF
[Interface]
Address = $WG_NET.1/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $PUB_NIC -j MASQUERADE; iptables -I INPUT -p udp --dport $WG_PORT -j ACCEPT
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $PUB_NIC -j MASQUERADE; iptables -D INPUT -p udp --dport $WG_PORT -j ACCEPT
EOF

  echo "==> Включение маршрутизации"
  echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
  sysctl --system >/dev/null

  if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "$WG_PORT/udp"
    sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    ufw reload
  fi

  systemctl enable --now "wg-quick@$WG_IF"
  echo "==> Сервер запущен"

  add_client "phone"
  echo
  echo "Готово. Ещё устройство: sudo bash $0 add laptop"
  echo "Не забудьте открыть порт $WG_PORT/udp в файрволе панели хостинга, если он там есть."
}

add_client() {
  local name="$1"; valid_name "$name"
  [[ -f "$PARAMS" ]] || die "сервер ещё не установлен"
  . "$PARAMS"
  [[ -f "$CLIENT_DIR/$name.conf" ]] && die "устройство '$name' уже существует"

  local octet
  for octet in $(seq 2 254); do
    grep -q "AllowedIPs = $WG_NET.$octet/32" "$WG_CONF" || break
  done
  grep -q "AllowedIPs = $WG_NET.$octet/32" "$WG_CONF" && die "нет свободных адресов"

  umask 077
  local priv pub psk
  priv="$(wg genkey)"; pub="$(echo "$priv" | wg pubkey)"; psk="$(wg genpsk)"

  cat >> "$WG_CONF" <<EOF

### client $name
[Peer]
PublicKey = $pub
PresharedKey = $psk
AllowedIPs = $WG_NET.$octet/32
EOF

  cat > "$CLIENT_DIR/$name.conf" <<EOF
[Interface]
PrivateKey = $priv
Address = $WG_NET.$octet/32
DNS = $CLIENT_DNS

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $psk
Endpoint = $PUB_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")

  echo
  echo "==> Устройство '$name' добавлено. Конфиг: $CLIENT_DIR/$name.conf"
  echo "Отсканируйте QR-код в приложении WireGuard (телефон):"
  qrencode -t ansiutf8 < "$CLIENT_DIR/$name.conf"
}

list_clients() {
  grep -oP '^### client \K.*' "$WG_CONF" 2>/dev/null || echo "(нет устройств)"
}

remove_client() {
  local name="$1"; valid_name "$name"
  grep -q "^### client $name\$" "$WG_CONF" || die "устройство '$name' не найдено"
  # удалить блок: строка-метка, пустая строка перед ней и 4 строки [Peer]
  sed -i "/^### client $name\$/,+4d" "$WG_CONF"
  sed -i '/^$/N;/^\n$/D' "$WG_CONF"   # убрать двойные пустые строки
  rm -f "$CLIENT_DIR/$name.conf"
  wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")
  echo "Устройство '$name' удалено"
}

case "${1:-install}" in
  install) install_server ;;
  add)     [[ -n "${2:-}" ]] || die "укажите имя: add <имя>"; add_client "$2" ;;
  list)    list_clients ;;
  remove)  [[ -n "${2:-}" ]] || die "укажите имя: remove <имя>"; remove_client "$2" ;;
  *)       die "неизвестная команда '$1' (install | add <имя> | list | remove <имя>)" ;;
esac
