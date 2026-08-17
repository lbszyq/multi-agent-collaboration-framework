# DSH（DeepSeek Harness）协作能力

> 本文档 = 本框架在 **DeepSeek Harness（DSH）宿主**下自动化编排的**唯一权威**（Codex 宿主见 `docs/codex-capabilities.md`）。
> **状态**：已实测可用（v1.0）。DSH 提供可靠的子代理能力与原生 PowerShell（pwsh），**自动化模式可启用**——在 DSH 下不再默认退回手工模式。
> 实测基线：pwsh 7.6.4 / git 2.45.1 / `scripts/patrol.ps1` 退出码 0 且 `[结果] PASS`。

---

## 一、核心结论（与 Codex 的差异）

| 维度 | Codex（原宿主） | DSH（当前宿主） |
|------|----------------|----------------|
| 子代理唤起 | `spawn_agent` 三档 `fork_turns` 均不干净，需两步派发 | `subagent` 接收**完整独立 prompt**，一步派发 |
| 上下文隔离 | `fork_turns=none` 会连 message 一起清掉 | `subagent` 天然「隔离历史 + prompt 成第一条」的干净组合 |
| 消息注入 | `followup_task`/`send_input` 不稳定 | `send_message`（对 subagentId 续聊）稳定 |
| 关闭/复用 | 无 `close_agent`/`resume_agent` 接口 | `interrupt_agent` 中断当前 turn；subagentId 会话内持久、`send_message` 可续 |
| 等待完成 | `wait_agent` | 后台 subagent 落定**自动通知** + `list_agents`（无需轮询 `reports/`，`patrol.ps1` 仅定位回报） |
| 脚本执行 | 依赖宿主提供 shell | `pwsh` 原生，`scripts/` 全部可用 |
| 人类决策节点 | 用户手工转述 | `ask_user_question` |
| 编排层 | 仓库不含编排实现（依赖宿主） | `pwsh`+`subagent`/`send_message` 顺序编排、`workflow` 并行派发（见 `docs/dsh-pm-driver.md`；`run_code` 当前宿主不可用，已废弃） |

---

## 二、宿主工具映射表（5 语义动作 → DSH 工具）

> 语义抽象（唤起/注入/等待/关闭/复用）与 `docs/codex-capabilities.md` 一致；下表给出 DSH 实际工具名。

| 能力 | DSH 工具 | 说明 | PM 何时使用 |
|------|---------|------|------------|
| 唤起子代理 | `subagent`（fresh 独立 prompt）/ `subagent_fork`（继承对话） | 创建独立上下文的角色子代理，`run_in_background: true` 返回持久 id | 开局拉起角色；有任务需要新角色时 |
| 消息注入 | `send_message` | 向已存在的 subagentId 注入任务卡/驳回指令，成为其下一轮 turn | 派卡、验收驳回、中途改派 |
| 等待完成 | 后台 subagent 落定自动通知 + `list_agents` | 后台 subagent 落定时运行时**主动通知父线程**（含最终消息），PM 无需轮询 `reports/`；`patrol.ps1` 仅用于定位回报文件实际位置 | 派卡后等落定通知，触发验收闭环 |
| 关闭子代理 | （常驻，不关闭） | 子代理唤起后常驻、不主动关闭；`interrupt_agent` 仅用于中断当前 turn | 仅父 agent 重启时失效 |
| 复用子代理 | `send_message` | 对 `idle` 常驻子代理继续发任务（后续所有卡直接续派） | 常驻模型默认 |

### 术语速查（Codex 工具名 → 语义动作 → DSH 工具名）

> 阅读 `PM-操作指南.md` / `docs/自动化协作协议.md` / `roles/*.md` 时若遇到 Codex 工具名，按下表映射到 DSH。这些通用文档用「语义动作」描述编排，宿主工具名仅在本文件与 `docs/codex-capabilities.md` 落地，**勿按字面名调用**。

| 语义动作 | Codex 工具名 | DSH 工具名 |
|---------|-------------|-----------|
| 唤起子代理 | `spawn_agent`（`collaboration__spawn_agent`） | `subagent`（fresh prompt）/ `subagent_fork`（继承对话） |
| 注入消息 | `followup_task` / `send_input` | `send_message`（对 subagentId 续聊） |
| 等待完成 | `wait_agent` | 后台 subagent 落定自动通知 + `list_agents` |
| 关闭子代理 | `close_agent` | `interrupt_agent`（中断当前 turn，无显式销毁） |
| 复用子代理（常驻） | 不关闭 + `send_input`/`followup_task` 续卡 | `send_message`（对 ready/idle 续起） |
| 编排实现 | （仓库不含编排代码） | 按序执行（pwsh+subagent，见 `docs/dsh-pm-driver.md` 二）/ `workflow`（并行派发，见 三） |

> **agent id 生命周期**：DSH 的 subagentId 在**同一会话内持久**（`list_agents` 可见 running/idle/ready；ready = 仅存于存储、可 `send_message` 续起）。会话整体重启后需重新 `subagent` 并让角色从 docs 恢复认知（与 `PM-操作指南.md` §五「先落盘再重启、已落盘 100% 可恢复」一致）。

---

## 三、一步派发协议（DSH，替代 Codex 两步派发）

> Codex 的两步派发（`spawn_agent(fork_turns="none")` 空消息 + `followup_task` 注入）是「spawn 会清掉 message」的 workaround。DSH 的 `subagent` 接收完整独立 prompt，**一步完成**：

```
tools.subagent({
  description: "R02-后端工程师",
  run_in_background: true,
  prompt: `
你是本项目的 [R02]-[后端工程师]。
<—— 此处粘贴 roles/templates/worker-init.md 的「注入模板」——>

你的任务卡是 TC-001，完整内容如下：
<—— 此处粘贴 task-cards/TC-001-*.md 完整内容——>
`
})
```

> `description` 固定为 `R0X-岗位名`（如 `R02-后端工程师`），不带任务简述；运行时身份以 `agent id` 为准。同一角色临时并行实例可用 `R02-后端工程师#TC-XXX` 作为人类可读标签（规则见 `roles/README.md`「常驻与并行实例规则」），但常驻实例命名仍固定为 `R0X-岗位名`。

- 身份识别：`subagent` 无历史上下文，prompt 即第一条消息，天然满足 AGENTS.md「最新身份声明优先」。
- **执行者禁编排**：prompt 末尾必须带 AGENTS.md 硬约束——角色禁止 `subagent`/`subagent_fork`/`workflow`/`send_message`（向他人派发）等编排动作，只做任务卡范围内的事。
- 回报落盘：位置规则见 `reports/README.md`；PM 通过 `pwsh` 跑 `patrol.ps1` 枚举 worktree 定位回报。

---

## 四、DSH 独有能力（Codex 时代没有）

| DSH 工具 | 对应框架机制 | 落地方式 |
|---------|-------------|---------|
| `ask_user_question` | 人类决策节点（`PM-操作指南.md` §八：角色组合确认/原型确认/产品验收/变更代价确认） | PM 在「必须确认」节点调用，选项带推荐项 |
| `workflow` | 并行派发（`docs/自动化协作协议.md` §3.6） | 多卡无耦合时 fan-out 到多个角色，分阶段编排 |
| `goal`（create_goal/update_goal） | 长期项目目标（从初始化到验收） | PM 跨多轮自主延续，落盘后可持续 |
| `pwsh` | `scripts/` 全套工具链 | 建卡/建 worktree/校验/巡检/状态/合并/密钥扫描全部原生执行 |

> **`goal` 的 PM 用法**（DSH 独有）：PM 在初始化时用 `create_goal` 建一个长期目标（「多 Agent 协作：{项目}」），把项目推进作为跨 goal 轮的自主延续目标；每完成一批任务卡/阶段用 `update_goal` 更新进度，需要用户拍板的节点可暂停/恢复。这补上了框架「PM 上下文长 → 重启」的痛点——goal 让 PM 在**单个会话内**跨多轮自主延续，而 SSOT（docs/task-cards/reports）保证会话重启后仍 100% 可恢复。注意：goal 是会话内持久化，会话重启后仍按 `PM-操作指南.md` §5 从 SSOT 恢复。

> **CloudBase 部署映射**：DSH 还内置 CloudBase（腾讯云开发）MCP 工具（静态托管/云函数/云托管/PG/NoSQL/存储/认证）。框架的部署（R06）、数据（R02/R05）、AI（R09）与 Layer 4 生产验收证据的 CloudBase 落地见 `docs/cloudbase-capabilities.md`（可选能力，非 CloudBase 部署的项目忽略）。

---

## 五、常驻模型（DSH 语义）

> 唤起后常驻，不关闭。PM 用 `subagent` 唤起角色（命名固定 `R0X-岗位名`），后续该角色的所有卡用 `send_message` 续派。子代理生命周期 = 父会话生命周期；父 agent 重启后 subagentId 失效，重新唤起并让角色从 docs 恢复认知。上下文过长时由用户直接重启父 agent（先落盘再重启）。

### 常驻精简上下文协议（DSH 默认建认知路径）

> 目的：DSH 下每个角色默认 = 一个常驻 subagent，上下文完全隔离——全量读 docs 的 token 成本 × 角色数 × 卡数会随项目膨胀。因此 **DSH 默认「首次/重启全量建认知一次，之后每张新卡只精简建认知」**（AGENTS.md 第三步 B 路径）。精简只缩短「建认知」路径，不降低「执行」质量：任务卡即合约、回报格式、契约偏离、SSOT 优先级等硬约束不变。

**首次唤起 / 会话重启后恢复（全量，每会话一次）**：
1. 必读：`docs/context-brief.md`（< 200 tokens 速览）→ `docs/project-status.md` → `docs/architecture.md` → `docs/decisions.md` → `docs/自动化协作协议.md`（协作流程细节）
2. 特殊场景：新项目首次初始化先读 `docs/初始化清单.md`；存量项目先读 `docs/存量项目接入清单.md`

**常驻续卡（默认，每张新卡）**：
1. 必读：`docs/context-brief.md` + `docs/project-status.md` + `docs/thread-routing.md`（角色状态节）+ 当前任务卡
2. 按需精读：仅当任务卡「约束与契约」引用时才读 `docs/architecture.md` / `docs/contracts/` / `docs/prd.md` / `docs/质量验收标准.md` 相关章节
3. 保持常驻：状态标 `idle`（`docs/thread-routing.md`），PM 用 `send_message` 注入下一张卡，不关闭

> 与 Codex 宿主「常驻上下文协议」（`docs/codex-capabilities.md`）语义一致；DSH 下为本框架默认路径。

---

## 六、环境依赖与边界

| 依赖项 | DSH 实测 | 缺失时后果 |
|--------|---------|-----------|
| pwsh ≥ 7 | ✅ 7.6.4 | `scripts/` 无法解析（Windows PowerShell 5.1 会乱码/失败） |
| git + worktree | ✅ 2.45.1 | 代码类任务无法物理隔离 |
| 子代理唤起/注入/等待 | ✅ `subagent`/`send_message`/`list_agents` | 退回手工模式 |
| 文件沙箱写权限 | ⚠️ `new-worktree.ps1` 会在仓库外建 `<仓库根>-TCXXX` 兄弟目录 | 若沙箱收紧，需把 worktree 放进允许区或显式放行 |
| 子代理并发上限 | ⚠️ 个位数级 | 超限分批派发或退回手工模式 |
| 会话持久性 | ⚠️ subagentId 会话内持久，跨会话失效 | 重启后重新 `subagent`，角色从 docs 恢复 |

---

## 七、落地清单（DSH 自动化模式启用）

1. `docs/dsh-pm-driver.md`：pwsh/subagent/workflow 编排驱动参考实现（`run_code` 当前宿主不可用，已废弃）。
2. `roles/templates/worker-init.md`：已收敛为单一「注入模板」+「使用说明」（DSH 一步派发 / 常驻续卡 / 手工 fallback）。
3. `AGENTS.md`：执行者禁编排已补 DSH 工具名；第三步改为两段式（A 全量/首次重启，B 常驻精简/DSH 默认）。
4. `docs/自动化协作协议.md`：环境依赖已标注 DSH 可用，编排正文以 DSH 工具名为主体。
5. 本文档：新增「常驻精简上下文协议」（DSH 默认建认知路径）。
6. 其余（SSOT/任务卡/回报/质量四层/变更管理/ADR/复盘）**两种宿主完全一致，零改造**。

---

## 变更记录

| 日期 | 变更内容 | 变更人 |
|------|---------|--------|
| 2026-01-28 | 初版：DSH 宿主映射 + 一步派发协议 | R99 |
| 2026-08-16 | v1.1：run_code 驱动废弃说明（以 dsh-pm-driver.md v2 为准）；新增「常驻精简上下文协议」（DSH 默认建认知路径）；落地清单同步 | R99 |
