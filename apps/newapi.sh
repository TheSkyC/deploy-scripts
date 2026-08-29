#!/usr/bin/env bash

APP_ID="newapi"
APP_NAME="New API"
i18n_register_many \
  app.newapi.description \
  "New API deployment with systemd, backups, and operational checks." \
  "使用 systemd、备份和运维检查的 New API 部署脚本。" \
  app.newapi.backup.log.start \
  "Backup started" \
  "开始备份" \
  app.newapi.backup.log.dir_failed \
  "[ERROR] Cannot create backup directory: %s" \
  "[ERROR] 无法创建备份目录：%s" \
  app.newapi.backup.log.data_missing \
  "[ERROR] Data directory does not exist (%s); backup aborted." \
  "[ERROR] 数据目录不存在（%s），备份中止。" \
  app.newapi.backup.log.wal_ok \
  "[OK] SQLite WAL checkpoint(TRUNCATE) completed." \
  "[OK] SQLite WAL checkpoint(TRUNCATE) 成功。" \
  app.newapi.backup.log.wal_warn \
  "[WARN] SQLite WAL flush failed; backup continues and some database data may not be flushed." \
  "[WARN] SQLite WAL flush 失败，备份继续（数据库可能有未落盘数据）。" \
  app.newapi.backup.log.integrity_warn \
  "[WARN] SQLite integrity_check returned %s; backup continues but the database may be corrupted." \
  "[WARN] SQLite integrity_check 返回：%s，备份继续但数据库可能已损坏。" \
  app.newapi.backup.log.ok \
  "[OK] Backup created: %s (%s)." \
  "[OK] 备份成功：%s（%s）。" \
  app.newapi.backup.log.tar_failed \
  "[ERROR] tar failed; temporary archive removed." \
  "[ERROR] tar 失败，临时文件已清理。" \
  app.newapi.backup.log.removed_old \
  "[OK] Removed %s old backups older than %s days." \
  "[OK] 已清理 %s 个超过 %s 天的旧备份。" \
  app.newapi.backup.log.remove_failed \
  "[WARN] Could not remove old backup: %s" \
  "[WARN] 旧备份删除失败：%s" \
  app.newapi.backup.log.done \
  "Backup finished" \
  "备份完成" \
  app.newapi.error.backup_script \
  "Backup script write failed: /usr/local/bin/new-api-backup" \
  "备份脚本写入失败：/usr/local/bin/new-api-backup。" \
  app.newapi.error.backup_dir_create \
  "Backup directory could not be created: %s. Check permissions or disk state before retrying." \
  "无法创建备份目录：%s。请检查权限或磁盘状态后重试。" \
  app.newapi.error.cron \
  "Scheduled backup config write failed: /etc/cron.d/new-api-backup" \
  "定时备份配置写入失败：/etc/cron.d/new-api-backup。" \
  app.newapi.error.cron_invalid \
  "BACKUP_CRON is invalid: '%s'. Use a crontab(5) schedule like '30 3 * * *' without shell metacharacters." \
  "BACKUP_CRON 无效：'%s'。请使用 crontab(5) 格式（如 '30 3 * * *'），且不含 shell 特殊字符。" \
  app.newapi.error.tz_invalid \
  "TZ is invalid: '%s'. Use an IANA timezone name like Asia/Shanghai or UTC." \
  "TZ 无效：'%s'。请使用 IANA 时区名（如 Asia/Shanghai 或 UTC）。" \
  app.newapi.error.env_file \
  "Runtime environment file write failed: %s" \
  "运行时环境文件写入失败：%s" \
  app.newapi.error.secret \
  "Failed to generate SESSION_SECRET. Check /dev/urandom availability and retry." \
  "生成 SESSION_SECRET 失败。请检查 /dev/urandom 是否可用后重试。" \
  app.newapi.success.cron \
  "Scheduled backup configured (daily 03:30, keep %s days)." \
  "定时备份已配置（每日 03:30，保留 %s 天）。" \
  app.newapi.success.env_file \
  "Runtime environment file written: %s (mode 600)." \
  "运行时环境文件已写入：%s（权限 600）。" \
  app.newapi.summary.public \
  "Public URL" \
  "公网访问" \
  app.newapi.summary.internal \
  "Internal URL" \
  "内网直连" \
  app.newapi.summary.credential_warning \
  "WARNING: the first login uses the application's built-in default admin credentials" \
  "警告：首次登录使用应用内置的默认管理员凭据" \
  app.newapi.summary.credential_hint \
  "Change the password immediately after login — the default credentials are public knowledge" \
  "登录后请立即修改密码——默认凭据是公开已知的"

APP_DESCRIPTION="$(t app.newapi.description)"
APP_IMPL_SCRIPT="impl/install_newapi.sh"

load_app_impl "$APP_IMPL_SCRIPT"
