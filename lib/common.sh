#!/usr/bin/env bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="/usr/local/etc/xray/config.json"
BACKUP_DIR="/usr/local/etc/xray/backup"
INFO_FILE="/root/vless_reality_node_info.txt"

log_info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_ok() { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_err() { echo -e "\033[1;31m[ERR ]\033[0m $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_err "请使用 root 用户执行。"
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_err "缺少命令：${cmd}"
    return 1
  fi
}

ensure_debian_11_13() {
  if [[ ! -f /etc/os-release ]]; then
    log_err "无法识别系统（缺少 /etc/os-release）。"
    return 1
  fi
  . /etc/os-release
  if [[ "${ID:-}" != "debian" ]]; then
    log_err "仅支持 Debian 11~13。当前：${PRETTY_NAME:-unknown}"
    return 1
  fi

  local major
  major="${VERSION_ID%%.*}"
  case "${major}" in
    11|12|13) ;;
    *)
      log_err "仅支持 Debian 11~13。当前版本：${VERSION_ID:-unknown}"
      return 1
      ;;
  esac
}

backup_config_if_exists() {
  if [[ -f "${CONFIG_PATH}" ]]; then
    mkdir -p "${BACKUP_DIR}"
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    cp -a "${CONFIG_PATH}" "${BACKUP_DIR}/config.json.${ts}.bak"
    log_ok "已备份配置：${BACKUP_DIR}/config.json.${ts}.bak"
  fi
}

restore_latest_backup() {
  if [[ ! -d "${BACKUP_DIR}" ]]; then
    log_warn "没有可回滚的备份目录。"
    return 1
  fi
  local latest
  latest="$(ls -1t "${BACKUP_DIR}"/config.json.*.bak 2>/dev/null | head -n1 || true)"
  if [[ -z "${latest}" ]]; then
    log_warn "没有可回滚的备份文件。"
    return 1
  fi
  cp -a "${latest}" "${CONFIG_PATH}"
  log_ok "已回滚到最新备份：${latest}"
}

systemctl_daemon_reload() {
  systemctl daemon-reload >/dev/null 2>&1 || true
}
