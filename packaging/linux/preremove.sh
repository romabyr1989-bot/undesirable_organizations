#!/bin/sh
# Выполняется пакетным менеджером перед удалением .deb/.rpm.
set -e
systemctl disable --now perechen.service 2>/dev/null || true
