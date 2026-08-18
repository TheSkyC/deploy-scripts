# 部署脚本扩展计划（PLAN）

> 本文档是本仓库“为高契合度候选项目逐个新增部署脚本”工作的唯一权威记忆锚点。
> 每次工作前先读本文件；完成后更新“当前进度”。目标语言：中文（脚本内注释与 i18n 按仓库约定）。

## 1. 总目标

在 `E:\workspace\deploy-scripts` 仓库中，为以下“高契合度候选”自托管服务逐个新增部署脚本：

- 单二进制 / GitHub Release 分发
- systemd 服务托管
- Debian / Ubuntu 生命周期（install / update / backup / status / uninstall）
- 与仓库既有框架（apps/ + impl/ + bin/ + 顶层包装 + dist/ 生成 + verify 套件）完全一致

用户指令（原文）：*“请你逐步的，按性价比实现这些项目的部署（高契合度候选那些），期间保持合适的提交粒度。期间你也可以查阅相关资料。如果某个项目不好弄，先跳过。现在开始吧！”*

## 2. 候选清单与筛选结论

### 2.1 已核实的 GitHub Release 资产（2026-08-18，网页 expanded_assets 核实；API 限流）

| 项目 | repo | 最新 tag | 资产模式（安装包内二进制名） |
|---|---|---|---|
| ntfy | binwiederhier/ntfy | v2.27.0 | `ntfy_2.27.0_linux_{amd64,arm64}.tar.gz`（文件名版本去 v；二进制 `ntfy`） |
| meilisearch | meilisearch/meilisearch | v1.53.1 | 裸二进制 `meilisearch-linux-amd64`、`meilisearch-linux-aarch64`（注意 aarch64 命名） |
| alist | AlistGo/alist | v3.63.0 | `alist-linux-{amd64,arm64}.tar.gz`（二进制 `alist`；不要用 musl 变体） |
| filebrowser | filebrowser/filebrowser | v2.63.23 | `linux-{amd64,arm64}-filebrowser.tar.gz`（二进制 `filebrowser`） |
| navidrome | navidrome/navidrome | v0.63.2 | `navidrome_0.63.2_linux_{amd64,arm64}.tar.gz`（版本去 v；二进制 `navidrome`） |
| frps | fatedier/frp | v0.71.0 | `frp_0.71.0_linux_{amd64,arm64}.tar.gz`（目录内 `frps`、`frpc`、`frps.toml` 示例） |
| gitea | go-gitea/gitea | v1.27.2 | 裸二进制 `gitea-1.27.2-linux-{amd64,arm64}`（去 v、无扩展名；另有 .xz 大体积资产） |

下载 URL 形如 `https://github.com/<repo>/releases/download/<tag>/<asset>`。

### 2.2 决策

- **实现队列（按性价比排序）**：
  1. ntfy（最简单、配置最少）
  2. meilisearch / alist / filebrowser
  3. navidrome / frps / gitea（gitea 若复杂度失控则跳过）
- **已跳过**：gatus —— 已核实其 GitHub release 无任何二进制资产（expanded_assets 为空），只适合源码构建/Docker。
- **未纳入当前队列**：miniflux、gotify、adguard、minio、listmonk、syncthing、beszel（候选清单其余项，本轮性价比顺序未排到；miniflux 资产尚未核实）。
- **明确不做**：Docker Compose 类应用（需框架级扩展）、PHP/DB 栈、重平台（GitLab/Grafana 等）、与 Nginx 反代定位冲突的反代工具。

## 3. 技术方案：共享生命周期库 lib/binary_app.sh

新增共享库（已完成第一版），复用仓库“共享 helper 优先于逐应用复制”的约定：

- 配置变量：`BA_ASSET_TEMPLATE`（含 `ARCH` 占位）、`BA_ARCHIVE_TYPE`（none/tar.gz/zip）、`BA_BIN_NAME`、`BA_MIN_SIZE=1048576`、`BA_HEALTH_URL`/`BA_HEALTH_CODES`、`BA_FIREWALL=1`、`BA_USE_ENV_FILE`、`BA_SERVICE_ARGS`、`BA_SERVICE_DESCRIPTION`、`BA_READWRITE_PATHS` 等。
- Hook（应用专属）：`ba_asset_name`、`ba_download_urls`、`ba_write_config`、`ba_systemd_unit`、`bapp_health_probe`（由库调用，应用可覆盖）、`ba_status_extra`、`ba_uninstall_extra`、`ba_validate_extra`、`ba_preflight_extra`、`ba_pre_start`、`ba_summary_extra`。
- 生命周期核心（库内命名，**全部 `bapp_*` / `ba_*` 前缀，绝不使用 `do_*`、`preflight_check`、`_validate_config_values`、`check_connectivity` 等通用名**）：
  - `bapp_install` / `bapp_update` / `bapp_backup` / `bapp_status` / `bapp_uninstall`
  - `bapp_preflight`、`bapp_validate_cfg`、`bapp_check_net`、`bapp_health_probe`、`bapp_inspect_binary`、`bapp_summary`
  - `binary_app_bootstrap`（设置 `APP_CONFIG_DERIVE_HOOK=_binary_app_derive_paths`、`CONF_FILE`、`LOCK_FILE`、派生路径、校验）
- 每个新应用的 `impl/install_<app>.sh` 只写：薄配置 + 应用专属 hook + 标准命令函数（`do_install`/`do_update`/`do_backup`/`do_status`/`do_uninstall`，每个都是一行委托 + `acquire_lock`），最后调用 `binary_app_bootstrap`。

### 3.1 命名避让（关键设计约束，踩坑总结）

仓库 `tools/checks/*.sh` 中有大量 awk 结构检查直接扫描 **`dist/install_*.sh`（库会被打包进每个 dist 脚本）**，且很多用未锚定正则（如 `/do_uninstall\(\)/`、`/health_check\(\)/`、`/verify_binary\(\)/`、`/print_summary\(\)/`）。因此：

- 库内任何函数名**不得包含**检查正则的完整子串（如 `do_install`、`health_check`、`verify_binary`、`print_summary` 等）。
- 当前已验证冲突并规避的：`preflight_check`、`check_connectivity`、`_validate_config_values`、`do_*`、`ba_health_check`→`bapp_health_probe`、`ba_verify_binary`→`bapp_inspect_binary`、`ba_print_summary`→`bapp_summary`。
- 新增应用时若再添加库函数，先跑一遍“库函数名 vs checks 正则”的碰撞扫描（用 Python 脚本模拟 awk `/.../` 对 dist 文件的匹配）。

### 3.2 systemd daemon-reload 计数避让（踩坑总结）

`check_systemd_daemon_reloads_are_explicit` 对 newapi/sub2api/cyberstrikeai/vaultwarden 的 impl/dist **精确计数** `if ! systemctl daemon-reload; then` 与对应 error 行（如 newapi 必须恰好 3+3）。库若用同样写法会污染 dist 计数导致 guards 失败。当前规避：

- 库内 3 处 reload 用 `if ! command systemctl daemon-reload; then`（`command` 前缀，语义等价、不会被计数正则匹配）。
- 卸载清理路径 1 处用 `if ! systemctl daemon-reload 2>/dev/null; then`（带重定向，也不匹配计数正则）。
- 新增应用的自建 check 必须按我们自己的写法（`command systemctl`）来断言，不要照抄既有应用的精确计数检查。

### 3.3 其它库内已处理约束

- 部署配置只能经 `app_save_config` 写入（库内无对 `$CONF_FILE` 的直接 `>`/`>>`/tee）。
- 卸载：先停服务、`require_safe_path` 校验、逐路径删除并 warn 失败、`userdel` 显式 if 分支 success/warn。
- 更新：stop 前 `app_binary_backup_current` 备份旧二进制（原子）、`app_binary_install_candidate` 替换、失败 `app_binary_restore_backup` 回滚；更新前自动 `_ba_backup "pre-update"`。
- 备份：`BACKUP_DIR/${APP_ID}_<label>_<ts>.tar.gz` + `backup.log` + `BACKUP_KEEP_DAYS` 保留清理。
- systemd 硬化默认：`NoNewPrivileges/PrivateTmp/ProtectSystem=strict/ReadWritePaths=${DATA_DIR} ${LOG_DIR}${BA_READWRITE_PATHS}`；unit 经 `systemd_write_unit` 原子写入。
- 摘要 IP 检测必须非致命：`hostname_scan="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"` + `YOUR_SERVER_IP` 回退（`check_summary_ip_detection_has_fallback` 强制，库已按此写）。
- i18n：全部消息走 `t` + `binary_app.*` 键（中英双语，`i18n_register_many` 注册于库文件顶部）；`impl/` 不得含硬编码中文；注释一律英文。
- 路径默认值必须是 safe path（`is_safe_path` 拒绝 `/opt`、`/var`、`/srv` 顶层；必须 `/opt/<app>`、`/var/lib/<app>` 这类二级路径）。

## 4. 当前进度（2026-08-18 快照，随工作实时更新）

### 已完成并提交

- ✅ `feat(lib): add shared binary app lifecycle` — `lib/binary_app.sh`（约 1200 行；i18n 全量注册 + 生命周期函数 + hook 机制）+ `lib/core.sh` 引用顺序 + `tools/build-release.sh` 打包库 + 随 verify 重建 `dist/*.sh`。
- ✅ `fix(lib): repair i18n block continuation strings` — 修复 i18n 块续行粘连缺陷。
- ✅ `feat(ntfy): ...` — ntfy 已实现并提交（端口 2586，`/etc/ntfy/server.yml` 原子写入）。
- ✅ `feat(meilisearch): ...` — meilisearch 已实现并提交（裸二进制 aarch64 命名，MEILI 环境文件 + 保留 master key）。
- ✅ `fix(meilisearch): derive env file path without shellcheck SC2153` — 修复 style 级 shellcheck。
- ✅ `feat(alist): ...` — alist 已实现并提交（`server --data ${DATA_DIR}`）。
- ✅ `feat(filebrowser): ...` — filebrowser 已实现并提交（FB_ROOT 就绪 + READWRITE_PATHS）。
- ✅ `tools/verify.sh all`（全量：syntax + shellcheck + release + dispatch + guards + 全部 check）已完整通过。

### 当前工作区状态

- 分支 `codex/script-audit-optimizations`，所有实现同 commit 同步 dist。
- 下一步：navidrome / frps / gitea（每个一个 feat commit；gitea 若复杂则跳过）。
- 最后：README 更新 + 最终全量 verify。

## 5. 提交计划（粒度）

1. `feat(lib): add shared binary app lifecycle` —— `lib/binary_app.sh` + `lib/core.sh` + `tools/build-release.sh` + 重建后的 `dist/*.sh`（此时 dist 随 verify 重建并同 commit）。
2. 每个新应用一个 feat commit（apps/impl/bin/wrapper/registry/checks + 重新生成的 dist）：
   - `feat(ntfy): add GitHub-release binary deployment`
   - `feat(meilisearch): ...` / `feat(alist): ...` / `feat(filebrowser): ...`
   - `feat(navidrome): ...` / `feat(frps): ...` / `feat(gitea): ...`（若做）
3. `docs(readme): document new applications`
4. 最终全量 verify 后收尾。

## 6. 各应用设计（实现时可微调）

### 通用默认
- 默认用户 `SERVICE_USER` 系统账户、nologin、家目录 `INSTALL_DIR`；`INSTALL_DIR`/`DATA_DIR`/`LOG_DIR`/`BACKUP_DIR` 均为 `/opt/<app>`、`/var/lib/<app>` 等二级 safe path。
- 端口冲突检测 `app_check_port_conflict`；健康检查 `bapp_health_probe`（curl 到 `BA_HEALTH_URL`，成功码 `BA_HEALTH_CODES`）；防火墙 `BA_FIREWALL=1`（ufw 开放端口）。

### ntfy（最高性价比，先做）
- 端口 2586；配置 `/etc/ntfy/server.yml`（`atomic_write_file` 写 `listen-http: :2586`、`cache-file` 指向数据目录）；`BA_USE_ENV_FILE=0`；`BA_ARCHIVE_TYPE=tar.gz`。
- 资产：`ntfy_<ver>_linux_{amd64,arm64}.tar.gz`（版本去 v），二进制 `ntfy`。

### meilisearch
- 端口 7700；`BA_ARCHIVE_TYPE=none`（裸二进制）；`ba_asset_name` 需把 arm64→aarch64。
- 环境文件 `/etc/<svc>.env` 写入生成的 `MEILI_MASTER_KEY`、`MEILI_ENV=production`、`MEILI_DB_PATH=${DATA_DIR}/meili_data`（`BA_USE_ENV_FILE=1`）。
- health：`http://127.0.0.1:${PORT}/health`。

### alist
- 端口 5244；`BA_ARCHIVE_TYPE=tar.gz`；命令 `alist server --data ${DATA_DIR}`（`BA_SERVICE_ARGS`）。
- 安装后提示 `alist admin random|set` 初始化管理员密码（`ba_summary_extra`）。

### filebrowser
- 端口 8081（避开 8080）；`BA_ARCHIVE_TYPE=tar.gz`；根目录 `FB_ROOT` 默认 `/srv/filebrowser`（safe path + 加入 `BA_READWRITE_PATHS`）。
- 参数 `-d/-r/-p/-a` 或环境 `FILEBROWSER_DATABASE`/`FILEBROWSER_ROOT`；首次默认 admin/admin，摘要提示修改。

### navidrome
- 端口 4533；`ba_asset_name` 版本去 v；`NAVIDROME_PORT`、`NAVIDROME_DATA_FOLDER`、音乐目录 `NAVIDROME_MUSIC_FOLDER` 默认 `/srv/music`（加入 `BA_READWRITE_PATHS`）。

### frps
- 端口 7000；`BA_ARCHIVE_TYPE=tar.gz`（目录内二进制约束 `frps`）；配置 `/etc/frps/frps.toml`（bindPort、auth.token 随机生成）；`ba_systemd_unit` 加 `-c` 参数；`BA_FIREWALL=1`（7000 入站）。

### gitea（若实现复杂度失控则跳过）
- 端口 3000；`BA_ARCHIVE_TYPE=none`；`ba_asset_name` 生成 `gitea-<去v版本>-linux-{amd64,arm64}`；apt 依赖多一个 `git`。
- `GITEA_WORK_DIR=${DATA_DIR}`、`--config /etc/gitea/app.ini`（RUN_USER、RUN_MODE、[server] HTTP_PORT/DOMAIN/ROOT_URL、[database] sqlite）；安装后提示手动 `gitea admin create-user`。

## 7. 新增应用的硬性步骤（每应用必做）

1. `apps/<app>.sh`：APP_ID/APP_NAME/i18n 注册/`load_app_impl`。
2. `impl/install_<app>.sh`：薄配置 + hook + 标准命令委托函数（每个含 `acquire_lock`）+ `binary_app_bootstrap`。
3. `bin/install_<app>.sh`：source core.sh + apps/<app>.sh + `main "$@"`。
4. 顶层 `install_<app>.sh` 包装：`exec bash "${SCRIPT_DIR}/bin/<name>" "$@"`。
5. `lib/app_registry.sh` 的 `DEPLOY_APP_SPECS` 加一行（`id|Name|apps/<id>.sh|impl/install_<id>.sh`）。
6. `tools/checks/app-<app>.sh`（check_* 函数）并注册到 `tools/verify.sh` 的 dispatch/guards 目标分支（`check_target_groups_cover_all_checks` 强制每个 check 必须被某 target 调用）。
7. `tools/checks/dispatch.sh` 的 `check_app_localized_descriptions` 增加中英描述断言。
8. `dist/` 重新生成并与源码同 commit（verify 会以 `DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0` 重建比对）。

### 自建 check 注意事项
- 我们的 app check 必须匹配**共享库实现**（如 `command systemctl daemon-reload`、`bapp_health_probe`），不要照抄既有应用的精确计数/函数名断言。
- `check_mutating_actions_acquire_locks`（扫描所有 impl/install_*.sh）要求每个 `do_install/do_update/do_backup/do_uninstall` 函数体内有 `acquire_lock` —— 薄包装必须满足。
- i18n 一致性检查只校验 `app.<prefix>.*` 键（apps/*.sh 注册 vs impl/checks 引用）；`binary_app.*` 键在 lib 注册，不在该校验范围，但自己要保持无孤立键。

## 8. 验证命令

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh            # 全量（含重建 dist，可能 3-6 分钟）
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh syntax
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh shellcheck # 约 40-60s
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh release
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh dispatch   # 约 3-5 分钟
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh guards     # 约 2-3 分钟
```

重建 dist：`DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0 bash tools/build-release.sh all`（Git Bash 中执行）。

## 9. 环境与踩坑记录

- Windows PowerShell 会话；跑 bash 用 `C:\Program Files\Git\bin\bash.exe`（Git Bash 5.2.26）。
- `.gitattributes` 强制 `*.sh` LF，`core.autocrlf=true`；用 Python `newline=''`/`\n` 写文件避免 CRLF。
- 不要用 `bash -c 'cat > file <<EOF'` 的 heredoc 经 PowerShell 传参（引号被打乱）；可靠写法：Python 3.14 显式 `\n` 写（本文件即如此生成），或 PowerShell here-string + `[System.IO.File]::WriteAllText`。
- GitHub API 已限流（403）：核实资产用网页 `https://github.com/<repo>/releases/expanded_assets/<tag>`。
- 不要在本机实装 install/update（需真实 systemd/root 服务环境且打 GitHub API）；验证靠 verify 套件 + 语法/静态检查。
- 二进制校验：非空、`BA_MIN_SIZE`（默认 1 MiB）、ELF magic `7f454c46`；失败时删除临时文件并 `error`。
- bash 语法问题排查套路：先 `bash -n`；函数级拆分逐个 `bash -n`；注意行首 `}` 与后续 token 粘连、未闭合 `$(`、heredoc 终止符、行末 `\` 续行。
