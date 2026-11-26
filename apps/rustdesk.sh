#!/usr/bin/env bash
# shellcheck disable=SC2034

APP_ID="rustdesk"
APP_NAME="RustDesk Server OSS"
i18n_register_many \
  app.rustdesk.description \
  "RustDesk OSS ID and relay server (hbbs + hbbr) managed with Docker Compose." \
  "通过 Docker Compose 管理 RustDesk OSS ID 与中继服务（hbbs + hbbr）。" \
  app.rustdesk.info.public_key \
  "RustDesk public key (share this with clients):" \
  "RustDesk 公钥（配置客户端时使用）：" \
  app.rustdesk.warn.no_key \
  "Public key is not available yet. Start the server first." \
  "公钥尚不可用，请先启动服务。" \
  app.rustdesk.error.systemd \
  "systemd is required." \
  "此脚本需要 systemd。" \
  app.rustdesk.error.service_name \
  "Invalid RustDesk service name: %s" \
  "RustDesk 服务名称无效：%s" \
  app.rustdesk.error.image \
  "Invalid RustDesk container image reference: %s" \
  "RustDesk 容器镜像名称无效：%s" \
  app.rustdesk.error.relay_host \
  "Set RUSTDESK_RELAY_HOST to the public DNS name or IP clients use to reach this server." \
  "请将 RUSTDESK_RELAY_HOST 设置为客户端访问此服务器时使用的公网域名或 IP。" \
  app.rustdesk.error.network_mode \
  "RUSTDESK_NETWORK_MODE must be host or bridge." \
  "RUSTDESK_NETWORK_MODE 必须为 host 或 bridge。" \
  app.rustdesk.error.port \
  "RustDesk ports must be distinct integers from 1 to 65535." \
  "RustDesk 端口必须是 1 到 65535 之间互不重复的整数。" \
  app.rustdesk.error.host_ports \
  "Custom RustDesk ports require RUSTDESK_NETWORK_MODE=bridge." \
  "自定义 RustDesk 端口要求 RUSTDESK_NETWORK_MODE=bridge。" \
  app.rustdesk.error.bind_addr \
  "RUSTDESK_BIND_ADDR must be 0.0.0.0 or 127.0.0.1." \
  "RUSTDESK_BIND_ADDR 必须为 0.0.0.0 或 127.0.0.1。" \
  app.rustdesk.error.compose \
  "Docker Compose is required." \
  "需要 Docker Compose。" \
  app.rustdesk.error.dependencies \
  "Could not install Docker Compose dependencies." \
  "无法安装 Docker Compose 依赖。" \
  app.rustdesk.error.docker_start \
  "Could not enable or start Docker." \
  "无法启用或启动 Docker。" \
  app.rustdesk.error.health \
  "RustDesk hbbs and hbbr did not both reach running state; inspect systemd and container logs." \
  "RustDesk 的 hbbs 和 hbbr 未能同时运行，请检查 systemd 与容器日志。" \
  app.rustdesk.error.update_prerequisite \
  "Both RustDesk services must be running before update." \
  "更新前 hbbs 和 hbbr 必须同时运行。" \
  app.rustdesk.error.rollback_info \
  "Cannot identify the running RustDesk containers or image for rollback." \
  "无法识别正在运行的 RustDesk 容器或镜像以执行回滚。" \
  app.rustdesk.error.mixed_images \
  "hbbs and hbbr are on different images; update rollback is unsafe." \
  "hbbs 和 hbbr 使用不同镜像，无法安全更新回滚。" \
  app.rustdesk.error.backup \
  "Failed to create a verified RustDesk data backup." \
  "无法创建已校验的 RustDesk 数据备份。" \
  app.rustdesk.error.image_retain \
  "Cannot retain the current RustDesk image for rollback." \
  "无法保留当前 RustDesk 镜像用于回滚。" \
  app.rustdesk.warn.update_rollback \
  "RustDesk update failed health checks; restoring the previous image and data." \
  "RustDesk 更新未通过健康检查，正在恢复旧镜像与数据。" \
  app.rustdesk.error.image_rollback \
  "Image rollback failed. Previous image retained as %s; inspect the stack and restore %s manually." \
  "镜像回滚失败。旧镜像保留为 %s；请检查服务栈并手动恢复 %s。" \
  app.rustdesk.error.data_rollback \
  "Image was restored, but data/service rollback needs attention. Previous image: %s; snapshot: %s." \
  "镜像已恢复，但数据/服务回滚仍需处理。旧镜像：%s；快照：%s。" \
  app.rustdesk.error.update_rolled_back \
  "RustDesk update was rolled back. Running image: %s; snapshot: %s." \
  "RustDesk 更新已回滚。运行镜像：%s；快照：%s。" \
  app.rustdesk.success.updated \
  "RustDesk updated to %s; pre-update backup: %s." \
  "RustDesk 已更新至 %s；更新前备份：%s。" \
  app.rustdesk.error.restore_archive \
  "Invalid RustDesk restore archive: %s" \
  "RustDesk 恢复归档无效：%s" \
  app.rustdesk.error.restore_health_rollback \
  "Restored data failed health checks; previous data has been put back from %s." \
  "恢复的数据未通过健康检查；已从 %s 回滚至原数据。" \
  app.rustdesk.error.no_backups \
  "No RustDesk backups found in %s." \
  "在 %s 中没有找到 RustDesk 备份。" \
  app.rustdesk.error.stop \
  "Failed to stop/disable RustDesk service %s." \
  "无法停止或禁用 RustDesk 服务 %s。" \
  app.rustdesk.error.reload \
  "systemd daemon-reload failed." \
  "systemd daemon-reload 执行失败。" \
  app.rustdesk.error.start \
  "Failed to start RustDesk systemd service %s." \
  "无法启动 RustDesk systemd 服务 %s。" \
  app.rustdesk.success.backup \
  "RustDesk backup created: %s" \
  "RustDesk 备份已创建：%s" \
  app.rustdesk.success.running \
  "RustDesk hbbs and hbbr are running." \
  "RustDesk hbbs 和 hbbr 均在运行。" \
  app.rustdesk.warn.services \
  "RustDesk hbbs and hbbr are not both running; inspect Docker Compose logs." \
  "RustDesk hbbs 和 hbbr 未同时运行，请检查 Docker Compose 日志。" \
  app.rustdesk.info.uninstalled \
  "Server stopped. Persistent identity retained at %s." \
  "服务已停止。持久化身份保留在 %s。"
APP_DESCRIPTION="$(t app.rustdesk.description)"
APP_IMPL_SCRIPT="impl/install_rustdesk.sh"
load_app_impl "$APP_IMPL_SCRIPT"
