#!/usr/bin/env bash
# Установка службы перечня 272-ФЗ на Linux (Debian/Ubuntu/Astra, RED OS/ALT).
#
#   sudo ./install.sh
#   sudo ./install.sh --data-dir /srv/perechen --cdi-dir /mnt/cdi/inbox --port 8080
#   sudo ./install.sh --open-firewall        # заодно открыть порт в firewalld
#
# Повторный запуск обновляет установленную службу, сохраняя данные и
# /etc/perechen/config.yaml.
set -euo pipefail

prefix=/opt/perechen
data_dir=/var/lib/perechen
cdi_dir=/mnt/cdi/inbox
config_dir=/etc/perechen
service_user=perechen
port=8080
service_name=perechen
open_firewall=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)   prefix="${2:?}"; shift 2 ;;
    --data-dir) data_dir="${2:?}"; shift 2 ;;
    --cdi-dir)  cdi_dir="${2:?}"; shift 2 ;;
    --user)     service_user="${2:?}"; shift 2 ;;
    --port)     port="${2:?}"; shift 2 ;;
    --open-firewall) open_firewall=true; shift ;;
    -h|--help)  sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "запустите с правами root (sudo)" >&2; exit 1; }
command -v systemctl >/dev/null || {
  echo "не найден systemd: установите службу вручную (см. README)" >&2
  exit 1
}

bundle="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
[[ -x "$bundle/bin/perechen" ]] || {
  echo "в комплекте нет bin/perechen: $bundle" >&2
  exit 1
}

# Комплект не должен лежать внутри каталога установки и наоборот: каталоги
# заменяются целиком, и при пересечении путей установщик удалил бы файлы,
# которые сам же собирается копировать.
if [[ "$bundle" == "$prefix" || "$bundle" == "$prefix"/* || "$prefix" == "$bundle"/* ]]; then
  cat >&2 <<EOF
Комплект распакован внутри каталога установки:
  комплект:  $bundle
  установка: $prefix
Так ставить нельзя — установщик удалил бы исходные файлы. Распакуйте архив
в отдельный каталог (например, ~/perechen-install) и запустите install.sh
оттуда, либо укажите другой --prefix.
EOF
  exit 1
fi

echo "==> пользователь $service_user"
if ! id -u "$service_user" >/dev/null 2>&1; then
  nologin_shell="$(command -v nologin || echo /sbin/nologin)"
  useradd --system --home-dir "$data_dir" --no-create-home \
          --shell "$nologin_shell" "$service_user"
fi

# Служба может быть запущена: остановим перед заменой файлов.
if systemctl is-active --quiet "$service_name"; then
  echo "==> останавливаем текущую службу"
  systemctl stop "$service_name"
fi

echo "==> файлы в $prefix"
mkdir -p "$prefix"
# Каталоги комплекта заменяем целиком, чтобы не оставлять файлы прошлой версии.
# Сначала копия рядом, потом замена: сорвавшееся копирование не должно
# оставлять установку без файлов.
for item in bin lib web assets packaging; do
  [[ -e "$bundle/$item" ]] || continue
  rm -rf "${prefix:?}/$item.new"
  cp -R "$bundle/$item" "$prefix/$item.new"
  rm -rf "${prefix:?}/$item"
  mv "$prefix/$item.new" "$prefix/$item"
done
[[ -f "$bundle/README.md" ]] && cp "$bundle/README.md" "$prefix/"
cp "$bundle/config.example.yaml" "$prefix/config.example.yaml"
chown -R root:root "$prefix"
chmod 755 "$prefix/bin/perechen"

echo "==> каталоги данных"
install -d -o "$service_user" -g "$service_user" -m 750 \
  "$data_dir" "$data_dir/downloads" "$data_dir/published"
install -d -o "$service_user" -g "$service_user" -m 775 "$cdi_dir"

echo "==> конфигурация $config_dir/config.yaml"
install -d -m 755 "$config_dir"
if [[ -f "$config_dir/config.yaml" ]]; then
  echo "    файл уже есть — оставляем как есть"
else
  sed -e "s#^DATA_DIR:.*#DATA_DIR: $data_dir#" \
      -e "s#^CDI_DROP_DIR:.*#CDI_DROP_DIR: $cdi_dir#" \
      -e "s#^PORT:.*#PORT: $port#" \
      "$bundle/config.example.yaml" > "$config_dir/config.yaml"
  chown "root:$service_user" "$config_dir/config.yaml"
  # В файле пароли SMTP и basic-auth: читать может только служба.
  chmod 640 "$config_dir/config.yaml"
fi

echo "==> юнит systemd"
sed -e "s#@@PREFIX@@#$prefix#g" \
    -e "s#@@USER@@#$service_user#g" \
    -e "s#@@CONFIG@@#$config_dir/config.yaml#g" \
    -e "s#@@DATA_DIR@@#$data_dir#g" \
    -e "s#@@CDI_DIR@@#$cdi_dir#g" \
    "$prefix/packaging/perechen.service.template" \
    > "/etc/systemd/system/$service_name.service"
chmod 644 "/etc/systemd/system/$service_name.service"

# SELinux (RED OS, ALT): восстановить контексты скопированных файлов.
if command -v restorecon >/dev/null 2>&1; then
  restorecon -R "$prefix" "$data_dir" 2>/dev/null || true
fi

# Межсетевой экран. На серверной установке RED OS/ALT firewalld включён, и
# интерфейс снаружи не открывается, хотя служба работает и порт слушает.
# Экран трогаем только по явной просьбе (как -OpenFirewall в Windows),
# в остальных случаях — предупреждаем.
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1
then
  if [[ "$open_firewall" == true ]]; then
    echo "==> firewalld: открываем $port/tcp"
    firewall-cmd --permanent --add-port="$port/tcp" >/dev/null
    firewall-cmd --reload >/dev/null
  elif ! firewall-cmd --query-port="$port/tcp" >/dev/null 2>&1; then
    echo "    firewalld включён, порт $port/tcp закрыт — снаружи интерфейс"
    echo "    не откроется. Открыть: firewall-cmd --permanent --add-port=$port/tcp"
    echo "    и firewall-cmd --reload (или переустановка с --open-firewall)."
  fi
fi

systemctl daemon-reload
systemctl enable --now "$service_name"

echo "==> проверка"
sleep 2
if systemctl is-active --quiet "$service_name"; then
  echo "    служба запущена"
else
  echo "    служба не поднялась, журнал:" >&2
  journalctl -u "$service_name" -n 30 --no-pager >&2
  exit 1
fi

cat <<EOF

Установлено.
  программа:      $prefix
  данные:         $data_dir
  папка CDI:      $cdi_dir
  конфигурация:   $config_dir/config.yaml   <- задайте SMTP, получателей, пароль
  интерфейс:      http://$(hostname -f 2>/dev/null || hostname):$port

Дальше:
  sudo nano $config_dir/config.yaml
  sudo systemctl restart $service_name
  systemctl status $service_name
  journalctl -u $service_name -f
  $prefix/bin/perechen paths --config $config_dir/config.yaml
EOF
