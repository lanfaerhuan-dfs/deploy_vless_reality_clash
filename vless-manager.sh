#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

XRAY_INSTALL_SCRIPT_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
TEMPLATE_PATH="${SCRIPT_DIR}/templates/config.reality.json.tpl"
STATE_FILE="/root/.vless_reality_state"

require_root
ensure_debian_11_13

need_ui() {
  command -v whiptail >/dev/null 2>&1 || command -v dialog >/dev/null 2>&1
}

ui_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local out=""

  if command -v whiptail >/dev/null 2>&1; then
    out=$(whiptail --title "${title}" --inputbox "${prompt}" 12 72 "${default_value}" 3>&1 1>&2 2>&3) || return 1
  else
    out=$(dialog --stdout --title "${title}" --inputbox "${prompt}" 12 72 "${default_value}") || return 1
  fi
  printf '%s' "${out}"
}

ui_msg() {
  local title="$1"
  local msg="$2"
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "${title}" --msgbox "${msg}" 16 80
  else
    dialog --stdout --title "${title}" --msgbox "${msg}" 16 80 >/dev/null
  fi
}

ui_yesno() {
  local title="$1"
  local prompt="$2"
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "${title}" --yesno "${prompt}" 12 72
  else
    dialog --stdout --title "${title}" --yesno "${prompt}" 12 72
  fi
}

ui_menu() {
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "VLESS Reality 管理器" --menu "请选择操作" 22 90 12 \
      "1" "安装/重装 Xray" \
      "2" "初始化/更新 VLESS Reality 配置" \
      "3" "轮换 UUID + Reality 密钥" \
      "4" "服务状态（systemctl + 监听端口）" \
      "5" "查看最近日志（journalctl）" \
      "6" "配置防火墙 UFW（22 + 业务端口 + 可选80）" \
      "7" "导出节点信息" \
      "8" "卸载 Xray" \
      "9" "退出" 3>&1 1>&2 2>&3
  else
    dialog --stdout --title "VLESS Reality 管理器" --menu "请选择操作" 22 90 12 \
      "1" "安装/重装 Xray" \
      "2" "初始化/更新 VLESS Reality 配置" \
      "3" "轮换 UUID + Reality 密钥" \
      "4" "服务状态（systemctl + 监听端口）" \
      "5" "查看最近日志（journalctl）" \
      "6" "配置防火墙 UFW（22 + 业务端口 + 可选80）" \
      "7" "导出节点信息" \
      "8" "卸载 Xray" \
      "9" "退出"
  fi
}

load_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
  fi
}

save_state() {
  cat > "${STATE_FILE}" <<STATE
PORT="${PORT:-443}"
SNI="${SNI:-www.amazon.com}"
UUID="${UUID:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
PUBLIC_KEY="${PUBLIC_KEY:-}"
VPS_IP="${VPS_IP:-}"
STATE
  chmod 600 "${STATE_FILE}"
}

get_public_ip() {
  curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true
}

install_or_reinstall_xray() {
  log_info "安装/重装 Xray..."
  bash -c "$(curl -L ${XRAY_INSTALL_SCRIPT_URL})" @ install
  systemctl enable xray >/dev/null 2>&1 || true
  log_ok "Xray 安装完成。"
}

generate_uuid() {
  xray uuid
}

generate_keypair() {
  local output
  output="$(xray x25519)"
  PRIVATE_KEY="$(awk -F': ' '/Private key|PrivateKey/{print $2}' <<<"${output}" | tr -d '[:space:]')"
  PUBLIC_KEY="$(awk -F': ' '/Public key|PublicKey|Password/{print $2}' <<<"${output}" | tr -d '[:space:]')"
  if [[ -z "${PRIVATE_KEY:-}" || -z "${PUBLIC_KEY:-}" ]]; then
    log_err "解析 x25519 输出失败，请手动执行 xray x25519 检查。"
    return 1
  fi
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

write_config() {
  [[ -f "${TEMPLATE_PATH}" ]] || { log_err "模板不存在：${TEMPLATE_PATH}"; return 1; }
  backup_config_if_exists
  mkdir -p /usr/local/etc/xray

  sed \
    -e "s|__PORT__|${PORT}|g" \
    -e "s|__UUID__|${UUID}|g" \
    -e "s|__PRIVATE_KEY__|${PRIVATE_KEY}|g" \
    -e "s|__SNI__|${SNI}|g" \
    "${TEMPLATE_PATH}" > "${CONFIG_PATH}"
}

test_and_restart_xray() {
  if ! xray run -test -config "${CONFIG_PATH}"; then
    log_err "配置校验失败，尝试回滚。"
    restore_latest_backup || true
    return 1
  fi

  systemctl restart xray
  systemctl enable xray >/dev/null 2>&1 || true
  log_ok "Xray 已重启并启用开机自启。"
}

configure_firewall() {
  require_cmd ufw || { apt update && apt -y install ufw; }

  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow "${PORT}"/tcp

  if ui_yesno "防火墙" "是否放行 80/tcp（可选）？"; then
    ufw allow 80/tcp
  fi

  ufw --force enable
  local status
  status="$(ufw status verbose || true)"
  ui_msg "UFW 状态" "${status}\n\n请同时确认云厂商安全组已放行端口。"
}

init_or_update_config() {
  require_cmd xray || { ui_msg "错误" "未检测到 xray，请先执行“安装/重装 Xray”。"; return; }

  load_state

  local p s
  p="$(ui_input "配置" "请输入服务端口（1-65535）" "${PORT:-443}")" || return
  validate_port "${p}" || { ui_msg "错误" "端口无效。"; return; }
  s="$(ui_input "配置" "请输入 SNI/伪装域名（如 www.amazon.com）" "${SNI:-www.amazon.com}")" || return

  PORT="${p}"
  SNI="${s}"

  if [[ -z "${UUID:-}" ]]; then
    UUID="$(generate_uuid)"
  fi
  if [[ -z "${PRIVATE_KEY:-}" || -z "${PUBLIC_KEY:-}" ]]; then
    generate_keypair || { ui_msg "错误" "密钥生成失败。"; return; }
  fi

  VPS_IP="$(get_public_ip)"

  write_config || { ui_msg "错误" "写入配置失败。"; return; }
  test_and_restart_xray || { ui_msg "错误" "配置测试或重启失败，请查看日志。"; return; }
  save_state

  ui_msg "完成" "配置已生效。\nPORT=${PORT}\nSNI=${SNI}\nUUID=${UUID}\nPublicKey=${PUBLIC_KEY}"
}

rotate_credentials() {
  require_cmd xray || { ui_msg "错误" "未检测到 xray。"; return; }
  load_state

  if [[ ! -f "${CONFIG_PATH}" ]]; then
    ui_msg "错误" "配置文件不存在，请先初始化配置。"
    return
  fi

  if [[ -z "${SNI:-}" || -z "${PORT:-}" ]]; then
    ui_msg "提示" "未检测到历史状态，将使用默认值 PORT=443, SNI=www.amazon.com。"
    PORT="${PORT:-443}"
    SNI="${SNI:-www.amazon.com}"
  fi

  UUID="$(generate_uuid)"
  generate_keypair || { ui_msg "错误" "密钥生成失败。"; return; }
  VPS_IP="$(get_public_ip)"

  write_config || { ui_msg "错误" "写入配置失败。"; return; }
  test_and_restart_xray || { ui_msg "错误" "配置测试或重启失败。"; return; }
  save_state

  ui_msg "完成" "已轮换 UUID + 密钥。\nUUID=${UUID}\nPublicKey=${PUBLIC_KEY}"
}

show_status() {
  load_state
  local port_show="${PORT:-443}"
  local status_text listening
  status_text="$(systemctl status xray --no-pager 2>&1 || true)"
  listening="$(ss -lntp 2>/dev/null | grep ":${port_show} " || true)"
  if [[ -z "${listening}" ]]; then
    listening="未检测到 :${port_show} 监听（可能端口不是 ${port_show} 或服务未启动）"
  fi
  ui_msg "服务状态" "${status_text}\n\n监听信息:\n${listening}"
}

show_logs() {
  local logs
  logs="$(journalctl -u xray -n 80 --no-pager 2>&1 || true)"
  ui_msg "最近日志" "${logs}"
}

export_node_info() {
  load_state
  local ip="${VPS_IP:-$(get_public_ip)}"

  if [[ -z "${UUID:-}" || -z "${PUBLIC_KEY:-}" || -z "${SNI:-}" || -z "${PORT:-}" ]]; then
    ui_msg "错误" "缺少关键参数，请先执行初始化/更新配置。"
    return
  fi

  cat > "${INFO_FILE}" <<INFO
# VLESS Reality 节点信息
Address: ${ip}
Port: ${PORT}
UUID: ${UUID}
Flow: xtls-rprx-vision
Network: tcp
Security: reality
SNI: ${SNI}
PublicKey: ${PUBLIC_KEY}
ShortID:

# Clash.Meta 示例
- name: "VLESS-REALITY-VISION"
  type: vless
  server: ${ip}
  port: ${PORT}
  uuid: "${UUID}"
  network: tcp
  tls: false
  flow: xtls-rprx-vision
  servername: ${SNI}
  client-fingerprint: chrome
  reality-opts:
    public-key: ${PUBLIC_KEY}
    short-id: ""
INFO
  chmod 600 "${INFO_FILE}"
  ui_msg "导出完成" "已导出到 ${INFO_FILE}"
}

uninstall_xray() {
  if ! ui_yesno "确认" "确定要卸载 Xray 吗？"; then
    return
  fi
  bash -c "$(curl -L ${XRAY_INSTALL_SCRIPT_URL})" @ remove
  ui_msg "完成" "Xray 已卸载。"
}

main() {
  if ! need_ui; then
    log_err "缺少 whiptail/dialog，请先运行 install.sh 安装依赖。"
    exit 1
  fi

  while true; do
    local choice
    choice="$(ui_menu)" || break
    case "${choice}" in
      1) install_or_reinstall_xray ;;
      2) init_or_update_config ;;
      3) rotate_credentials ;;
      4) show_status ;;
      5) show_logs ;;
      6) load_state; PORT="${PORT:-443}"; configure_firewall ;;
      7) export_node_info ;;
      8) uninstall_xray ;;
      9) break ;;
      *) ui_msg "提示" "未知选项：${choice}" ;;
    esac
  done
}

main "$@"
