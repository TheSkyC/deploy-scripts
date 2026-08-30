# 项目当前进度与整改路线

> **审计基准**：P0-S2 安全审计代码基线为 `af6b511`（2026-08-30）；当前整改代码基线为 `0dfe154`（CyberStrikeAI 固定 git 提交发布产物）。
> **文档目的**：将另一 AI 提出的安全、架构和体验问题与当前代码逐项对照，区分“已修复”“部分完成”“仍待处理”，并给出下一阶段可执行顺序。
>
> **结论先行**：这份建议对应的是修复前状态。高优先级安全项 1–4 已在 2026-08-29 的连续提交中完成主要修复；功能建议中的版本固定、单应用 dry-run/help、一键 HTTPS、卸载前导出、多实例、配置 diff、CI push 校验也已经落地。当前最大的未完成项不是原建议中的安全基线，而是：**真实生产环境验证仍有限、四个手写应用的架构取舍尚未进一步推进、`dist/` 生成物的治理仍保留漂移风险、部分应用仍采用浮动分支/镜像版本语义**。

## 1. 当前项目状态

### 1.1 仓库规模与形态

| 指标 | 当前值 | 说明 |
|---|---:|---|
| 应用实现 | 16 个 | `apps/` 与 `impl/` 各 16 个 |
| 单文件发布产物 | 17 个 | `dist/`：16 个应用脚本 + `deploy.sh` |
| `dist/` 规模 | 约 135,274 行（按当前工作区统计） | 生成产物，不应手工编辑 |
| 共享库 | 约 8,979 行 | `lib/`，含 binary-app、备份、状态、通知、调度、迁移、Compose、Fleet 等能力 |
| 工作区 | 干净 | 旧安装安全审计、行为级守卫及发布产物已提交 |
| 当前整改代码基线 | `0dfe154` | CyberStrikeAI 固定 git 提交及其发布产物；后续文档提交不改变该代码基线 |

### 1.2 已完成的主线能力

截至当前 HEAD，项目已经从“单应用安装脚本集合”发展为“共享生命周期框架 + 应用适配器 + 中央管理命令”：

- **16 个应用统一动作面**：`install`、`update`、`backup`、`restore`、`status`、`status-json`、`doctor`、`verify`、`uninstall`；能力由应用注册表声明。
- **10 个 GitHub Release 二进制应用**已经接入 `lib/binary_app.sh`：alist、beszel、filebrowser、frps、gitea、gotify、meilisearch、navidrome、newapi、ntfy。
- **New API 已完成迁移**：`impl/install_newapi.sh` 从约 1,074 行缩减至约 310 行源码，主要生命周期委托共享库；保留 SQLite WAL 备份、cron 备份和历史 `new-api_` 归档前缀兼容。对应提交 `5e52008`，并在 `39a2861` 增加真实安装 smoke 场景。
- **备份可靠性闭环已完成**：归档 SHA-256、`manifest.json`、`verify`、安全 restore、损坏/路径穿越防护；16/16 应用均具备 backup + verify + restore 能力（不同应用可通过自定义适配实现）。
- **中央运维能力已完成**：`status-all`、`backup-all`、`update-all`、`doctor-all`、`check-update`、`doctor security`、通知、systemd timer/cron 调度、export/import、Fleet 多机执行、JSON 状态与操作历史。
- **安全基线已收紧**：Web 服务默认 loopback；二进制应用默认不自动开防火墙端口；Vaultwarden 默认关闭注册；TickFlow 默认生成随机面板密码；敏感配置 root-only；Nginx 默认站点可恢复而非卸载时直接删除。
- **质量门禁已加强**：verify 套件从扫描生成物文本逐步解耦，源码结构检查与 `dist` 一致性检查分离；CI 的 syntax/release/dispatch/guards、shellcheck、Docker E2E smoke 已配置为 push/PR 执行，nightly 运行全量验证。

## 2. 对另一 AI 建议的逐项核对

状态标记：

- **已修复**：当前源码已解决，且有提交/守卫/文档证据。
- **部分完成**：主问题已缓解，但仍有边界、兼容性或后续治理工作。
- **待处理**：当前仍可观察到，建议进入后续迭代。
- **误报/已过时**：建议描述的是旧代码，当前不应再按原问题报告。

### 2.1 安全问题

| 编号 | 原建议 | 当前状态 | 证据与说明 |
|---|---|---|---|
| H1/H2 | Vaultwarden 明文 Admin Token 写入并打印；注册默认开启 | **已修复** | `impl/install_vaultwarden.sh:15-20, 1245-1270`：`SIGNUPS_ALLOWED=false`；Token 以 root-only mode 600 文件保存，安装摘要不打印 Token，仅提示用 `token` 动作查看/轮换/删除。提交 `d58b5f4`、`e635a91`。 |
| H3 | New API 安装摘要打印 `root / 123456` | **已修复** | `impl/install_newapi.sh:112-119` 仅输出“使用应用内置默认管理员凭据，请立即修改”的警告，不输出具体密码。提交 `370b1d5`。 |
| H4 | 默认 `0.0.0.0`、自动放行防火墙、明文 HTTP | **主要已修复** | `lib/binary_app.sh:543-546, 903-907` 将共享二进制应用默认绑定 `127.0.0.1`，`BA_FIREWALL` 默认 0；`impl/install_sub2api.sh:16-18` 与 `impl/install_tickflow.sh:17-21` 同样默认 loopback。TLS 可通过 `BA_ENABLE_HTTPS`/`DOMAIN` 或应用现有 HTTPS 流程启用。仍需注意：显式设置公网绑定仍可能提供明文 HTTP，摘要会警告；frps 是刻意的公网 TCP 例外；CyberStrikeAI/CPA Stack/Vaultwarden 等自定义应用需要按各自配置核查。 |
| H5 | Sub2API 用拼接 SQL；密码复制到 `/usr/local/bin/sub2api-backup` | **主要已修复** | `impl/install_sub2api.sh:512-553` 对 `PG_USER`/`PG_DB` 做标识符校验，密码通过 `psql -v pg_pass` 参数传值；`impl/install_sub2api.sh:746-776` 将 DSN 写入 `${CONFIG_DIR}/.pg_dsn`（mode 600），生成的备份脚本仅读该文件，不嵌入密码。仍建议后续进一步使用 PostgreSQL identifier quoting/API，降低 SQL 拼接的长期维护风险。提交 `68dc386`。 |

> **安全处置建议**：不要只看当前源码。若主机曾使用旧版本安装，旧的 `/root/.vaultwarden-admin-token.*`、旧备份脚本、旧配置或旧日志可能仍留有凭据，应在升级前后人工检查并轮换 Vaultwarden Admin Token、Sub2API 数据库密码及其他默认凭据。

### 2.2 架构与维护性问题

| 编号 | 原建议 | 当前状态 | 证据与说明 |
|---|---|---|---|
| M15 | Sub2API/Vaultwarden/NewAPI/CyberStrikeAI 各自重复生命周期 | **部分完成** | New API 已迁移到共享 `binary_app`（提交 `5e52008`）。剩余三个手写应用仍保留，但已有共享 helper（备份、回滚、删除、配置、restore、版本检查）。`PLAN.md:54-62` 明确记录：Vaultwarden 是 Docker 镜像提取 + Web Vault/nginx/certbot，Sub2API 是多构件备份 + PostgreSQL/Redis，CyberStrikeAI 是源码构建，当前不适合强行套单二进制生命周期。 |
| M1 | `dist/` 生成物可能与源码漂移 | **有防线，治理仍可优化** | `tools/verify.sh` 的 release/dispatch/guards 会确定性重建并检查 `dist`；`.github/workflows/verify.yml:3-5, 23-40` 已在 push/PR 执行 release 检查。因此提交过时 `dist` 会被 CI 拦截。风险仍存在于本地忘记重建、生成物体积大、源码与发布物双份审阅成本；后续可评估改为 release 时生成或保留提交产物但强化 pre-commit。 |
| M1/M15 | 版本完全浮动，始终 `releases/latest` | **二进制应用已修复；自定义应用仍有差异** | `lib/binary_app.sh:596-600, 663-670` 支持并校验 `BA_VERSION`，安装配置记录 `INSTALLED_VERSION`；未设置时仍为 latest，设置后 update 只针对 pinned tag，`check-update` 显示当前/目标。Sub2API 已接入共享版本查询适配器；Hugo 支持 `HUGO_VERSION` 精确 pin、安装记录和统一版本输出；TickFlow 支持 `TICKFLOW_COMMIT` 的完整 SHA pin、安装记录和本地 JSON 比对；CyberStrikeAI 支持 `GITHUB_COMMIT` 的完整 SHA pin、安装记录和本地 JSON 比对；Vaultwarden 使用镜像 tag。故“全部 10 个二进制应用浮动”已过时，但全仓库尚未统一版本策略。 |
| M11/M8 | Hugo `.deb` 无 SHA-256；Vaultwarden 用 root crontab 覆盖 | **已修复** | `impl/install_hugo_blog.sh:62-70, 308-340` 提取 GitHub asset digest 并校验后才 `dpkg -i`；Vaultwarden 使用 `/etc/cron.d/vaultwarden-backup` 与 `/etc/cron.d/certbot-renew` 原子写入，不再覆盖 root crontab。提交 `7640720`。 |

### 2.3 一致性与体验问题

| 编号 | 原建议 | 当前状态 | 证据与说明 |
|---|---|---|---|
| L2 | 四套中央命令参数解析重复，flag 可能静默忽略 | **已修复** | `lib/manager_args.sh:4-18, 55-118` 统一解析 `--json`、`--include`、`--exclude`、`--dry-run`、`--continue-on-error` 等；未知/不支持参数进入 usage 并返回非零。`update-all` 的 continue-on-error 是固有行为，文档已说明。提交 `a1237c9`。 |
| L2 | 单应用缺少 `--dry-run` 和完整 `--help` | **已修复** | `lib/cli.sh:1-58, 143-165` 实现单应用 `--dry-run` 与根据 `CONFIG_KEYS` 输出配置键及当前值；`docs/apps.md:7-10` 已记录。 |
| L2 | 无单应用文档 | **已修复** | 新增 `docs/apps.md`，覆盖 16 个应用的共性配置、应用专属配置、默认值、认证、备份/恢复和安全默认。中央命令另有 `docs/central-commands.md`。提交 `3848a93`。 |
| L1/L3/L7/L6 | 配置命名、shebang、时区、Nginx default 清理不一致 | **大部分已修复** | shebang 已统一；Sub2API 使用可配置 `SUB2API_TZ`，不再硬编码 `Asia/Shanghai`；Nginx default 由共享 helper 备份/恢复；配置路径仍保留历史兼容和应用语义差异（如 Vaultwarden `/etc/vaultwarden.env`、Sub2API `/etc/sub2api`），不建议为表面统一破坏兼容性。 |

## 3. 建议新增功能完成度

| 优先级 | 功能 | 完成度 | 当前实现 / 剩余工作 |
|---|---|---|---|
| 高 | 应用版本固定（pin）机制 | **已完成（主要覆盖）** | `BA_VERSION`、安装记录、显式 pinned update、`check-update` 已落地；Hugo 也已支持 `HUGO_VERSION`、`INSTALLED_VERSION` 和统一 JSON 输出。剩余：为 Vaultwarden 镜像、git branch/源码构建统一版本记录与升级策略。 |
| 高 | 单应用 `--dry-run` + 完整 `--help` | **已完成** | 共用 `lib/cli.sh`；帮助输出 `CONFIG_KEYS`，dry-run 覆盖 install/update/backup/uninstall。 |
| 高 | 一键 HTTPS | **已完成（框架/二进制应用）** | `BA_ENABLE_HTTPS=1` + `DOMAIN` 走共享 certbot/nginx 流程；默认 loopback。Vaultwarden/CPA Stack 等已有独立 cert 流程，需按应用设置域名和邮箱。仍不是所有自定义应用都能用同一开关。 |
| 中 | 卸载前配置导出 | **已完成** | `lib/cli.sh:80-102` 在 uninstall 前 best-effort 导出 mode 600 配置并提示恢复；中央 `export/import` 也支持整机配置迁移。 |
| 中 | 多实例支持 | **已完成（中央入口）** | `deploy.sh <app>@<instance> <action>` 已实现独立配置/锁路径；仍应补充实例级文档、冲突测试和自定义应用的运行时隔离说明。 |
| 中 | `dist/` 漂移 CI 强制 | **已完成（push/PR）** | `.github/workflows/verify.yml` 的 release/dispatch/guards 在每次 push/PR 执行；nightly 另跑 all。可选增强是 pre-commit hook。 |
| 低 | 中央命令参考文档 | **已完成** | `docs/central-commands.md` 已覆盖批次命令、notify、schedule、export/import、fleet、self-update、restore 等。 |
| 低 | 迁移四个手写应用到 binary_app | **已完成可行性评估；不宜强行全部迁移** | New API 已迁移；其余三项因分发/依赖/备份模型差异保留手写，并复用共享 helper。下一步应是提取更细粒度公共原语，而不是为了行数强行合并。 |
| 低 | 配置 diff / 审计 | **已完成** | `lib/app.sh:676-698, 746-756` 的 `doctor` 会比较当前配置与安装时 baseline，敏感值只报告“发生变化”，不打印秘密。 |

## 4. 目前仍需关注的风险与边界

### 4.1 真实部署与发布验证

当前验证重点是 Bash 静态/结构检查、stub 行为验证和 Docker smoke；这能覆盖生命周期文件操作和 CLI 路径，但不能替代真实 Debian/Ubuntu 主机上的：

- systemd、Nginx、certbot、Docker、PostgreSQL、Redis 的真实版本兼容性；
- GitHub release/镜像站的真实资产可用性、限流、签名/摘要变化；
- 真实公网 DNS、IPv6、防火墙、TLS 续期和反向代理配置；
- 升级/恢复跨版本数据兼容性。

### 4.2 凭据与旧安装残留

安全修复只约束新代码和新安装流程。已部署旧版本的主机应执行一次人工迁移审计：

1. 检查并删除旧的 Vaultwarden token 临时文件和终端/日志残留；
2. 轮换 Vaultwarden Admin Token、Sub2API PG 密码、应用默认管理员密码；
3. 检查监听地址和防火墙规则，确认不需要的公网端口已关闭；
4. 检查 `/etc/cron.d/` 与历史 root crontab，删除旧备份任务后再启用新任务；
5. 使用 `status-json`、`doctor`、`verify` 确认服务和备份健康。

### 4.3 版本可复现性的剩余边界

当前 `BA_VERSION` 只对共享 GitHub Release 二进制应用提供通用 pin。当前共有 10 个应用使用该共享生命周期。仍有几类版本来源需要独立策略：

- Vaultwarden：`VW_IMAGE_TAG` 已可指定镜像 tag，但镜像 tag 不等同于不可变 digest；
- Hugo：已支持 `HUGO_VERSION` 精确 release pin，并保存 `INSTALLED_VERSION`；未设置时仍采用 GitHub latest，`check-update` 使用共享 JSON 协议；
- TickFlow：默认仍为 git branch 模式，但现已可通过 `TICKFLOW_COMMIT` 固定完整 SHA；未设置 pin 时 branch 会移动；
- CyberStrikeAI：默认仍为 git branch 模式，但现已可通过 `GITHUB_COMMIT` 固定完整 SHA；未设置 pin 时 branch 会移动；
- CPA Stack/Sub2API：多组件或自定义版本来源，需记录完整组件版本。

## 5. 下一阶段建议（按优先级）

### P0：生产安全与回归防护

- [x] 为安全默认增加行为级 guard：验证所有 Web 应用默认 loopback；验证 `BA_FIREWALL=0`；验证 TickFlow 自动生成非空密码；验证安装摘要不含已知凭据模式。新增 `DEPLOY_FAIL_ON_INSECURE_PUBLIC_BIND=1` 后，共享二进制生命周期与 TickFlow 对显式 wildcard + 无 TLS 组合支持统一 hard-fail。
- [x] 为旧安装提供一次性迁移/清理提示或 `doctor security` 检查，识别旧 token 临时文件、旧明文 DSN、旧公网监听和 root crontab 残留；审计只读、默认脱敏，并支持 `--json`。
- [x] 为显式公网绑定 + 未启用 TLS 的组合提供统一 hard-fail 选项（当前主要是 warning），避免误部署明文服务：`DEPLOY_FAIL_ON_INSECURE_PUBLIC_BIND=1` 已接入共享二进制应用与 TickFlow。

### P1：版本与部署可复现性

- [ ] 为 Vaultwarden/CPA Stack/Sub2API 定义统一版本记录字段；Hugo 已具备 `HUGO_VERSION`、`INSTALLED_VERSION` 和 GitHub release tag 语义，TickFlow/CyberStrikeAI 已具备完整 SHA commit pin、`INSTALLED_VERSION` 和本地 git commit JSON 语义。后续优先支持不可变镜像 digest 和组件版本 manifest。
- [ ] 为 `check-update` 补齐其余非 GitHub Release 应用的统一输出协议，明确 latest/tag/branch/commit 的语义；Hugo 已接入 `github_release` 输出，TickFlow pinned commit 已接入本地 `git_commit` 输出（`cache_state=pinned`），两者 pinned target 都不联网查询 latest。
- [ ] 将 E2E smoke 从当前代表性矩阵扩展到真实依赖服务或可复用容器 fixture。

### P2：维护成本与发布流程

- [ ] 评估 `dist/` 是否继续提交：若继续，增加 pre-commit 生成检查；若不继续，改为 release pipeline 生成并在文档中明确源码入口。
- [ ] 提取 Sub2API、Vaultwarden、CyberStrikeAI 共同的“配置/锁/回滚/健康/备份”原语，继续减少复制，但保持应用特有分发和数据模型。
- [ ] 增加实例级文档、TLS 反代示例、配置导出/导入演练文档。

## 6. 推荐验证命令

在 Windows PowerShell 中使用 Git Bash 执行：

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tools/verify.sh syntax
& 'C:\Program Files\Git\bin\bash.exe' tools/verify.sh release
& 'C:\Program Files\Git\bin\bash.exe' tools/verify.sh dispatch
& 'C:\Program Files\Git\bin\bash.exe' tools/verify.sh guards
& 'C:\Program Files\Git\bin\bash.exe' tools/verify.sh all
& 'C:\Program Files\Git\bin\bash.exe' tools/e2e-smoke.sh
```

本次已执行仓库盘点和源码证据核对；尚未执行需要 Linux/systemd/Docker 的完整验证。提交前至少执行 `syntax`、`release` 和 `guards`，并确认 `git diff --check` 通过。

## 7. 参考

- [README.md](../README.md)
- [PLAN.md](../PLAN.md)
- [CHANGELOG.md](../CHANGELOG.md)
- [应用部署参考](apps.md)
- [中央命令参考](central-commands.md)
- [持续进度日志](progress.log)
