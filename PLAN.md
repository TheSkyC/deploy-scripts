# 部署脚本扩展计划（PLAN）

> 本文档记录本仓库“为高契合度候选自托管项目新增部署脚本（共享二进制应用扩展）”工作的目标、候选核实与实现快照；该阶段已完成并归档。
> 后续若要为共享 `binary_app` 框架新增应用：资产映射以 §2 为准，硬性步骤见 §7，环境与验证注意见 §7/§9。
> 仓库整体持续进度以 Git 提交历史为准；`docs/progress.log` 与 `docs/project-progress-and-remediation.md` 是本机工作日志，已不纳入 Git 跟踪，新 clone 中不会存在。

## 0. 2026-09 Linux 修复与优化推进

当前目标是在 Linux 开发环境（bash 5.2、systemd、shellcheck；Docker 守护进程不可用）中健壮地推进此前的审查清单。验证基线为仓库 `tools/verify.sh`，涉及 dist 的源码变更必须用
`DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0 bash tools/build-release.sh all` 重建并同 commit 提交。

### 已完成

- Python 可移植性：优先使用 `python3`，保留 `DEPLOY_PYTHON` 覆盖，验证套件在仅 `python3` 环境也可运行。
- i18n：注册缺失的 `status.title`，并为框架共享键增加一致性 guard。
- binary app 安装摘要：TLS 场景显示正确 `https` 与托管 nginx 代理状态。
- TLS 失败回滚：清理 nginx 站点、默认站点备份与续签 cron；续签 cron 改为按应用命名；卸载仅在没有其他托管站点时删除旧全局 cron。
- 状态文档：补充 `DEPLOY_STATUS_TIMEOUT_SECONDS`、`DEPLOY_STATUS_HEALTH_TIMEOUT_SECONDS`、`DEPLOY_STATUS_NO_PROBE`、`DEPLOY_STATUS_NO_NETWORK`。
- 凭据 redaction：把 operation 摘要、operation 日志与通知共用的正则收敛到 `operation_redact_text()`，防止不同出口漂移；`verify.sh operation` 通过。
- 文档引用：修正 PLAN 对未跟踪工作日志的引用，避免新 clone 后出现悬空路径。

### 已评估但不改

- `__deploy_run_exit_handlers` 中的重复 handler 调用看似冗余，实际是用 `if __deploy_set_exit_status "$status"` 的条件上下文向 handler 传递退出码。简单合并分支会让非零状态触发 `set -e` 或丢失 `$?`，保持现状更安全。

### 后续候选

- 继续观察状态采集超时行为；当前设计只在 `status-all` 聚合路径强制子 shell 超时，单应用交互命令依赖内部探针自身的 `curl --max-time`。
- 关注并行 verify 中出现过一次的后备备份行为抖动；若再次出现，先定位 `run_checks_parallel` 隔离性再调整测试。


## 1. 总目标

在 `E:\workspace\deploy-scripts` 仓库中，为高契合度候选自托管服务新增与既有框架（`apps/` + `impl/` + `bin/` + 顶层包装 + `dist/` 生成 + verify 套件）完全一致的部署脚本：

- 单二进制 / GitHub Release 分发；systemd 服务托管。
- Debian / Ubuntu 全生命周期：install / update / backup / status / uninstall。
- 脚本内注释与 i18n 按仓库约定（i18n 中英双语、注释英文）。

用户指令（原文）：*“请你逐步的，按性价比实现这些项目的部署（高契合度候选那些），期间保持合适的提交粒度。期间你也可以查阅相关资料。如果某个项目不好弄，先跳过。现在开始吧！”*

## 2. 候选资产核实与筛选结论

> 下表资产均经 GitHub Releases 网页 `expanded_assets` 核实（API 限流 403，2026-08-18）；下载 URL 形如
> `https://github.com/<repo>/releases/download/<tag>/<asset>`。本表是各 `impl/install_<app>.sh` 注释指向的权威资产映射。

### 2.1 已核实的 GitHub Release 资产

| 项目 | repo | 最新 tag | 资产模式（安装包内二进制名） |
|---|---|---|---|
| ntfy | binwiederhier/ntfy | v2.27.0 | `ntfy_2.27.0_linux_{amd64,arm64}.tar.gz`（文件名版本去 v；二进制 `ntfy`） |
| meilisearch | meilisearch/meilisearch | v1.53.1 | 裸二进制 `meilisearch-linux-amd64` / `meilisearch-linux-aarch64`（注意 aarch64 命名） |
| alist | AlistGo/alist | v3.63.0 | `alist-linux-{amd64,arm64}.tar.gz`（二进制 `alist`；不要用 musl 变体） |
| filebrowser | filebrowser/filebrowser | v2.63.23 | `linux-{amd64,arm64}-filebrowser.tar.gz`（二进制 `filebrowser`） |
| navidrome | navidrome/navidrome | v0.63.2 | `navidrome_0.63.2_linux_{amd64,arm64}.tar.gz`（版本去 v；二进制 `navidrome`） |
| frps | fatedier/frp | v0.71.0 | `frp_0.71.0_linux_{amd64,arm64}.tar.gz`（目录内 `frps`、`frpc`、`frps.toml` 示例） |
| gitea | go-gitea/gitea | v1.27.2 | 裸二进制 `gitea-1.27.2-linux-{amd64,arm64}`（去 v、无扩展名；另有 .xz 大体积资产） |

### 2.2 筛选结论

- **实现队列（按性价比排序，已全部完成）**：① ntfy → ② meilisearch / alist / filebrowser → ③ navidrome / frps / gitea → ④ gotify → ⑤ beszel。
- **已跳过**：gatus —— GitHub release 无任何二进制资产（expanded_assets 为空），只适合源码构建/Docker。
- **暂缓（未纳入共享二进制队列，接入前需先补齐前置条件）**：
  - miniflux：release 有裸二进制，但强制 PostgreSQL + 数据库初始化 + 首个管理员创建，需先设计数据库依赖 hook。
  - AdGuard Home：发行包可用，但 DNS 53 端口 + Web UI 端口 + 首次 Web 配置向导超出当前单端口/单配置模型。
  - syncthing：发行包可用，但配置生成、GUI 认证、同步目录与服务用户权限需专门安全策略。
  - MinIO：Release 页面无稳定可映射 Linux 资产，需重新核实上游发布渠道。
  - listmonk：候选仓库与发布渠道需重新核实，且有数据库依赖与初始化流程。
- **明确不做**：Docker Compose 类应用（需框架级扩展）、PHP/DB 栈、重平台（GitLab/Grafana 等）、与 Nginx 反代定位冲突的反代工具。

## 3. 共享库 lib/binary_app.sh（实现要点）

共享生命周期库，复用仓库“共享 helper 优先于逐应用复制”的约定；细节以 `lib/binary_app.sh` 源码为准：

- 配置变量：`BA_ASSET_TEMPLATE`（含 `ARCH` 占位）、`BA_ARCHIVE_TYPE`（none/tar.gz/zip）、`BA_BIN_NAME`、`BA_MIN_SIZE`、`BA_HEALTH_URL`/`BA_HEALTH_CODES`、`BA_FIREWALL`、`BA_USE_ENV_FILE`、`BA_SERVICE_ARGS`、`BA_SERVICE_DESCRIPTION`、`BA_READWRITE_PATHS`、`BA_APT_PACKAGES`、`BA_ARCHIVE_PREFIX` 等。
- 应用 hook：`ba_asset_name`、`ba_download_urls`、`ba_write_config`、`ba_systemd_unit`、`bapp_health_probe`（库调用、应用可覆盖）、`ba_status_extra`、`ba_uninstall_extra`、`ba_validate_extra`、`ba_preflight_extra`、`ba_pre_start`、`ba_summary_extra`。
- 生命周期核心全部以 `bapp_*` / `ba_*` 前缀命名（`bapp_install/update/backup/status/uninstall`、`binary_app_bootstrap` 等）；`impl/install_<app>.sh` 只写薄配置 + hook + 标准命令委托函数（每个含 `acquire_lock`）。
- 关键硬化：路径默认值必须为 safe path 二级路径（如 `/opt/<app>`、`/var/lib/<app>`）；配置仅经 `app_save_config` 写入；systemd 硬化默认 `NoNewPrivileges/PrivateTmp/ProtectSystem=strict/ReadWritePaths=${DATA_DIR} ${LOG_DIR}${BA_READWRITE_PATHS}`；二进制校验非空 + `BA_MIN_SIZE`（默认 1 MiB）+ ELF magic `7f454c46`；更新前自动备份、失败原子回滚；备份归档 `BACKUP_DIR/${APP_ID}_<label>_<ts>.tar.gz` + `BACKUP_KEEP_DAYS` 清理；i18n 全部走 `t` + `binary_app.*` 键（中英双语）。

> 2026-08-29 起 `tools/checks/*.sh` 结构断言只检查源码（`impl/`、`lib/`、`apps/`），`dist/` 仅由 `check_dist_is_up_to_date` 做“重建后与源码一致”比对；
> 此前“库函数命名避开检查正则子串、`command systemctl` 计数避让”等约束已解除，无需再规避。

## 4. 手写应用迁移评估（M15）

- **newapi：已迁移**（2026-08-29）。`impl/install_newapi.sh` 由 1074 行减至约 337 行，21 个专属 guard 精简为 4 个；框架新增 `BA_ARCHIVE_PREFIX="new-api"` 保持历史备份前缀兼容。
- **vaultwarden / sub2api / cyberstrikeai：保留手写**（已充分复用共享 helper：`app_binary_*` 二进制回滚、`app_remove_*` 删除、`app_save_config` 配置持久化、`backup_restore_data_dir` 恢复、`github_latest_release_tag` 版本查询）：
  - vaultwarden：二进制经 Docker 镜像提取（非 GitHub Release）+ Web Vault 第二构件 + nginx 反代 + certbot TLS —— 迁移需框架新增“容器镜像提取”下载后端，收益/风险比低。
  - sub2api：PostgreSQL/Redis 依赖 + 多构件备份（数据目录/配置目录/PG 转储）——备份格式与框架单目录打包模型不兼容。
  - cyberstrikeai：源码构建（Go build + Python venv），不在二进制下载生命周期内。

## 5. 实现结果与应用清单（默认端口）

9 个新增二进制应用全部实现并逐个提交（apps/impl/bin/wrapper/registry/checks + 重建 dist 同 commit），newapi 已并入共享框架；verify 套件（syntax/release/dispatch/guards）通过，e2e-smoke 接入 CI。

| 应用 | 端口 | 关键点 |
|---|---|---|
| ntfy | 2586 | `/etc/ntfy/server.yml`（`serve` 指定） |
| meilisearch | 7700 | 裸二进制 aarch64 命名；`/etc/meilisearch.env`（保留 master key） |
| alist | 5244 | `server --data ${DATA_DIR}`；安装后提示 `alist admin --data …` 初始化管理员密码 |
| filebrowser | 8084 | `FB_ROOT` 默认 `/srv/filebrowser` |
| navidrome | 4533 | `ND_*` env；`MUSIC_DIR` 默认 `/srv/music` |
| frps | 7000 | `/etc/frps/frps.toml` + 随机 auth.token |
| gitea | 3000 | 裸二进制；`BA_APT_PACKAGES="git"`；`/etc/gitea/app.ini`（sqlite） |
| gotify | 8085 | zip 发行包；`/etc/gotify.env`；首次生成并保留随机管理员密码 |
| beszel | 8090 | Hub tar.gz；数据目录 `/var/lib/beszel`；`/api/health` 健康检查 |
| newapi | 8080 | 已迁移至共享框架；`BA_ARCHIVE_PREFIX="new-api"` |

## 6. 新增应用的硬性步骤（每应用必做）

1. `apps/<app>.sh`：APP_ID/APP_NAME/i18n 注册/`load_app_impl`。
2. `impl/install_<app>.sh`：薄配置 + hook + 标准命令委托函数（每个含 `acquire_lock`）+ `binary_app_bootstrap`。
3. `bin/install_<app>.sh`：source core.sh + apps/<app>.sh + `main "$@"`。
4. 顶层 `install_<app>.sh` 包装：`exec bash "${SCRIPT_DIR}/bin/<name>" "$@"`。
5. `lib/app_registry.sh` 的 `DEPLOY_APP_SPECS` 加一行（`id|Name|apps/<id>.sh|impl/install_<id>.sh`）。
6. `tools/checks/app-<app>.sh`（check_* 函数）并注册到 `tools/verify.sh` 的 dispatch/guards 目标分支（`check_target_groups_cover_all_checks` 强制每个 check 必须被某 target 调用）。
7. `tools/checks/dispatch.sh` 的 `check_app_localized_descriptions` 增加中英描述断言。
8. `dist/` 重新生成并与源码同 commit（verify 以 `DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0` 重建比对）。

自建 check 注意：app check 必须匹配**共享库实现**（如 `command systemctl daemon-reload`、`bapp_health_probe`），不要照抄既有应用的精确计数/函数名断言；
`check_mutating_actions_acquire_locks` 要求每个 `do_install/do_update/do_backup/do_uninstall` 函数体内有 `acquire_lock`；
i18n 一致性只校验 `app.<prefix>.*` 键（`binary_app.*` 在 lib 注册，不在该校验范围，但要保持无孤立键）。

## 7. 验证命令

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh            # 全量（含重建 dist，可能 3-6 分钟）
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh syntax
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh shellcheck # 约 40-60s
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh release
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh dispatch   # 约 3-5 分钟
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh guards     # 约 2-3 分钟
```

重建 dist：`DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0 bash tools/build-release.sh all`（Git Bash 中执行）。

## 8. 归档说明与后续

- 本阶段（共享二进制扩展 + newapi 迁移）已完成归档；持续修复以 Git 提交历史为准，不要假设上述两个未跟踪日志在新 clone 中存在。
- 暂缓候选与“明确不做”项见 §2.2；若未来要接入需先补齐其前置条件（数据库 hook / 多端口模型 / 发布渠道核实等）。

## 9. 环境与踩坑记录

- Windows PowerShell 会话；跑 bash 用 `C:\Program Files\Git\bin\bash.exe`（Git Bash 5.2.26）。
- `.gitattributes` 强制 `*.sh` LF，`core.autocrlf=true`；用 Python `newline=''`/`\n` 写文件避免 CRLF。
- 不要用 `bash -c 'cat > file <<EOF'` 的 heredoc 经 PowerShell 传参（引号被打乱）；可靠写法：Python 显式 `\n` 写，或 PowerShell here-string + `[System.IO.File]::WriteAllText`。
- GitHub API 已限流（403）：核实资产用网页 `https://github.com/<repo>/releases/expanded_assets/<tag>`。
- 不要在本机实装 install/update（需真实 systemd/root 服务环境且打 GitHub API）；验证靠 verify 套件 + 语法/静态检查。**2026-08-29 起真实安装矩阵由 `tools/e2e-smoke.sh` 在 Docker 容器内执行**（stub systemd + 文件版 curl shim，覆盖 binary_app 与 compose 两条路径；CI job `e2e-smoke` 每次 push 运行）。
- 二进制校验：非空、`BA_MIN_SIZE`（默认 1 MiB）、ELF magic `7f454c46`；失败时删除临时文件并 `error`。
- bash 语法问题排查套路：先 `bash -n`；函数级拆分逐个 `bash -n`；注意行首 `}` 与后续 token 粘连、未闭合 `$(`、heredoc 终止符、行末 `\` 续行。
