# scripts/ 框架工具集

> 将 PM 的人工核验（建卡、校验、巡检、状态同步、合并）脚本化。PowerShell 7（pwsh）下运行，脚本为 UTF-8 编码。
> 适用于框架自身及其复制到各项目后的日常维护。
> **状态唯一权威**：任务卡/回报文件头 YAML front-matter（机器可读）；markdown 正文保持人类可读，脚本不解析正文状态。

---

## 脚本清单

| 脚本 | 用途 | 用法 |
|------|------|------|
| `framework-lib.ps1` | 共享函数库（front-matter 解析/更新），被其他脚本 dot-source | — |
| `new-task-card.ps1` | 从模板生成任务卡（含 front-matter），生成后自动校验 | `.\scripts\new-task-card.ps1 -Number 006 -Summary "示例模块" -Role "R02-后端工程师"` |
| `new-worktree.ps1` | 为任务卡创建独立 Worktree（`git worktree add`），自动回填任务卡 front-matter（workdir/base_branch/base_commit） | `.\scripts\new-worktree.ps1 -Number 006 -Summary "user-module"` |
| `validate-task-card.ps1` | 校验任务卡 front-matter：必填字段/章节/验收标准条数/F3+F4 关键词提示/worktree 要求 | `.\scripts\validate-task-card.ps1 -Path task-cards\TC-001-xxx.md` |
| `validate-report.ps1` | 校验回报 front-matter：必填字段/章节/验收标准全勾/状态与工作区一致性 | `.\scripts\validate-report.ps1 -Path reports\TC-001-回报.md` |
| `patrol.ps1` | PM 巡检：任务卡状态 + 回报 + 未合并分支 + Worktree + 交叉检查 | `.\scripts\patrol.ps1` |
| `generate-status.ps1` | 状态摘要生成器：扫描任务卡 front-matter，自动更新 `docs/project-status.md` 与 `docs/thread-routing.md` 的自动生成区（勿手改） | `.\scripts\generate-status.ps1`（`-DryRun` 预览） |
| `generate-metrics.ps1` | 复盘度量采集器（只读）：解析 `reports/` 全部完工回报的 §9 度量/§5 Bug 分布/§6 契约偏离/§1 状态向量，输出复盘输入表与估算偏差率（供 `docs/retrospectives/` 使用） | `.\scripts\generate-metrics.ps1` |
| `merge-card.ps1` | PM 验收通过后执行合并：校验 accepted → 检查工作区 → `git merge --no-ff` → 标记 merged | `.\scripts\merge-card.ps1 -Card TC-001` |
| `scan-secrets.ps1` | 密钥/凭据扫描：高置信模式 FAIL（安全红线）、低置信 WARN；patrol.ps1 自动调用 | `.\scripts\scan-secrets.ps1` |
| `validate-framework.ps1` | 框架一致性检查：模板 front-matter ↔ `framework-lib.ps1` 常量表 ↔ 脚本字段引用 ↔ 文档相对路径引用四方位校验 | `.\scripts\validate-framework.ps1` |
| `tests/framework-selftest.ps1` | 框架关键逻辑自测（零依赖自断言）：front-matter 解析/更新、worktree 判定、F3/F4 关键词、字段契约、H1 引用失效负样例、集成退出码 | `.\scripts\tests\framework-selftest.ps1` |

---

## 校验规则说明

### front-matter（任务卡与回报）

任务卡/回报文件第一行 `---`、末行 `---` 之间为 YAML 简单标量（`key: value`），是状态与 Git 定位信息的**唯一权威**。脚本只解析 front-matter，不解析正文表格。字段清单见 `task-cards/template.md` 与 `reports/template.md`。

### validate-task-card

- **FAIL**：缺少 front-matter 必填字段（id/status/created/assigned_role/priority/depends_on/workdir/base_branch/base_commit/target_branch）、状态非法、缺少必填章节、验收标准为空
- **FAIL**：`workdir` 为「主工作区」但未填写 `workdir_note`（仅纯文档/纯配置卡可用主工作区）；状态非 todo 时 `workdir`/`base_commit` 未填写
- **FAIL**：`parallel_with` 非空但 `workdir` 为主工作区（并行卡必须 worktree）
- **WARN**：验收标准未命中边界条件（F3）或异常处理（F4）关键词——仅提示，不阻断派发；语义完整性依赖 R03 验收标准评审（第二道防线）；`light: true` 卡与纯文档/配置卡（`workdir=主工作区` 且 `workdir_note`）自动跳过提示

### validate-report

- **FAIL**：文件名不合规、front-matter 缺必填字段（task_id/role/time/status/repo_root/workdir_type/base_commit/branch/head_commit/workspace_status）、`workdir_type=worktree` 但缺 `worktree` 路径
- **FAIL**：状态为 `done` 但验收标准未全勾；`workspace_status=dirty` 但状态为 `done`（应为 partial/blocked）
- 外部证据清单（§4.2）支持「待外部提供」状态：用户·PM 责任项（P2/P3/P9/P10）声明待外部提供时不判空（对应 `docs/质量验收标准.md` §1.2）
- `light: true` 回报（轻量通道）：只要求 §1 总体状态 + §3 文件变更清单，其余章节允许缺失或「不适用」（见 `docs/轻量任务通道.md`）

### patrol

- 无 `develop` 分支或非 Git 仓库时自动跳过 Git 检查，不报错
- 交叉检查：有回报但任务卡状态未更新为 `done`/`accepted`/`merged` 时会列出
- Worktree 隔离交叉检查：所有任务卡 `workdir` 必须为独立 worktree 路径（主工作区仅限纯文档卡与 `light: true` 轻量卡）；并行组内多卡共用同一工作目录 → FAIL
- 并行组文件级重叠检查：并行卡须在 front-matter 声明 `touched_files`（逗号分隔，以 `code/` 为根，见 `task-cards/template.md`）；缺失或同组卡修改范围重叠 → FAIL（`docs/自动化协作协议.md` §3.6）
- 复盘触发：累计归档任务卡自上次复盘（`docs/retrospectives/README.md` 索引末列「复盘时已归档数」为基线，缺省 0）新增 ≥10 张 → 行动清单提示复盘
- 行动清单提示运行 `generate-status.ps1` 同步自动生成区

### generate-status

- 扫描 `task-cards/*.md`（不含 archive）front-matter，按 status 分组：进行中（todo/in_progress/partial/blocked/done/accepted）与已完成（merged）
- 更新 `docs/project-status.md`「进行中的任务卡」「已完成的任务卡」与 `docs/thread-routing.md`「当前任务卡索引」的 `<!-- BEGIN AUTO-GENERATED -->` 区
- 自动生成区勿手改；`-DryRun` 仅预览不写文件

### merge-card

- 前置条件：任务卡状态为 `accepted`；feature worktree 工作区干净；存在检出 `target_branch` 的 worktree
- 合并后自动更新任务卡 front-matter（status=merged、completed=今天）并 commit 到目标分支；不 push、不自动解决冲突

---

## CI 自动检查（.github/workflows/framework-check.yml）

> 框架随附 GitHub Actions 工作流：push（main/develop）与 PR 时自动运行 `validate-framework.ps1`（模板↔常量表↔脚本↔文档引用四方位一致性）、`patrol.ps1`（巡检，含密钥扫描）与 `scripts/tests/framework-selftest.ps1`（框架自测）。新项目若使用 GitHub Actions 无需额外配置；不使用或本地仓库时，等效检查为手动运行上述三个脚本。

---
## 使用提示

- 若 PowerShell 执行策略阻止运行，用：`powershell -ExecutionPolicy Bypass -File scripts\patrol.ps1`
- 脚本只读不写（`new-task-card.ps1`、`new-worktree.ps1`、`generate-status.ps1`、`merge-card.ps1` 除外——前两者新建文件/执行 `git worktree add`，后两者更新状态摘要/任务卡状态），可放心用于验收前置检查

## 变更记录

| 日期 | 变更内容 | 变更人 |
|------|---------|--------|
| — | — | — |
