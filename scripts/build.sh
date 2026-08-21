#!/usr/bin/env bash
# Сборка комплекта поставки для Linux и macOS.
#
#   ./scripts/build.sh                       # собрать всё в dist/
#   ./scripts/build.sh --skip-ui             # только сервер (UI уже собран)
#   ./scripts/build.sh --with-sqlite /путь   # положить libsqlite3 в комплект
#
# Результат: dist/perechen-<версия>-<ос>-<арх>/ и .tar.gz рядом.
# Кросс-компиляции у Dart нет: комплект собирается на той ОС, для которой он
# предназначен.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skip_ui=false
sqlite_lib=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-ui) skip_ui=true; shift ;;
    --with-sqlite) sqlite_lib="${2:?путь к библиотеке}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

case "$(uname -s)" in
  Linux)  os=linux ;;
  Darwin) os=macos ;;
  *) echo "неподдерживаемая ОС: $(uname -s). Для Windows — build\\build.ps1" >&2
     exit 2 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) arch=x64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) arch="$(uname -m)" ;;
esac

version="$(sed -n 's/^version: *//p' "$root/apps/server/pubspec.yaml" | head -1)"
name="perechen-${version}-${os}-${arch}"
stage="$root/dist/$name"

command -v dart >/dev/null || { echo "не найден dart (нужен SDK >= 3.5)" >&2; exit 1; }
if [[ "$skip_ui" == false ]]; then
  command -v flutter >/dev/null || {
    echo "не найден flutter (нужен >= 3.24) — или соберите с --skip-ui" >&2
    exit 1
  }
fi

echo "==> комплект $name"
rm -rf "$stage"
mkdir -p "$stage/bin" "$stage/lib" "$stage/assets" "$stage/packaging"

if [[ "$skip_ui" == false ]]; then
  echo "==> Flutter Web"
  (cd "$root/apps/ui" && flutter pub get && flutter build web --release)
fi
if [[ ! -d "$root/apps/ui/build/web" ]]; then
  echo "нет собранного UI: $root/apps/ui/build/web" >&2
  exit 1
fi
cp -R "$root/apps/ui/build/web" "$stage/web"

echo "==> сервер"
(cd "$root/apps/server" && dart pub get)
(cd "$root/apps/server" && dart compile exe bin/server.dart -o "$stage/bin/perechen")
chmod +x "$stage/bin/perechen"

cp "$root/packages/core/assets/countries_ru.txt" "$stage/assets/"
cp "$root/apps/server/config.example.yaml" "$stage/config.example.yaml"
cp -R "$root/packaging/$os/." "$stage/packaging/"

# Готовый юнит с путями по умолчанию — для сборки .deb/.rpm через nfpm.
# install.sh собирает свой из того же шаблона, с путями установки.
if [[ "$os" == linux ]]; then
  sed -e "s#@@PREFIX@@#/opt/perechen#g" \
      -e "s#@@USER@@#perechen#g" \
      -e "s#@@CONFIG@@#/etc/perechen/config.yaml#g" \
      -e "s#@@DATA_DIR@@#/var/lib/perechen#g" \
      -e "s#@@CDI_DIR@@#/mnt/cdi/inbox#g" \
      "$root/packaging/linux/perechen.service.template" \
      > "$stage/packaging/perechen.service"
fi
[[ -f "$root/README.md" ]] && cp "$root/README.md" "$stage/README.md"

# Библиотека SQLite. По умолчанию берётся системная (есть и в Linux, и в
# macOS); --with-sqlite кладёт свою — например, для машин без libsqlite3.so.
if [[ -n "$sqlite_lib" ]]; then
  [[ -f "$sqlite_lib" ]] || { echo "нет файла: $sqlite_lib" >&2; exit 1; }
  cp "$sqlite_lib" "$stage/lib/"
  echo "    библиотека SQLite в комплекте: $(basename "$sqlite_lib")"
else
  echo "    библиотека SQLite: системная (проверка ниже)"
fi

echo "==> проверка комплекта"
"$stage/bin/perechen" paths || {
  echo "комплект собран, но 'perechen paths' завершился с ошибкой" >&2
  exit 1
}

echo "==> архив"
(cd "$root/dist" && tar -czf "$name.tar.gz" "$name")

cat <<EOF

Готово:
  каталог: dist/$name
  архив:   dist/$name.tar.gz

Установка службы:
  sudo dist/$name/packaging/install.sh
EOF

if [[ "$os" == linux ]] && command -v nfpm >/dev/null 2>&1; then
  cat <<EOF
Пакеты (необязательно, найден nfpm):
  cd dist/$name && VERSION=$version ARCH=${arch/x64/amd64} \\
    MAINTAINER="ops@corp.example" VENDOR="corp" \\
    nfpm package -f packaging/nfpm.yaml -p deb -t ..
EOF
fi
