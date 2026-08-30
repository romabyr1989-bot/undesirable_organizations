#!/usr/bin/env bash
# Сборка комплекта поставки для Linux и macOS.
#
#   ./scripts/build.sh                       # собрать всё в dist/
#   ./scripts/build.sh --skip-ui             # только сервер (UI уже собран)
#   ./scripts/build.sh --with-sqlite /путь   # своя libsqlite3 в комплект
#   ./scripts/build.sh --no-sqlite           # не класть libsqlite3 совсем
#   ./scripts/build.sh --seed /путь.xlsx     # свой стартовый файл перечня
#   ./scripts/build.sh --no-seed             # без стартовых данных
#
# Результат: dist/perechen-<версия>-<ос>-<арх>/ и .tar.gz рядом.
# Кросс-компиляции у Dart нет: комплект собирается на той ОС, для которой он
# предназначен.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skip_ui=false
sqlite_lib=""
bundle_sqlite=true
seed_file=""
bundle_seed=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-ui) skip_ui=true; shift ;;
    --with-sqlite) sqlite_lib="${2:?путь к библиотеке}"; shift 2 ;;
    --no-sqlite) bundle_sqlite=false; shift ;;
    --seed) seed_file="${2:?путь к файлу перечня}"; shift 2 ;;
    --no-seed) bundle_seed=false; shift ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
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
  # Собираем с нуля. Следы прошлых сборок — особенно принесённые с другой
  # машины build/ и .dart_tool/ — сбивают инкрементальную сборку: она считает
  # свои же свежие файлы устаревшими и удаляет их. В комплект тогда уезжает
  # интерфейс без манифеста ресурсов, шрифта значков и статики из web/,
  # причём сборка завершается успешно и молча.
  (cd "$root/apps/ui" && flutter clean >/dev/null)
  # --no-web-resources-cdn: CanvasKit кладётся в комплект, иначе интерфейс
  #   в закрытом контуре не запускается (тянет его с gstatic.com).
  # --pwa-strategy=none: без служебного воркера, который кеширует сборку и
  #   после обновления службы показывает прежний интерфейс.
  # --no-tree-shake-icons: на части версий Flutter отсев неиспользуемых значков
  #   выбрасывает шрифт MaterialIcons целиком, и в интерфейсе вместо значков
  #   остаются пустые места. Лишние 1,5 МБ дешевле сломанного интерфейса.
  (cd "$root/apps/ui" && flutter pub get &&
    flutter build web --release --no-web-resources-cdn --pwa-strategy=none \
      --no-tree-shake-icons)
  # Заглушка поверх пустого файла, который оставляет сборка: снимает
  # регистрацию воркера у браузеров, открывавших сервис раньше.
  cp "$root/apps/ui/web/sw_killswitch.js" \
    "$root/apps/ui/build/web/flutter_service_worker.js"
fi
if [[ ! -d "$root/apps/ui/build/web" ]]; then
  echo "нет собранного UI: $root/apps/ui/build/web" >&2
  exit 1
fi
# Сборка интерфейса должна быть полной. Однажды в комплект уехал интерфейс без
# манифеста ресурсов, шрифта значков и статики: значки и логотип не рисовались,
# а сборка при этом прошла успешно и молча. Дешевле проверить здесь, чем
# обнаружить это на площадке.
web_build="$root/apps/ui/build/web"
for required in assets/AssetManifest.bin.json assets/FontManifest.json \
                assets/fonts/MaterialIcons-Regular.otf index.html main.dart.js; do
  [[ -f "$web_build/$required" ]] && continue
  echo "в сборке интерфейса нет $required" >&2
  echo "(следы прошлых сборок сбивают Flutter — помогает flutter clean)" >&2
  exit 1
done
cp -R "$root/apps/ui/build/web" "$stage/web"

echo "==> сервер"
(cd "$root/apps/server" && dart pub get)
(cd "$root/apps/server" && dart compile exe bin/server.dart -o "$stage/bin/perechen")
chmod +x "$stage/bin/perechen"

cp "$root/packages/core/assets/countries_ru.txt" "$stage/assets/"
# Недостающее звено цепочки сертификатов первоисточника: в закрытом контуре
# его неоткуда дотянуть, поэтому едет в комплекте.
cp "$root/apps/server/assets/ca-bundle.pem" "$stage/assets/"
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

# Библиотека SQLite. Комплект рассчитан на автономную установку, поэтому по
# умолчанию она кладётся внутрь: на «чистой» ОС пакета sqlite может не быть, а
# поставить его без доступа к репозиториям нельзя. Сервер ищет библиотеку
# сначала в lib/ комплекта, потом среди системных.
find_system_sqlite() {
  local name path
  if [[ "$os" == macos ]]; then
    for path in /usr/lib/libsqlite3.dylib /opt/homebrew/lib/libsqlite3.dylib; do
      [[ -f "$path" ]] && { echo "$path"; return 0; }
    done
    return 1
  fi
  for name in libsqlite3.so.0 libsqlite3.so; do
    path="$(ldconfig -p 2>/dev/null | awk -v n="$name" '$1 == n {print $NF; exit}')"
    [[ -n "$path" && -f "$path" ]] && { echo "$path"; return 0; }
  done
  for path in /usr/lib64/libsqlite3.so.0 /usr/lib/x86_64-linux-gnu/libsqlite3.so.0; do
    [[ -f "$path" ]] && { echo "$path"; return 0; }
  done
  return 1
}

if [[ "$bundle_sqlite" == false ]]; then
  echo "    библиотека SQLite: системная (по просьбе --no-sqlite)"
else
  if [[ -z "$sqlite_lib" ]]; then
    sqlite_lib="$(find_system_sqlite || true)"
  fi
  if [[ -z "$sqlite_lib" ]]; then
    echo "    библиотека SQLite не найдена — комплект рассчитывает на системную" >&2
  else
    [[ -f "$sqlite_lib" ]] || { echo "нет файла: $sqlite_lib" >&2; exit 1; }
    # Копируем под каноничным именем: символические ссылки в комплекте
    # бесполезны, а сервер ищет libsqlite3.so.0 / libsqlite3.dylib.
    target="libsqlite3.so.0"
    [[ "$os" == macos ]] && target="libsqlite3.dylib"
    cp -L "$sqlite_lib" "$stage/lib/$target"
    echo "    библиотека SQLite в комплекте: $target ($sqlite_lib)"
  fi
fi

# ------------------------------------------------- стартовые данные перечня
# После установки интерфейс не должен встречать ответственного пустым списком,
# поэтому в комплект кладётся свежий файл перечня: сервис подхватит его при
# первом запуске, пока база пуста. Отсутствие файла работе не мешает — список
# наполнится первой же проверкой сайта.
seed_target="$stage/assets/perechen-seed.xlsx"
if [[ "$bundle_seed" == false ]]; then
  echo "    стартовые данные: не кладём (по просьбе --no-seed)"
elif [[ -n "$seed_file" ]]; then
  [[ -f "$seed_file" ]] || { echo "нет файла: $seed_file" >&2; exit 1; }
  cp "$seed_file" "$seed_target"
  echo "    стартовые данные из файла: $seed_file"
else
  echo "==> стартовые данные с сайта Минюста"
  seed_url="$(sed -n 's/^MINJUST_EXPORT_URL: *//p' \
    "$root/apps/server/config.example.yaml" | head -1)"
  # Сервер Минюста присылает неполную цепочку сертификатов, поэтому к
  # системному хранилищу подставляем недостающее звено из комплекта.
  trust="$(mktemp)"
  cat "$stage/assets/ca-bundle.pem" > "$trust"
  for store in /etc/pki/tls/certs/ca-bundle.crt \
               /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem; do
    [[ -f "$store" ]] && { cat "$store" >> "$trust"; break; }
  done
  if curl -fsSL --max-time 180 --cacert "$trust" -o "$seed_target" "$seed_url" &&
     [[ -s "$seed_target" ]]; then
    echo "    скачано: $(wc -c < "$seed_target" | tr -d ' ') байт"
  else
    rm -f "$seed_target"
    echo "  ! стартовые данные не скачались. Комплект соберётся без них, но" >&2
    echo "    после установки список будет пуст до первой проверки сайта." >&2
    echo "    Свой файл: --seed <путь>; отказаться совсем: --no-seed" >&2
  fi
  rm -f "$trust"
fi

echo "==> проверка комплекта"
# Конфигурацию берём из самого комплекта, а не системную: на машине, где рядом
# установлена служба, /etc/perechen/config.yaml лежит с правами 640 root:perechen
# и сборщику не читается — проверка падала бы не на комплекте, а на окружении.
"$stage/bin/perechen" paths --config "$stage/config.example.yaml" || {
  echo "комплект собран, но 'perechen paths' завершился с ошибкой" >&2
  exit 1
}

# Контрольные суммы: в macOS есть только shasum, в RED OS/ALT — только
# sha256sum. Берём то, что нашлось на сборочной машине.
if command -v sha256sum >/dev/null 2>&1; then
  sha256=(sha256sum)
else
  sha256=(shasum -a 256)
fi

echo "==> опись комплекта"
{
  echo "# Комплект $name"
  echo "# собран $(date '+%Y-%m-%d %H:%M:%S %Z') на $(uname -srm)"
  if [[ "$os" == linux ]]; then
    echo "# glibc сборочной машины: $(ldd --version 2>/dev/null | head -1)"
    echo "#"
    echo "# Библиотеки, которые бинарник ждёт от целевой ОС:"
    ldd "$stage/bin/perechen" 2>/dev/null | sed 's/^/#   /' || true
  fi
  echo "#"
  echo "# sha256 файлов комплекта:"
  (cd "$stage" && find . -type f ! -name MANIFEST.txt -print0 |
    sort -z | xargs -0 "${sha256[@]}")
} > "$stage/MANIFEST.txt"
echo "    $(grep -c '^[0-9a-f]' "$stage/MANIFEST.txt") файлов"

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
