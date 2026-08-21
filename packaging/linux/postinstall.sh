#!/bin/sh
# Выполняется пакетным менеджером после установки .deb/.rpm.
set -e

data_dir=/var/lib/perechen
cdi_dir=/mnt/cdi/inbox
config_dir=/etc/perechen

if ! id -u perechen >/dev/null 2>&1; then
  nologin_shell="$(command -v nologin || echo /sbin/nologin)"
  useradd --system --home-dir "$data_dir" --no-create-home \
          --shell "$nologin_shell" perechen
fi

install -d -o perechen -g perechen -m 750 \
  "$data_dir" "$data_dir/downloads" "$data_dir/published"
install -d -o perechen -g perechen -m 775 "$cdi_dir"
install -d -m 755 "$config_dir"

if [ ! -f "$config_dir/config.yaml" ]; then
  cp /opt/perechen/config.example.yaml "$config_dir/config.yaml"
  chown root:perechen "$config_dir/config.yaml"
  # В файле пароли SMTP и basic-auth.
  chmod 640 "$config_dir/config.yaml"
fi

if command -v restorecon >/dev/null 2>&1; then
  restorecon -R /opt/perechen "$data_dir" 2>/dev/null || true
fi

systemctl daemon-reload || true
systemctl enable perechen.service || true
systemctl restart perechen.service || true

cat <<EOF
Служба perechen установлена.
  конфигурация: $config_dir/config.yaml  <- задайте SMTP, получателей, пароль
  после правки: systemctl restart perechen
EOF
