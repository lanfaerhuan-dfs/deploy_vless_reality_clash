#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERR ] 请使用 root 运行 install.sh"
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  echo "[ERR ] 无法识别系统"
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "debian" ]]; then
  echo "[ERR ] 仅支持 Debian 11~13"
  exit 1
fi
major="${VERSION_ID%%.*}"
if [[ "${major}" != "11" && "${major}" != "12" && "${major}" != "13" ]]; then
  echo "[ERR ] 仅支持 Debian 11~13，当前: ${VERSION_ID:-unknown}"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt update
apt -y install curl unzip jq nano ca-certificates ufw whiptail dialog

chmod +x "${SCRIPT_DIR}/vless-manager.sh"
chmod +x "${SCRIPT_DIR}/lib/common.sh"

exec "${SCRIPT_DIR}/vless-manager.sh"
