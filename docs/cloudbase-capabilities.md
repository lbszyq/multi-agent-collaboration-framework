# CloudBase（腾讯云开发）部署映射

> 本文件 = 框架在 **DSH 宿主 + CloudBase（腾讯云开发）**下的部署/BaaS 能力映射（**可选能力**，非 CloudBase 部署的项目忽略本文档）。
> 定位：把框架的部署角色（R06）、数据角色（R02/R05）、AI 角色（R09）与 Layer 4 生产验收证据，映射到 DSH 的 CloudBase MCP 工具。
> 与 `docs/dsh-capabilities.md`（编排能力）、`docs/codex-capabilities.md`（Codex 编排）并列，三者覆盖「编排 / 部署 / 数据」三个宿主维度。

---

## 一、角色 → CloudBase 工具映射

| 角色 | 职责 | CloudBase 工具 | 说明 |
|------|------|---------------|------|
| R06 DevOps | 部署 / 上线 | `manageApps`（首选，部署到独立子域名）/ `manageHosting`（静态托管，老项目）/ `manageCloudRun`（云托管服务）/ `manageFunctions`（云函数） | 新 Web 项目首选 `manageApps`；已有静态托管历史用 `manageHosting`；需自定义后端 / 长连接用 `manageCloudRun` 或 `manageFunctions` |
| R02 后端 | 数据层 | `managePgDatabase`/`queryPgDatabase`（PG + `app.rdb()` + RLS）或 `writeNoSqlDatabaseContent`/`readNoSqlDatabaseContent`（NoSQL 文档库） | 新环境默认 PG（先 `envQuery(action=info)` 看 `RuntimeBackends`）；已存在的 NoSQL 集合继续用 NoSQL 工具 |
| R05 数据 | 数据模型 / 迁移 | 同 R02（PG 迁移走 `managePgDatabase(action=applyMigration)`） | R05 未激活时职责合并到 R02（见 `roles/R05-数据工程师.md`） |
| R09 AI | AI 模块 | `ai-model-*`（通过 `searchKnowledgeBase(mode=skill)` 读取，见角色文件 Skill 绑定） | 文本/流式走 `generateText`/`streamText`；`ai.createModel` + 模型 ID |
| PM / 全员 | 认证 / 权限 / 存储 | `manageAppAuth`/`queryAppAuth`（登录方式）、`managePermissions`（资源权限/RLS）、`manageStorage`/`queryPgStorage`（存储桶） | 前端登录先 `manageAppAuth` 配 provider + publishable key；上传前确认目标 pgstore 桶存在 |

## 二、Layer 4 生产验收证据的 CloudBase 原语

> 对应 `docs/质量验收标准.md` §1.2「证据责任矩阵」中 P2（后端部署）/ P3（第三方服务就绪）/ P9（错误监控）/ P10（日志采集）等【外部证据】项，CloudBase 部署下用以下原语代替泛化的「公网 URL / CI 链接」：

| 验收项 | CloudBase 证据形式 |
|--------|-------------------|
| P2 后端已部署 | 静态托管域名（`*.tcloudbaseapp.com` / `*.webapps.tcloudbase.com`）可访问 + `queryHosting`/`queryApps` 返回状态 |
| P3 第三方服务就绪 | `envQuery(action=info, envId=...)` 返回的环境状态 + 认证/数据库/存储已开通 |
| P9 / P10 监控日志 | `queryLogs(action=searchLogs)`（CLS 跨服务日志）+ 云函数日志（`queryFunctions(action=listFunctionLogs)`） |
| 环境 / 凭证 | `envId`、云函数名、publishable key（`queryAppAuth` 获取，勿写明文密钥） |

## 三、安全红线（CloudBase 特化）

- 明文密钥 / token 仍禁写入任何项目文件（沿用 `AGENTS.md` 通用安全红线）；CloudBase 的 publishable key 可在前端用，但 **SecretKey / API Key 一律经环境变量或密钥管理注入**，勿提交。
- 数据库权限：PG 用 RLS（`managePgDatabase(action=execute)` 跑 `CREATE POLICY`），NoSQL 用 `managePermissions(resourceType="noSqlDatabase")` 安全规则——不要在客户端暴露管理端密钥。

## 四、与现有文档的关系

- 编排能力（唤起/注入/等待/关闭）：`docs/dsh-capabilities.md`
- 部署 / 数据 / AI 的 CloudBase 落地：本文档
- 质量验收证据责任矩阵：`docs/质量验收标准.md` §1.2
- 技术选型（前端组件库 / 后端框架）：`docs/architecture.md` §5（CloudBase 是部署/BaaS 层，不替代业务技术选型）

## 变更记录

| 日期 | 变更内容 | 变更人 |
|------|---------|--------|
| 2026-01-28 | 初版：CloudBase 部署/数据/AI/证据映射 | R99 |
