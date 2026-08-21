#!/usr/bin/env bash
# Удаление службы перечня 272-ФЗ.
#
#   sudo ./uninstall.sh            # снять службу, данные оставить
#   sudo ./uninstall.sh --purge    # снять службу и удалить данные с настройками
set -euo pipefail

prefix=/opt/perechen
data_dir=/var/lib/perechen
config_dir=/etc/perechen
service_user=perechen
service_name=perechen
purge=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)   prefix="${2:?}"; shift 2 ;;
    --data-dir) data_dir="${2:?}"; shift 2 ;;
    --purge)    purge=true; shift ;;
    -h|--help)  sed -n '2,6p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "запустите с правами root (sudo)" >&2; exit 1; }

systemctl disable --now "$service_name" 2>/dev/null || true
rm -f "/etc/systemd/system/$service_name.service"
systemctl daemon-reload
rm -rf "${prefix:?}"

if [[ "$purge" == true ]]; then
  rm -rf "${data_dir:?}" "${config_dir:?}"
  userdel "$service_user" 2>/dev/null || true
  echo "Удалено вместе с данными и настройками."
else
  echo "Служба снята. Данные ($data_dir) и настройки ($config_dir) оставлены."
fi
