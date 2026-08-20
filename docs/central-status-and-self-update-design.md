# 中控状态中心与脚本自更新系统：详细设计

- **状态**：提案
- **作者**：Codex
- **日期**：2026-08-20
- **适用仓库**：`deploy-scripts`
- **目标版本**：分阶段交付；第一阶段不改变任何现有应用的安装、更新和卸载语义。

## 1. 背景与现状

仓库已经提供了一个以 Bash 实现的应用部署框架：

- 根入口 `deploy.sh` 会转发到 `bin/deploy.sh`；
- `lib/manager_cli.sh` 根据 `lib/app_registry.sh` 的注册表调度应用；
- 每个应用由 `apps/<app>.sh`（定义和文案）与 `impl/install_<app>.sh`（生命周期实现）组成；
- 公共框架已经统一了锁、配置保存、systemd、网络、原子文件写入和 i18n；
- 应用层已经有 `install`、`update`、`backup`、`restore`（部分应用）、`status`、`status-json`、`doctor`、`uninstall`；
- `lib/app.sh` 的 `do_status_json()` 已经能输出配置、记录版本和一个或多个 systemd 服务的基础状态；
- 二进制应用通过 `lib/binary_app.sh` 共享版本、健康检查和 `bapp_status` 能力；
- `tools/verify.sh` 与 `tools/checks/` 提供语法、ShellCheck、发布包一致性、调度和框架守卫检查。

但中控目前仍是“选择一个应用后执行一个动作”的调度器，缺少跨应用可观测性和框架自身的生命周期管理：

1. 无法用一条命令获得所有已注册应用的安装、服务、健康、版本、备份与最近操作状态；
2. 各应用 `status` 面向人类的输出格式不同，不能稳定汇总；
3. 现有 `status-json` 是有价值的基础，但没有统一的安装状态、健康状态、可更新状态和最近一次操作信息；
4. 应用更新与“部署脚本框架更新”没有明确的命令和安全边界；
5. 当前从仓库工作区或 `dist/` 单文件运行时，没有支持校验、原子切换、回滚和审计记录的自更新流程。

本设计把仓库从“应用部署脚本集合”增强为“可观测、可审计、可回滚的部署中控”。

## 2. 目标、非目标与设计原则

### 2.1 目标

1. 提供稳定的全局状态总览，支持人类可读表格和机器可读 JSON。
2. 定义统一状态模型，允许应用在不改写所有既有 `status` 输出的情况下逐步接入。
3. 记录安装、更新、备份、恢复和卸载等操作的进度与最终结果，便于失败定位和后续汇总。
4. 提供批量诊断、批量备份和批量应用更新的公共调度能力，但默认保守、安全。
5. 提供中控脚本的**发布包式**自更新：校验、暂存、验证、原子激活、回滚和审计完整闭环。
6. 保持现有直接应用调用方式兼容，例如 `deploy.sh newapi update` 与 `install_newapi.sh update`。
7. 不在状态文件、命令输出或日志中记录密码、令牌、私钥、完整环境变量或应用配置正文。

### 2.2 非目标

本期不实现以下内容：

- 不提供 Web 面板、数据库或常驻守护进程；CLI/JSON 是唯一接口。
- 不将所有应用的运行日志集中采集或替代 journald。
- 不保证所有第三方应用都可以可靠检查最新版本；不能可靠检查时必须明确显示“未支持/未知”，不能猜测“已是最新”。
- 不自动执行可能造成数据不可逆变化的数据库迁移，也不改变现有卸载时保留数据的安全默认值。
- 不在开发者本地 Git 工作区中无提示覆盖未提交代码。
- 不以 `curl URL | bash` 或覆盖当前正在执行的文件作为升级机制。

### 2.3 设计原则

- **状态与动作分离**：查询状态不得修改应用、配置或服务；`overview`、`status-all`、`check-update`、`doctor-all` 均为只读动作。
- **应用更新与中控更新分离**：`deploy.sh <app> update` 更新应用；`deploy.sh self-update` 更新框架。两者不能复用同一个含义模糊的命令。
- **失败可见、失败可恢复**：每次写操作都有持久化运行记录；自更新失败不激活半成品版本，并尽可能保留可用的上一个版本。
- **安全优先**：更新包在下载后必须校验哈希；启用签名校验后，签名失败必须终止；任何未验证内容不得执行。
- **渐进兼容**：以公共默认实现提供基础状态；高级探针由应用选择性声明，旧应用不因未接入而失效。
- **机器接口稳定**：JSON 结构有 `schema_version`，新增字段允许，字段语义变更必须提升主版本或增加新字段。
- **避免新增运行时依赖**：核心逻辑仅要求现有 Bash、curl、coreutils、systemd（有服务的机器）；JSON 由 Bash 输出，不要求 `jq`。签名验证工具可以是可选能力。

## 3. 术语与边界

| 术语 | 含义 |
|---|---|
| 应用（app） | 注册表中一个可独立部署和管理的项目，如 `newapi` 或 `gitea`。 |
| 中控/框架（framework） | `deploy.sh`、`bin/`、`lib/`、`apps/`、`impl/` 等共同构成的部署框架。 |
| 应用更新 | 下载或部署某个应用的新版本，由 `<app> update` 执行。 |
| 中控更新 | 安装一份新的、经过验证的框架发布包，由 `self-update` 执行。 |
| 观测快照 | 一次只读状态采集的内存结果；除显式缓存外不落盘。 |
| 操作记录（operation record） | 某个改变系统的生命周期操作的开始、阶段、成功或失败信息。 |
| 已安装 | 应用的受管配置文件存在且安全，或由应用的专用判定函数确认；不等同于服务正在运行。 |
| 健康 | 应用可用性的探测结果；可能是 HTTP、TCP、systemd 或专用探针。 |
| 发布包 | 可验证的中控框架归档文件及其清单、校验值和可选签名。 |
| 激活 | 将受管安装目录中的 `current` 原子切换到某个完整发布版本。 |

## 4. 总体架构

### 4.1 模块划分

新增模块建议如下：

```text
lib/
  state.sh           # 统一状态模型、状态收集、JSON/表格渲染
  operation.sh       # 生命周期操作记录和阶段进度
  version.sh         # 版本规范化、比较与可更新检查
  manager_status.sh  # overview/status-all/problems/health-all/doctor-all
  self_update.sh     # 发布清单、下载校验、版本激活、回滚
  manager_cli.sh     # 仅增加命令路由，保持为薄层

tools/checks/
  state.sh           # 状态 JSON、退出码、注册表遍历检查
  operation.sh       # 操作记录格式和失败清理检查
  self-update.sh     # 清单、校验、切换和回滚守卫检查

docs/
  central-status-and-self-update-design.md
```

现有模块的职责不变：

- `lib/app_registry.sh`：应用 ID、显示名、定义文件和实现文件的权威注册表；
- `lib/app_loader.sh`：按需加载应用定义与实现；
- `lib/app.sh`：应用通用配置、doctor 和 JSON 基础信息；
- `lib/binary_app.sh`：二进制应用的共享安装、更新、健康检查与状态输出；
- `lib/lock.sh`：互斥；
- `lib/atomic.sh`：文件和软链接的原子写入/切换；
- `lib/network.sh`：网络下载和 GitHub release 查询的既有能力；
- `lib/manager_cli.sh`：中控命令解析，不承载业务实现。

`lib/core.sh` 负责按依赖顺序加载新增模块。建议顺序为：`app_registry.sh`、`app_loader.sh`、`version.sh`、`operation.sh`、`state.sh`、`self_update.sh`、`cli.sh`、`manager_status.sh`、`manager_cli.sh`。

### 4.2 两条执行路径

```text
只读状态路径：
  deploy.sh overview/status-all/problems/check-update
    -> manager_status
    -> app registry
    -> source app definition + source impl（只加载，不执行 lifecycle）
    -> app_status_collect
    -> JSON 或表格渲染

写操作路径：
  deploy.sh <app> install/update/backup/restore/uninstall
    -> manager_cli + app_loader
    -> operation_start
    -> 既有 do_* 生命周期函数
    -> operation_step / operation_finish

框架更新路径：
  deploy.sh self-update
    -> self_update
    -> 获取 manifest + 校验
    -> 下载归档到临时目录 + 校验
    -> 解压、离线验证
    -> releases/<version> 暂存
    -> 原子切换 current
    -> 运行激活后 smoke check
    -> 成功保留，失败自动回滚
```

### 4.3 单一状态来源的优先级

状态采集必须避免把“缓存”误认为事实。字段来源按以下优先级使用：

1. **实时系统事实**：文件存在性、权限、`systemctl`、本地健康探针、端口监听；
2. **受管配置**：`/etc/<app>-deploy.conf` 或通过 `app_conf_file()` 确定的兼容路径，读取 `INSTALLED_VERSION` 等非敏感字段；
3. **应用声明的专用采集函数**：多服务、Docker Compose、Nginx 或特殊部署模式；
4. **操作记录**：只用于显示最近动作和历史结果，不覆盖实时状态；
5. **版本检查缓存**：只用于显示“上次检查结果”，过期后必须标为 `stale`，不能作为更新决策的唯一依据。

## 5. 命令行设计

### 5.1 新增中控命令

| 命令 | 默认性质 | 说明 |
|---|---|---|
| `deploy.sh overview` | 只读 | 全局人类可读状态表；`status-all` 的别名。 |
| `deploy.sh status-all` | 只读 | 所有注册应用的状态表。 |
| `deploy.sh status-all --json` | 只读 | 输出稳定的全局 JSON 文档。 |
| `deploy.sh status-all --short` | 只读 | 仅显示已安装应用及存在异常/更新的项目。 |
| `deploy.sh problems` | 只读 | 仅显示异常、退化、失败或配置不安全项目。 |
| `deploy.sh health-all` | 只读 | 对已安装应用执行健康采集并输出摘要。 |
| `deploy.sh doctor-all` | 只读 | 对已安装应用执行 `doctor`，逐项汇总；失败后继续。 |
| `deploy.sh check-update` | 网络只读 | 检查所有支持版本检查的已安装应用是否有更新。 |
| `deploy.sh update-all` | 写操作 | 逐个更新已安装且有更新的应用；需要确认或 `DEPLOY_ASSUME_YES=1`。 |
| `deploy.sh backup-all` | 写操作 | 逐个备份已安装应用；需要确认或 `DEPLOY_ASSUME_YES=1`。 |
| `deploy.sh history [app]` | 只读 | 展示中控维护的操作历史。 |
| `deploy.sh self-version` | 只读 | 显示框架安装模式、当前版本、前一版本、更新渠道。 |
| `deploy.sh self-update --check` | 网络只读 | 检查指定渠道是否有框架更新。 |
| `deploy.sh self-update` | 写操作 | 下载、验证并原子激活框架更新。 |
| `deploy.sh self-update --rollback` | 写操作 | 回滚到上一份已成功激活的框架版本。 |
| `deploy.sh self-update --list` | 只读 | 列出本地受管安装中可回滚版本。 |

不新增裸 `update`、裸 `status` 等中控命令，以避免和应用命令产生歧义。

### 5.2 选项约定

所有新增命令统一支持：

```text
--json                 输出 JSON；JSON 输出不得混入颜色、进度或提示文本。
--short                精简人类可读输出。
--only-installed       仅处理已安装应用；批量写操作默认启用。
--include <id,id...>   仅处理指定应用 ID。
--exclude <id,id...>   排除指定应用 ID。
--continue-on-error    单个应用失败后继续；批量命令默认启用。
--no-network           禁止网络访问；版本字段仅使用缓存或显示 unknown。
--refresh              忽略可更新缓存并联网刷新。
--dry-run              显示将执行的写操作，不改变系统。
--yes                  等价于本次进程 `DEPLOY_ASSUME_YES=1`，仅用于确定性批量确认。
```

约束：

- `--json` 不可与交互菜单混用；
- `--dry-run` 仅适用于 `update-all`、`backup-all` 和 `self-update`；
- `--refresh` 与 `--no-network` 互斥；
- 选项解析失败退出码为 `2`；
- 未支持应用或未知应用 ID 退出码为 `2`，不得静默跳过。

### 5.3 交互菜单

`deploy.sh` 无参数时仍进入现有应用选择菜单。在菜单首屏追加只读入口：

```text
  s) 全部应用状态
  p) 仅查看异常
  u) 检查应用更新
  f) 检查中控更新
```

不将 `update-all` 和 `self-update` 直接放在首屏的一键危险操作中。用户必须进入明确的确认流程，看到影响范围、待更新版本与备份策略后才能执行。

### 5.4 退出码

为新增中控命令定义固定退出码；既有应用动作的退出码保持兼容，后续再逐步统一：

| 退出码 | 含义 |
|---:|---|
| `0` | 成功；状态检查未发现异常。 |
| `1` | 一般执行失败或至少一个批量子任务失败。 |
| `2` | 参数、命令或应用 ID 错误。 |
| `3` | 请求的对象未安装或不存在。 |
| `4` | 服务状态异常。 |
| `5` | 健康检查失败或退化。 |
| `6` | 发现可用更新（仅 `check-update` / `self-update --check` 的可选严格模式）。 |
| `7` | 配置安全性或完整性检查失败。 |
| `8` | 权限不足。 |
| `9` | 锁冲突，已有互斥操作运行。 |
| `10` | 网络、下载或远端清单失败。 |
| `11` | 自更新校验、激活或回滚失败。 |

默认 `status-all` 即使存在异常也退出 `0`，便于人工查看；传入 `--strict` 时，按最高严重度返回 `4`、`5` 或 `7`。`problems --strict` 默认启用严格模式。

## 6. 统一状态模型

### 6.1 枚举值

所有机器可读状态均使用英文、snake_case 枚举；人类展示由 i18n 翻译。

#### 安装状态 `install_state`

| 值 | 判定 |
|---|---|
| `not_installed` | 未发现安全有效的受管配置，且专用检测未确认安装。 |
| `installed` | 发现安全配置或专用检测确认安装。 |
| `installing` | 最新操作记录仍处于运行状态且动作为 `install`。 |
| `install_failed` | 最近一次 install 失败，且尚未有成功 install/update 覆盖。 |
| `uninstalling` | 最新操作记录仍处于运行状态且动作为 `uninstall`。 |
| `uninstall_failed` | 最近一次 uninstall 失败。 |
| `unknown` | 无法安全读取或应用未提供可判定信息。 |

`installed` 不代表健康；配置存在但权限不安全时可标记 `installed` 同时 `config.safe=false`，总体严重度为 `critical`。

#### 服务状态 `service.state`

`running`、`stopped`、`failed`、`disabled`、`not_found`、`not_managed`、`unknown`。

多服务应用不把单个服务状态简化为真/假：顶层 `service.state` 为聚合值，具体值在 `services[]` 中展示。

#### 健康状态 `health.state`

`healthy`、`degraded`、`unhealthy`、`not_checked`、`unsupported`、`unknown`。

- HTTP 返回应用声明成功码：`healthy`；
- 服务运行但探针失败：`unhealthy`；
- 服务运行、健康端点短暂不可用且应用声明可接受初始化：`degraded`；
- 未请求联网/无 curl/为节省开销未探测：`not_checked`；
- 应用明确没有可行探针：`unsupported`。

#### 版本状态 `version.update_state`

`up_to_date`、`update_available`、`check_failed`、`unsupported`、`unknown`、`stale`。

“无法检查”绝不能映射为 `up_to_date`。

### 6.2 单应用 JSON 合约

`deploy.sh <app> status-json` 保持现有顶层字段兼容，并在第一阶段将其扩展为下列形式。字段可新增，既有 `config`、`version`、`service`、`services` 字段不可重命名：

```json
{
  "schema_version": 2,
  "collected_at": "2026-08-20T14:30:12+08:00",
  "app_id": "newapi",
  "app_name": "New API",
  "root": true,
  "install_state": "installed",
  "severity": "ok",
  "config": {
    "path": "/etc/newapi-deploy.conf",
    "exists": true,
    "owner": "root",
    "mode": "600",
    "safe": true,
    "valid": true
  },
  "version": {
    "installed": "v1.2.3",
    "latest": null,
    "checked_at": null,
    "update_state": "unknown",
    "source": "config"
  },
  "service": {
    "name": "newapi",
    "systemctl_available": true,
    "unit_exists": true,
    "active": true,
    "enabled": true,
    "state": "running"
  },
  "services": [],
  "health": {
    "state": "healthy",
    "checked_at": "2026-08-20T14:30:12+08:00",
    "probe_type": "http",
    "url": "http://127.0.0.1:3000/health",
    "http_code": 200,
    "message": null
  },
  "backup": {
    "state": "available",
    "last_success_at": "2026-08-19T02:00:00+08:00",
    "path": "/var/backups/newapi",
    "message": null
  },
  "operation": {
    "state": "idle",
    "last_action": "update",
    "last_result": "success",
    "last_started_at": "2026-08-19T01:57:00+08:00",
    "last_finished_at": "2026-08-19T02:00:00+08:00",
    "last_step": "health_check",
    "last_error_code": null,
    "last_error_summary": null,
    "log_path": "/var/log/deploy-scripts/newapi/20260819T015700+0800-update.log"
  }
}
```

要求：

- 所有时间使用 RFC 3339 带时区偏移；采集不到则为 `null`，不输出空字符串；
- `message` 和 `last_error_summary` 必须是去敏后的摘要，长度上限 512 字节；
- 密钥、密码、Token、连接串、域名之外的私有配置不允许进入 JSON；
- JSON 输出只写 stdout，诊断和下载错误写 stderr；
- `schema_version` 初始为 `2`，今后仅新增可选字段不升版本。

### 6.3 全局 JSON 合约

`deploy.sh status-all --json` 输出单个文档：

```json
{
  "schema_version": 1,
  "generated_at": "2026-08-20T14:30:12+08:00",
  "framework": {
    "version": "v1.4.0",
    "install_mode": "checkout",
    "channel": "stable"
  },
  "summary": {
    "registered": 18,
    "installed": 6,
    "healthy": 5,
    "degraded": 0,
    "unhealthy": 1,
    "not_installed": 12,
    "update_available": 2,
    "errors": 0
  },
  "apps": [
    { "app_id": "newapi", "install_state": "installed", "severity": "ok" }
  ],
  "errors": []
}
```

为减少总览开销，默认 `apps[]` 可包含完整单应用状态对象；未来如果对象变大，再以 `--detail` 控制扩展字段，但不得让同一字段改变类型。

### 6.4 严重度计算

公共聚合函数 `state_calculate_severity` 按从高到低的规则计算：

1. `critical`：配置不安全/无效，或正在运行的应用最近操作留下未恢复的严重失败；
2. `error`：已安装应用的服务 `failed`/`stopped`，或健康 `unhealthy`；
3. `warning`：健康 `degraded`、服务未启用、无最近成功备份、版本可更新、版本检查过期；
4. `info`：未安装、健康不支持、版本检查不支持；
5. `ok`：已安装、运行、健康、配置安全且没有更高等级问题；
6. `unknown`：无法收集关键事实。

未安装应用默认是 `info`，不会在 `problems` 中出现。`--short` 输出 `warning` 及以上；`problems` 输出 `critical`、`error` 和 `warning`，可通过 `--errors-only` 过滤为前两类。

## 7. 状态采集与应用扩展点

### 7.1 基础采集流程

每个应用的状态采集必须在子 shell 中执行，防止应用加载期间修改变量、trap 或函数影响中控后续应用：

1. 从注册表读取应用 ID；
2. 在子 shell 内通过现有 `manager_load_app` 加载应用定义；
3. 仅 source 实现脚本，禁止调用 `do_install`、`do_update` 等写函数；
4. 调用 `app_status_collect_json`；
5. 捕获 stdout 中的单个 JSON 对象、stderr 和退出码；
6. 将加载错误包装进全局 `errors[]`，继续采集其他应用。

采集超时采用可配置的 `DEPLOY_STATUS_TIMEOUT_SECONDS`，默认 8 秒。没有 `timeout` 命令时仍执行，但在结果中标记 `timeout_enforced=false`。健康探针单应用默认不超过 5 秒。

### 7.2 公共默认实现

`lib/state.sh` 中的 `app_status_collect_json` 负责：

- 调用现有 `app_conf_file()`、`app_doctor_validate_saved_config()`、`app_config_installed_version()`；
- 调用 `app_doctor_service_name()` 与 `APP_DOCTOR_SERVICES_FN`；
- 将 systemd 原始状态标准化为新枚举；
- 根据操作记录计算 `install_state` 的“进行中/失败”覆盖状态；
- 调用可选扩展点采集版本、健康、备份；
- 统一输出 JSON。

`do_status_json()` 改为薄包装：

```bash
do_status_json() {
  app_status_collect_json
}
```

这样既保留当前 CLI 合约，也避免两个 JSON 状态实现逐渐分叉。

### 7.3 应用可选扩展点

应用不直接拼接最终 JSON。应用可以声明以下函数；缺失时使用公共默认或 `unsupported`：

```bash
# 输出一个 JSON 对象，不含 app_id/app_name 等公共字段。
# 失败返回非 0，公共层将 health.state 标为 unknown 并记录安全摘要。
APP_STATUS_HEALTH_FN=myapp_status_health
APP_STATUS_VERSION_FN=myapp_status_version
APP_STATUS_BACKUP_FN=myapp_status_backup
APP_STATUS_INSTALL_FN=myapp_status_install

# 多服务应用沿用既有扩展点。
APP_DOCTOR_SERVICE_FN=myapp_primary_service
APP_DOCTOR_SERVICES_FN=myapp_all_services
```

建议输出约定：

```json
{"state":"healthy","probe_type":"http","url":"http://127.0.0.1:3000/health","http_code":200,"message":null}
```

版本扩展点：

```json
{"installed":"v1.2.3","latest":null,"checked_at":null,"update_state":"unknown","source":"config"}
```

备份扩展点：

```json
{"state":"available","last_success_at":"2026-08-19T02:00:00+08:00","path":"/var/backups/newapi","message":null}
```

扩展点应当只访问本机状态，除非调用方显式要求版本联网检查；必须遵守 `DEPLOY_STATUS_NO_NETWORK=1`。

### 7.4 二进制应用接入

`lib/binary_app.sh` 已有 `GITHUB_REPO`、`INSTALLED_VERSION`、`BA_HEALTH_URL`、`BA_HEALTH_CODES`、`bapp_health_probe` 和 `bapp_status`。新增适配器应在公共二进制库中提供：

- `bapp_status_health_json`：复用健康 URL 和成功码；
- `bapp_status_version_json`：从配置读取 `INSTALLED_VERSION`；只有 `check-update --refresh` 才调用 `github_latest_release_tag`；
- `bapp_status_backup_json`：根据 `BACKUP_DIR` 和最近成功记录返回状态；
- `bapp_status_install_json`：基于受管配置与二进制/服务存在性给出更准确判断。

这样 ntfy、Meilisearch、Alist、Filebrowser、Navidrome、frps、Gitea、Gotify、Beszel 等共享二进制生命周期的应用无须逐个复制采集逻辑。

### 7.5 特殊应用接入

New API、Sub2API、Vaultwarden、CyberStrikeAI、Hugo Blog、TickFlow、CPA Stack 等需要各自实现少量适配器：

- 多 systemd 服务：输出 `services[]`，顶层服务状态由公共层聚合；
- Docker Compose：检查 compose 服务状态，且不能依赖彩色的 `docker compose ps` 表格；
- Nginx 静态站点：服务健康应定义为 Nginx 正常、站点文件存在，必要时加本地 HTTP 检查；
- 没有可比版本的 Git 工作树型应用：版本可采用 commit SHA，`update_state` 设为 `unsupported` 或由专用远端比较实现；
- HTTP 健康码有特例的应用必须在应用定义中声明成功码，不能在中控写 app ID 特判。

## 8. 操作进度、运行记录与日志

### 8.1 目录布局

所有中控新增运行时文件使用独立目录，不污染已有 `/etc/<app>-deploy.conf`：

```text
/var/lib/deploy-scripts/
  state/
    <app-id>.json                  # 最近完成或失败操作的摘要，不是实时状态缓存
  history/
    operations.jsonl               # 仅追加的全局操作索引
  self-update.json                 # 中控更新状态
  locks/
    manager.lock                   # 批量中控互斥锁
    self-update.lock               # 自更新互斥锁

/var/log/deploy-scripts/
  <app-id>/
    20260820T143012+0800-install.log
    20260820T151025+0800-update.log
  manager/
    20260820T160000+0800-update-all.log
  self-update/
    20260820T170000+0800-self-update.log
```

创建规则：

- 数据目录权限 `0750 root:root`；
- 状态和历史文件权限 `0640 root:root`；
- 日志目录权限 `0750 root:root`；日志文件 `0640 root:root`；
- 写文件使用 `atomic_write_file` 或追加后严格检查；
- 写状态失败不能掩盖原操作的失败，但必须输出警告；
- 日志应接入 logrotate，默认保留 30 天/20 个文件，具体策略可通过全局配置调整。

### 8.2 运行记录格式

每一次会修改系统的顶层命令均创建一个运行 ID：

```text
20260820T143012+0800-newapi-update-6f43b2c1
```

记录对象：

```json
{
  "schema_version": 1,
  "run_id": "20260820T143012+0800-newapi-update-6f43b2c1",
  "scope": "app",
  "app_id": "newapi",
  "action": "update",
  "state": "succeeded",
  "started_at": "2026-08-20T14:30:12+08:00",
  "finished_at": "2026-08-20T14:33:55+08:00",
  "last_step": "health_check",
  "steps": [
    {"name":"backup","state":"succeeded","started_at":"...","finished_at":"..."},
    {"name":"download","state":"succeeded","started_at":"...","finished_at":"..."}
  ],
  "exit_code": 0,
  "error": null,
  "log_path": "/var/log/deploy-scripts/newapi/20260820T143012+0800-update.log"
}
```

状态枚举：`running`、`succeeded`、`failed`、`cancelled`、`interrupted`、`rolled_back`、`rollback_failed`。

`operations.jsonl` 只存摘要，按一行一个 JSON 写入；每应用最新对象写入 `state/<app-id>.json`，供状态页 O(1) 读取。全局索引不可作为唯一事实来源，损坏时状态采集仍可进行。

### 8.3 生命周期接入方式

不要求立即重写全部 `do_*`。采用两层接入：

1. **第一阶段外层包装**：中控从 `manager_main` 调度应用动作时，执行 `operation_run_app_action <app> <action>`，自动记录开始、退出结果、退出码和日志；直接调用 `install_<app>.sh` 时通过 `app_loader.sh` 的共用 dispatch 包装获得相同记录。
2. **第二阶段应用阶段标注**：现有实现逐步在关键点添加 `operation_step_start` / `operation_step_finish`，例如 `preflight`、`backup`、`download`、`verify`、`configure`、`service_restart`、`health_check`。

用于捕获意外退出的 trap 必须保留并链式调用现有 `deploy_add_exit_handler()`，不能覆盖 `lock.sh` 已注册的清锁 handler。`set -e` 导致的退出同样应被记录为 `failed` 或 `interrupted`。

### 8.4 日志去敏

日志默认通过 `tee` 同时输出至终端和文件。不得盲目记录 shell xtrace；禁止启用 `set -x`。写入前应对已知敏感模式进行基础脱敏：

- `TOKEN=...`、`PASSWORD=...`、`SECRET=...`、`KEY=...`、`Authorization: Bearer ...`；
- URL 中 `user:password@host` 的 password 部分；
- 不记录完整配置文件内容。

这只是防御性措施，应用实现仍必须避免将秘密传入日志。

## 9. 批量操作设计

### 9.1 目标选择

`update-all`、`backup-all`、`doctor-all`、`health-all` 的目标集通过下列顺序计算：

1. 从注册表取得稳定顺序；
2. 应用 `--include` 与 `--exclude`；两者同时给出时先 include 后 exclude；
3. 对默认 `--only-installed` 使用**无网络的基础状态采集**筛选；
4. 输出最终目标列表和跳过原因；
5. 写操作等待确认，`--dry-run` 只输出计划。

默认不并行执行写操作：多个应用可能共享 apt、Nginx、防火墙、80/443 端口或网络带宽。`doctor-all`、`status-all` 可在后续版本引入受限并行，但第一版保持串行，优先保证可读日志和确定性。

### 9.2 `update-all`

默认策略：

1. 只更新已安装且 `update_state=update_available` 的应用；
2. 版本检查失败/未知/不支持的应用列为跳过，不尝试猜测更新；
3. 每个应用仍由自己的 `do_update` 决定下载、备份和重启细节；
4. 任一应用失败后记录失败并继续下一个；
5. 最终显示成功、失败、跳过和未支持列表；若有失败退出 `1`。

必须明确：`update-all` **不是**“强制所有应用重新部署”。提供 `--force` 只能作为后续显式扩展，第一期不实现。

### 9.3 `backup-all`

仅调用已安装应用的 `do_backup`。应用不支持备份时记为 `unsupported`，不作为失败。批量备份前应检测磁盘可用空间；实际最小空间需求难以统一时只显示预警，不能凭空拒绝所有备份。

### 9.4 `doctor-all` 与 `health-all`

- `doctor-all` 调用现有 `do_doctor`，捕获完整输出并在汇总中显示结果；
- `health-all` 使用统一状态采集中的健康扩展点，不调用安装、更新或重启；
- `status-all` 默认可执行本地健康探针；使用 `--no-network` 时仍允许 `127.0.0.1` 探针，因为它不访问互联网。若用户需要完全无连接探测，后续可提供 `--no-probe`。

## 10. 框架自更新：发布包式方案

### 10.1 为什么采用发布包而非直接 Git pull

生产服务器上的框架更新必须保证“旧版本仍可运行，直到新版本已完整验证”。直接在工作目录中 `git pull` 或用网络下载覆盖文件存在以下风险：

- 网络中断后工作目录处于部分更新状态；
- 依赖的 `lib/`、`apps/`、`impl/` 与入口脚本版本不匹配；
- 无法可靠回到上一个完整版本；
- 本地修改可能被覆盖；
- 难以对实际执行内容进行完整性校验。

因此生产建议使用版本化发布目录与原子 `current` 符号链接。Git 工作区继续适用于开发和贡献，但不作为生产自更新的写入目标。

### 10.2 受管安装布局

默认受管安装根目录：

```text
/opt/deploy-scripts/
  releases/
    v1.4.0/
      deploy.sh
      bin/
      lib/
      apps/
      impl/
      tools/
      RELEASE.json
    v1.3.2/
  current -> /opt/deploy-scripts/releases/v1.4.0
  previous -> /opt/deploy-scripts/releases/v1.3.2
  bootstrap/
    deploy.sh
  state/
    self-update.json
```

首次采用发布包安装时，推荐为系统命令建立一个稳定入口：

```text
/usr/local/sbin/deploy-scripts -> /opt/deploy-scripts/current/deploy.sh
```

稳定入口只跟随 `current`，不直接指向带版本号目录。`atomic_symlink` 已提供适合的原子软链接切换能力。

### 10.3 运行模式

框架通过 `self-version` 检测模式：

| 模式 | 判定 | `self-update` 行为 |
|---|---|---|
| `managed_release` | 当前脚本位于或通过 `/opt/deploy-scripts/current` 执行，且有有效 `RELEASE.json` | 完整支持检查、更新、回滚。 |
| `checkout` | `DEPLOY_ROOT_DIR/.git` 存在 | 默认只允许 `--check`；不改写工作区。提示使用受管安装或由维护者手工审阅 Git 更新。 |
| `standalone_dist` | 仅发现单文件 dist 脚本，未处于受管发布目录 | 默认仅允许 `--check`，可引导用户执行显式 `self-install` 迁移到受管布局。 |
| `unknown` | 无法确定 | 禁止写更新，只显示诊断。 |

这样可以严格保护当前开发仓库及用户未提交修改。`self-update --force-worktree` 不纳入设计；如果未来需要，也必须另行审计和明确确认。

### 10.4 发布清单

每个发布版本提供一个**独立 JSON manifest**和一个归档包。建议使用发布仓库/Release 附件托管，URL 通过安装配置或环境变量指定。

`manifest.json` 规范：

```json
{
  "schema_version": 1,
  "project": "deploy-scripts",
  "channel": "stable",
  "version": "v1.4.0",
  "published_at": "2026-08-20T08:00:00Z",
  "minimum": {
    "bash": "4.3"
  },
  "artifacts": {
    "source": {
      "name": "deploy-scripts-v1.4.0.tar.gz",
      "url": "https://example.invalid/releases/v1.4.0/deploy-scripts-v1.4.0.tar.gz",
      "sha256": "<64 lowercase hex characters>",
      "size_bytes": 123456
    }
  },
  "notes": [
    "Add global status overview.",
    "Add managed self-update rollback."
  ]
}
```

受管发布包内部必须有 `RELEASE.json`，至少包含：

```json
{
  "schema_version": 1,
  "project": "deploy-scripts",
  "version": "v1.4.0",
  "build_commit": "<commit or verified build identifier>",
  "built_at": "2026-08-20T08:00:00Z"
}
```

外部 manifest 的版本、项目名、归档 SHA256 与归档内部 `RELEASE.json` 必须相互匹配。`tools/build-release.sh` 或新的发布构建工具负责生成这些文件，不能手工维护校验值。

### 10.5 信任与校验

默认安全基线是 HTTPS + 固定 SHA256 校验；更高安全级别支持签名：

```text
DEPLOY_SELF_UPDATE_URL=https://<trusted-release-endpoint>
DEPLOY_SELF_UPDATE_CHANNEL=stable
DEPLOY_SELF_UPDATE_REQUIRE_SIGNATURE=false
DEPLOY_SELF_UPDATE_PUBLIC_KEY=/etc/deploy-scripts/update.pub
```

校验顺序：

1. 检查更新配置的 URL 和渠道值是否合法；
2. HTTPS 下载 manifest 至私有临时目录；拒绝空文件和超过上限的 manifest；
3. 验证 manifest JSON 的严格字段格式、项目名、版本格式、SHA256 格式和 URL scheme；
4. 如果要求签名，验证 manifest 的 detached signature；没有验证器、签名缺失或签名无效均失败；
5. 比较候选版本与当前版本；拒绝降级，除非显式 `--allow-downgrade`（第一期仅预留，不开放）；
6. 下载归档到临时文件，限制最大体积，校验字节数（若提供）和 SHA256；
7. 解压到临时目录，拒绝绝对路径、`..` 路径、设备文件、符号链接逃逸和不符合预期的顶层目录；
8. 校验内部 `RELEASE.json`；
9. 对关键 `.sh` 文件执行 `bash -n`，并执行发布包离线 smoke check；
10. 只有全部完成后才允许写入 `releases/<version>`。

注意：哈希只能保证“下载文件符合 manifest”，不能独立建立信任根；生产环境应逐步把 `DEPLOY_SELF_UPDATE_REQUIRE_SIGNATURE=true` 作为默认，公钥由受控安装流程写入且 root-only 管理。具体签名工具建议优先选择发布与服务器端都易安装的 `minisign`；实现应通过适配层支持替换，不把工具名散落在更新逻辑中。

### 10.6 更新状态机

```text
idle
  -> checking
  -> download_manifest
  -> verify_manifest
  -> download_artifact
  -> verify_artifact
  -> stage_release
  -> validate_release
  -> activate
  -> smoke_check
  -> succeeded

任一步失败：
  -> failed（current 不变）

activate 后 smoke_check 失败：
  -> rolling_back
  -> rolled_back
  或 -> rollback_failed
```

`self-update --dry-run` 执行到 `validate_release` 为止，但绝不写 `releases/`、`current`、`previous` 或状态；允许下载到临时目录并在退出时删除。

### 10.7 激活与回滚

激活操作：

1. 使用 `/var/lib/deploy-scripts/locks/self-update.lock` 获取排他锁；
2. 确保没有正在执行的受管写操作；第一期只通过中控锁协调，不能检测所有外部进程；
3. 将已验证目录以原子 rename 放入 `releases/<version>`；版本目录必须此前不存在；
4. 读取当前 `current` 目标，原子更新 `previous` 为旧目标；
5. 通过 `atomic_symlink` 将 `current` 切换到新版本；
6. 使用新版本运行只读 smoke check：`bash deploy.sh list`、`bash deploy.sh self-version`、`bash deploy.sh status-all --json --no-network`；
7. smoke check 成功则将状态记为 `succeeded`；
8. smoke check 失败则原子将 `current` 指回旧目标并记为 `rolled_back`；若回滚也失败，记为 `rollback_failed` 并在 stderr 输出恢复命令。

`self-update --rollback`：

- 只允许受管发布模式；
- `previous` 必须存在，目标目录必须通过基本 `RELEASE.json` 和 shell 语法验证；
- 激活前展示 `current -> previous` 的版本变化，并要求确认；
- 回滚成功后交换 `current` 和 `previous`，保留再回退能力；
- 不能回滚到已被清理的目录。

### 10.8 发布保留与清理

默认保留：当前版本、前一版本、最近 3 个成功版本，共至少 3 个完整版本；可通过 `DEPLOY_SELF_UPDATE_KEEP_RELEASES` 配置，最小值为 3。

清理只能在一次成功更新后执行；不得删除 `current`、`previous`，不得删除正在被锁定或未验证的目录。清理失败只警告，不影响已完成更新。

### 10.9 自更新配置

配置文件：`/etc/deploy-scripts/self-update.conf`，权限 `0600 root:root`，沿用现有安全配置加载风格并使用显式 allow-list。

建议键：

```bash
DEPLOY_SELF_UPDATE_URL="https://releases.example.invalid/deploy-scripts"
DEPLOY_SELF_UPDATE_CHANNEL="stable"
DEPLOY_SELF_UPDATE_REQUIRE_SIGNATURE="false"
DEPLOY_SELF_UPDATE_PUBLIC_KEY="/etc/deploy-scripts/update.pub"
DEPLOY_SELF_UPDATE_KEEP_RELEASES="3"
DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS="30"
```

命令行/环境变量仅可覆盖非安全降级配置。即使环境变量设置 `DEPLOY_SELF_UPDATE_REQUIRE_SIGNATURE=false`，当系统配置要求签名时也不得关闭签名校验。

## 11. 版本检查设计

### 11.1 版本来源

版本检查区分三类：

| 类型 | 当前版本 | 最新版本 | 比较方式 |
|---|---|---|---|
| GitHub 二进制发布 | `INSTALLED_VERSION` | `github_latest_release_tag` | semver/标签规范化比较。 |
| 专用发布逻辑 | 应用声明 | 应用专用函数 | 应用负责返回标准 JSON。 |
| Git 工作树/静态站点/不可比较应用 | config 或 commit | 无 | `unsupported` 或 `unknown`。 |

公共比较函数只处理确认可比较的版本；无法解析、预发布标签、日期版本等由应用明确声明策略。不能使用字符串字典序比较版本。

### 11.2 缓存与速率限制

远端版本检查可能触发 GitHub API 限流。缓存存储于：

```text
/var/lib/deploy-scripts/version-cache/<app-id>.json
```

格式包含 `checked_at`、`latest`、`source`、`result`、`expires_at`；默认 TTL 6 小时。规则：

- `status-all` 默认不联网，只展示缓存或 `unknown`；
- `check-update --refresh` 才允许对所有目标联网；
- `check-update` 无 `--refresh` 时只刷新过期缓存；
- 网络失败时保留最后一次成功缓存，但状态设为 `stale`，并保留错误摘要；
- 并行版本请求第一期不实现，避免突发 API 流量；
- 支持 `GITHUB_TOKEN` 时仅把它传给 curl，绝不输出、缓存或写入 operation record。

## 12. 兼容性与迁移

### 12.1 对现有调用的兼容

下列行为保持：

```bash
bash deploy.sh
bash deploy.sh list
bash deploy.sh newapi install
bash deploy.sh newapi update
bash deploy.sh newapi status
bash deploy.sh newapi status-json
bash install_newapi.sh update
bash dist/install_newapi.sh update
```

新增的公共状态函数不得改变现有 `do_status()` 的文本输出。`status-json` 只增加字段且保持已有字段及其类型。任何改变必须用现有 `tools/checks/config-status.sh` 与 dispatch 检查覆盖。

### 12.2 配置兼容

- 不迁移或改写已有 `/etc/<app>-deploy.conf`；
- operation state 和 version cache 为可删除的辅助信息，删除后不会损坏应用；
- 新的 `/etc/deploy-scripts/self-update.conf` 独立于应用配置；
- `/opt/deploy-scripts` 只在用户显式采用受管发布安装时创建；从仓库工作区运行不自动迁移。

### 12.3 dist 发布包

`dist/` 的单文件脚本仍面向“单应用复制到服务器”的场景。它们可以执行应用状态、操作记录和应用更新，但不应原地自替换。

当用户执行：

```bash
bash dist/deploy.sh self-update
```

系统应解释当前为 `standalone_dist` 模式，并提供明确但不自动执行的迁移说明：下载并验证完整发布包、安装到 `/opt/deploy-scripts`、建立稳定入口。可在后续版本提供 `self-install`；第一期不将迁移与更新混在一个动作中。

## 13. 安全与可靠性要求

1. 所有状态、缓存、配置和日志路径必须由固定根目录和受验证的 app ID 构造；app ID 仅来自注册表或严格验证后的 `--include` 参数。
2. 批量写操作与自更新必须使用不同的 lock file，并获取一个全局 manager lock；单应用已有 lock 不替代全局协调。
3. 不从 manifest 中 `source` shell 内容；manifest 只能被严格 JSON 解析器/字段提取器读取。
4. 不允许 manifest 下载 URL 使用 `file:`、`data:`、无 scheme 或包含凭据的 URL；默认只允许 `https:`。
5. 解压前与解压后都要防止路径穿越和符号链接攻击；临时目录必须由 `mktemp -d` 创建，权限 `0700`。
6. 不以 root 执行未校验的新脚本；更新前所有 shell 语法和清单校验完成后才激活。
7. 更新操作的日志和状态不得存储签名公钥以外的秘密；下载请求中的 Authorization header 绝不写日志。
8. `self-update` 需要 root，因为它写 `/opt`、`/etc`、`/var/lib` 和 `/usr/local/sbin`；只读 `--check` 可非 root 执行，但不写缓存，或写到用户临时目录。
9. 状态采集应尽量非 root 可用；无法读取 root-only 配置时返回 `permission_denied`/`unknown`，不得通过放宽配置权限解决。
10. 任何自动回滚都只切换框架版本，绝不回滚应用数据或应用版本。

## 14. 验证与测试策略

### 14.1 单元级 shell 测试

新增 `tools/checks/state.sh`、`operation.sh`、`self-update.sh`，至少覆盖：

- JSON 转义、JSON 格式可由 Python `json.loads` 验证；
- 基础配置存在/缺失/权限不安全时的 `install_state` 和 severity；
- systemd 模拟返回 active/inactive/failed 时的标准化；
- 多服务聚合；
- 未支持版本检查不误报已是最新；
- 缓存过期和网络失败时 `stale` 语义；
- `--json` stdout 仅包含合法 JSON；
- `--include`、`--exclude`、`--only-installed` 目标选择；
- 操作成功、错误退出、信号中断后的运行记录；
- 敏感值脱敏；
- 自更新 manifest 的非法项目名、非法 URL、错误哈希、空包、路径穿越归档、内部版本不一致；
- 更新成功的 `current`/`previous` 原子切换；
- 新版本 smoke check 失败的自动回滚；
- 回滚目标缺失/损坏时拒绝切换；
- checkout 和 standalone 模式拒绝写自更新。

### 14.2 集成级验证

在临时目录和函数 mock 环境执行，不能依赖真实 root/systemd/GitHub：

```bash
bash tools/verify.sh syntax
bash tools/verify.sh shellcheck
bash tools/verify.sh dispatch
bash tools/verify.sh guards
bash tools/verify.sh release
bash tools/verify.sh all
```

新增 target：

```bash
bash tools/verify.sh state
bash tools/verify.sh operation
bash tools/verify.sh self-update
```

`all` 必须覆盖它们；`check_target_groups_cover_all_checks` 继续保证没有遗漏的新 check 函数。

### 14.3 手工验收矩阵

| 场景 | 期望结果 |
|---|---|
| 仅安装一个二进制应用 | `status-all` 正确显示未安装和已安装应用，已安装应用带服务、健康、当前版本。 |
| 服务停止 | 状态显示 `stopped`，severity 至少为 `error`，`problems` 出现该项。 |
| 根权限配置被改为 0644 | `config.safe=false`，severity 为 `critical`，不得读取/显示敏感内容。 |
| GitHub API 不可达 | 已缓存版本显示 `stale`；无缓存显示 `check_failed/unknown`，不显示 up_to_date。 |
| 批量更新中一个应用失败 | 其余目标继续，最终汇总失败，历史记录完整。 |
| 下载的自更新归档哈希不匹配 | 不创建/激活 release，`current` 保持原值。 |
| 新 release 激活后 smoke check 失败 | `current` 恢复到旧 release，状态为 `rolled_back`。 |
| checkout 有未提交修改 | `self-update` 拒绝写入，清楚说明可用 `--check` 和受管安装方案。 |

## 15. 分阶段实施计划

### Phase 0：基础契约与框架准备

- 新增 `lib/version.sh`：严格版本规范化与比较；
- 新增 `lib/operation.sh`：运行 ID、状态落盘、日志目录、trap 链接；
- 增加 i18n 文案、退出码、路径常量和通用参数解析；
- 建立 state/operation/self-update 的验证骨架。

**完成标准**：不改变已有应用行为；`tools/verify.sh all` 通过。

### Phase 1：统一单应用 JSON 与状态总览（MVP）

- 新增 `lib/state.sh`，让 `do_status_json()` 复用公共收集器；
- 实现 `overview`、`status-all`、`--json`、`--short`、`problems`；
- 接入所有共享 binary-app 应用；
- 对特殊应用先提供最低限度的 config/service 状态，健康/备份可逐步补齐；
- 状态查询无网络默认，且全局状态可在无 GitHub 访问时工作。

**完成标准**：每个注册应用有合法 JSON，`status-all --json` 可被 Python 解析，任何单应用采集失败不阻止其他应用展示。

### Phase 2：操作记录和批量只读/备份能力

- 为通过中控和直接 wrapper 调用的写操作加外层 operation record；
- 实现 `history [app]`、`health-all`、`doctor-all`、`backup-all --dry-run`；
- 在 3 个代表性应用中试点细粒度步骤，确认 trap、锁和日志语义后再推广。

**完成标准**：成功、失败和中断均有去敏状态记录；批量操作汇总稳定且保留子应用错误。

### Phase 3：应用版本检查和 `update-all`

- 接入 binary-app 的 GitHub release 检查与缓存；
- 为特殊应用声明 `unsupported` 或实现专用版本适配器；
- 实现 `check-update`、`update-all`、确认与 `--dry-run`；
- 增加 API 限流、缓存过期和网络失败测试。

**完成标准**：`update-all` 只更新明确可更新的已安装应用，不能检查的应用不会被误更新。

### Phase 4：发布包、受管安装与自更新

- 扩展构建流程生成 release archive、外部 `manifest.json`、内部 `RELEASE.json`、校验值和可选签名；
- 实现 `self-version`、`self-update --check`、受管模式检测；
- 实现下载、校验、暂存、离线验证、激活、smoke check、回滚、版本保留；
- 发布受管安装迁移说明；首版保持 checkout/standalone 不写入。

**完成标准**：临时目录集成测试覆盖成功更新、坏包拒绝、激活后自动回滚和手动回滚；真实测试服务器完成一次稳定版本升级和回滚演练。

### Phase 5：增强（可选）

- 状态采集有限并发和超时细化；
- `--strict`、`--errors-only`、导出 Prometheus textfile；
- 定时 version check 与通知钩子；
- 签名校验默认开启；
- 受管安装的 `self-install` 助手；
- 可选 TUI，而非改变默认 CLI。

## 16. 需要在实现前确认的决策

以下决策不阻塞 Phase 1，但会影响 Phase 4 发布流程，应在开始自更新实现前冻结：

1. **发布托管位置**：使用 GitHub Releases、内部对象存储或独立 HTTPS 站点；必须有长期稳定的 manifest URL。
2. **签名方案**：首发是否强制 minisign；如果不强制，何时将 `REQUIRE_SIGNATURE` 默认设为 true。
3. **框架版本来源**：采用 Git tag（建议 `vX.Y.Z`）还是从构建元数据生成；建议要求每个稳定发布具有不可变 tag。
4. **受管安装路径**：是否固定 `/opt/deploy-scripts`；建议固定，降低文档和回滚复杂性。
5. **日志保留策略**：默认 30 天/20 文件是否满足运维需求；建议通过配置可调，且不得无限增长。
6. **是否在第一期将 `status-all` 默认做本地健康探测**：建议是；探测只访问 loopback、单项 5 秒超时，并可用 `--no-probe` 关闭。

## 17. 验收清单

实现完成后，以下项目必须全部满足：

- [ ] 所有 `lib/app_registry.sh` 中注册的应用可被 `status-all --json` 枚举，且每项是合法 JSON。
- [ ] 新状态模型清晰区分未安装、已安装、服务停止、健康失败、配置不安全和版本未知。
- [ ] 现有单应用 `status` 文本输出未被破坏；现有 `status-json` 的既有字段兼容。
- [ ] 状态总览不会因某一应用 definition/impl 加载失败而整体失败。
- [ ] 应用更新与中控更新在命令、日志、状态记录和文档中完全分离。
- [ ] 批量写操作默认仅操作已安装应用、默认串行、默认继续其他应用，并有清晰汇总。
- [ ] 自更新不会在 Git checkout 或 standalone dist 文件上原地覆盖用户文件。
- [ ] 受管自更新在激活前完成 manifest、归档、路径、版本和 shell 语法验证。
- [ ] 自更新失败时 `current` 仍指向原完整版本；激活后验证失败时自动回滚。
- [ ] 操作记录与日志不会泄露密钥、令牌、密码或完整私密配置。
- [ ] 所有新增检查注册到 `tools/verify.sh all`，并在更新 `dist/` 后通过完整验证。

## 18. 推荐的首个可交付范围

为了尽快提供用户可见价值，首个 PR 应只包含 Phase 1 的最小闭环：

```bash
sudo bash deploy.sh overview
sudo bash deploy.sh status-all
sudo bash deploy.sh status-all --json
sudo bash deploy.sh status-all --short
sudo bash deploy.sh problems
```

它应包含：基础安装/服务/配置/版本记录状态、binary-app 健康适配、统一表格、稳定 JSON、单应用故障隔离和完整 verify 覆盖。

在这个基础稳定后，再加入操作记录、批量更新和发布包式自更新。这样可以避免把状态模型、批量写操作和框架升级三个高风险改变混在同一个发布中。
