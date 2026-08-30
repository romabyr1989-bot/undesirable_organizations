#!/usr/bin/env bash
# Установка службы перечня 272-ФЗ на macOS (демон launchd).
#
#   sudo ./install.sh
#   sudo ./install.sh --cdi-dir /Volumes/cdi/inbox --port 8080
#
# Повторный запуск обновляет установку, сохраняя данные и config.yaml.
set -euo pipefail

prefix=/usr/local/perechen
data_dir=/usr/local/var/perechen
cdi_dir=""
config_dir=/usr/local/etc/perechen
port=8080
label=ru.perechen.server

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)   prefix="${2:?}"; shift 2 ;;
    --data-dir) data_dir="${2:?}"; shift 2 ;;
    --cdi-dir)  cdi_dir="${2:?}"; shift 2 ;;
    --port)     port="${2:?}"; shift 2 ;;
    -h|--help)  sed -n '2,7p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "запустите с правами root (sudo)" >&2; exit 1; }
[[ -n "$cdi_dir" ]] || cdi_dir="$data_dir/cdi-inbox"

bundle="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
в отдельный каталог и запустите install.sh оттуда, либо укажите --prefix.
EOF
  exit 1
fi

plist="/Library/LaunchDaemons/$label.plist"
log_file="$data_dir/logs/perechen.log"
error_log="$data_dir/logs/perechen.err.log"

if launchctl print "system/$label" >/dev/null 2>&1; then
  echo "==> останавливаем текущий демон"
  launchctl bootout "system/$label" 2>/dev/null || true
fi

echo "==> файлы в $prefix"
mkdir -p "$prefix"
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
chown -R root:wheel "$prefix"
chmod 755 "$prefix/bin/perechen"

echo "==> каталоги данных"
mkdir -p "$data_dir/downloads" "$data_dir/published" "$data_dir/logs" "$cdi_dir"

echo "==> конфигурация $config_dir/config.yaml"
mkdir -p "$config_dir"
if [[ -f "$config_dir/config.yaml" ]]; then
  echo "    файл уже есть — оставляем как есть"
else
  sed -e "s#^DATA_DIR:.*#DATA_DIR: $data_dir#" \
      -e "s#^CDI_DROP_DIR:.*#CDI_DROP_DIR: $cdi_dir#" \
      -e "s|^#\{0,1\} *LOG_FILE:.*|LOG_FILE: $log_file|" \
      -e "s#^PORT:.*#PORT: $port#" \
      "$bundle/config.example.yaml" > "$config_dir/config.yaml"
  # В файле пароли SMTP и basic-auth.
  chown root:wheel "$config_dir/config.yaml"
  chmod 600 "$config_dir/config.yaml"
fi

echo "==> демон launchd"
sed -e "s#@@PREFIX@@#$prefix#g" \
    -e "s#@@CONFIG@@#$config_dir/config.yaml#g" \
    -e "s#@@ERROR_LOG@@#$error_log#g" \
    "$prefix/packaging/ru.perechen.server.plist.template" > "$plist"
chown root:wheel "$plist"
chmod 644 "$plist"

launchctl bootstrap system "$plist"
launchctl enable "system/$label"

echo "==> проверка"
sleep 2
if launchctl print "system/$label" >/dev/null 2>&1; then
  echo "    демон загружен"
else
  echo "    демон не загрузился, журнал:" >&2
  [[ -f "$error_log" ]] && tail -n 30 "$error_log" >&2
  exit 1
fi

cat <<EOF

Установлено.
  программа:      $prefix
  данные:         $data_dir
  папка CDI:      $cdi_dir
  конфигурация:   $config_dir/config.yaml   <- задайте SMTP, получателей, пароль
  журнал:         $log_file
  интерфейс:      http://localhost:$port

Дальше:
  sudo nano $config_dir/config.yaml
  sudo launchctl kickstart -k system/$label
  tail -f $log_file
  $prefix/bin/perechen paths --config $config_dir/config.yaml
EOF
