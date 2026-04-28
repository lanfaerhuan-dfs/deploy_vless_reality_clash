# VLESS Reality 一键部署与维护（Debian 11~13）

这是一个基于 **Bash + whiptail/dialog TUI** 的 VLESS + REALITY（XTLS Vision）自动化部署与维护工具。

## 快速开始

> 推荐 root 用户执行。

```bash
bash <(curl -fsSL URL)
```

> 你只需要把 `URL` 替换成你发布后的安装脚本地址。

## 本地运行（开发/测试）

```bash
bash install.sh
```

## 功能（单入站、单用户）

- 安装/重装 Xray
- 初始化与更新 VLESS Reality 配置（无 shortId）
- 自动生成/轮换 UUID 与 x25519 密钥
- UFW 放行 22 + 业务端口（可选 80）
- 启停与状态查看（systemd）
- 日志查看
- 导出节点信息到 `/root/vless_reality_node_info.txt`
- 卸载 Xray

## 支持系统

- Debian 11
- Debian 12
- Debian 13

## 目录结构

- `install.sh`：安装依赖并启动菜单
- `vless-manager.sh`：主菜单入口
- `lib/common.sh`：通用函数
- `templates/config.reality.json.tpl`：配置模板
