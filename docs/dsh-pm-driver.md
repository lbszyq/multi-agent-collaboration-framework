# DSH PM 编排驱动（参考实现）

> 本文件 = DSH 宿主下 PM 自动化编排的**实际可用驱动**。把「建卡→建 Worktree→唤起子代理→派发→等待→验收→合并→归档」串成可重复执行的闭环。
> **工具前提（与当前宿主实测一致）**：DSH 提供 `pwsh`（原生 PowerShell，跑 `scripts/` 全套）、`subagent`/`send_message`/`list_agents`/`interrupt_agent`（子代理编排）、`workflow`（多卡并行 fan-out）、`ask_user_question`（人类决策节点）、`read`/`write`/`edit`（文件工具）。**`run_code` 在当前宿主不可用**——旧版 run_code 驱动已废弃，若仓库历史中存在 `tools.*` 调用示例，以本文为准并删除。
> 脚本层（建卡/校验/巡检/合并）复用 `scripts/` 的 pwsh 工具链，不改脚本本身。
> 前置：项目已按 `docs/初始化清单.md` 完成 Git 基线（主工作区检出 develop）。

---

## 一、驱动全景

```text
phase0 巡检       → pwsh：patrol.ps1（读状态，FAIL=先处理）
phase1 建卡+建WT → pwsh：new-task-card.ps1 + new-worktree.ps1 + git commit
phase2 派发       → subagent（完整 prompt = worker-init 注入模板 + 任务卡）；常驻续卡用 send_message
phase3 等待       → 后台 subagent 落定自动通知 + list_agents 确认（patrol.ps1 定位回报）
phase4 验收       → pwsh：validate-report.ps1 + 读回报 + 四层质量核查（LLM 判断）
phase5 合并归档   → pwsh：merge-card.ps1 + generate-status.ps1 + 移动 archive + git commit
phaseH 人类决策   → ask_user_question（角色组合/原型/验收/变更代价）
```

---

## 二、按 phase 的可执行操作序列（PM 直接照做）

> 以下每个 phase 给出 PM 在当前 DSH 会话中的**确切操作**：`pwsh` 表示调用 pwsh 工具（workdir = 仓库根），`subagent`/`send_message`/`list_agents`/`ask_user_question` 表示调用同名工具。

### phase0：巡检

```
pwsh: . '.\\scripts\\patrol.ps1'
```

判断：输出含 `[结果] PASS` 且退出码 0 才继续；有 `[FAIL]` 先处理再派发。

### phase1：建卡 + 建 Worktree + 提交任务卡

```
pwsh: . '.\\scripts\\new-task-card.ps1' -Number 001 -Summary "用户认证模块" -Role "R02-后端工程师"
pwsh: . '.\\scripts\\new-worktree.ps1' -Number 001 -Summary "user-auth"
pwsh: git -C <仓库根> add task-cards
pwsh: git -C <仓库根> commit -m "chore(TC-001): add task card"
```

> 落盘硬约束：任务卡未 commit 到 `develop` 前，`new-worktree.ps1` 会拒绝创建（P0 前置校验），合并闭环依赖该提交。

### phase2：派发

**新角色（一步派发）**：调用 `subagent`，参数：
- `description`：`R02-后端工程师`（固定 `R0X-岗位名`，不带任务简述）
- `run_in_background`：true
- `prompt`：按 `roles/templates/worker-init.md` 的「注入模板」组装 = 身份声明 + 认知模式 + 任务卡完整内容 + 禁编排约束（禁止 `subagent`/`subagent_fork`/`workflow`/`send_message` 等编排动作）

**常驻角色续卡**：调用 `send_message`，目标 = 该角色 subagentId（`list_agents` 查询），消息 = 「你是 R0X-岗位名，执行任务卡 TC-XXX」+ 任务卡完整内容。

**同一角色临时并行实例**：额外实例同样用 `subagent` 拉起，`description` 用 `R0X-岗位名#TC-XXX`，并在 `thread-routing.md` 登记为“临时并行实例”；验收合并后回收，常驻实例保持唯一。

**派发后落盘硬约束（未完成 = 不算派发完成）**：
1. `pwsh: . '.\\scripts\\generate-status.ps1'` —— 自动同步 `docs/project-status.md`、`docs/thread-routing.md` 自动生成区与 `docs/context-brief.md`「当前活跃任务」；
2. 在 `docs/thread-routing.md` 活跃对话表登记该角色状态 `working`（运行时句柄用 `list_agents` 查询，不持久化）。

### phase3：等待

- 后台 `subagent` 落定时**运行时自动通知父线程**，PM 收到落定通知后触发验收；无需轮询 `reports/`。
- 确认：`list_agents`（scope=children）查看角色状态；`pwsh` 跑 `patrol.ps1` 定位回报文件实际位置（代码类卡回报在任务卡 Worktree 内）。
- 超时未回报：`send_message` 向角色发提醒。

### phase4：验收

**大卡先独立审阅（`docs/自动化协作协议.md` §3.4，默认）**：用 `subagent` 拉起**新鲜上下文**的审阅子代理（不参与产出、不带 PM 信任惯性），prompt 注入：回报实际路径（先 `patrol.ps1` 定位）+ 任务卡验收标准 + `docs/质量验收标准.md` 四层模型与 §1.2 证据责任矩阵 + 相关契约引用（可按需注入 `code-review` / `verification-before-completion` skill 引用）；要求跑 `validate-report.ps1`、读回报与相关代码、逐条核查验收标准与外部证据，输出「通过 / 不通过（问题清单）」。结论是 PM 仲裁的**输入**，不自动否决。小卡 / light 卡豁免。

```
pwsh: . '.\\scripts\\validate-report.ps1' -Path <实际路径>\\TC-XXX-回报.md
read: <实际路径>\\reports\\TC-XXX-回报.md   （用 patrol 定位的 Worktree 内路径）
```

随后对照 `docs/质量验收标准.md` 四层模型逐条核查（模型判断，不自动放行）；契约偏离评估、决策记录、驳回指令均按 `docs/自动化协作协议.md` §3.4 执行。

### phase5：合并 + 归档 + 状态同步

```
pwsh: . '.\\scripts\\merge-card.ps1' -Card TC-001 [-TestCommand "<冒烟命令>"]
pwsh: . '.\\scripts\\generate-status.ps1'
pwsh: $f = Get-ChildItem -Path 'task-cards/TC-001-*.md' | Select-Object -First 1; git -C <仓库根> mv $f.Name task-cards/archive/
pwsh: git -C <仓库根> commit -m "chore(TC-001): archive merged card"
```

### phaseH：人类决策节点

调用 `ask_user_question`（questions 数组，每项 id/question/options，推荐项放首位）——仅用于「做什么 / 花多少钱 / 什么时候好」类节点（角色组合确认、原型确认、产品验收、变更代价确认），判定规则见 `PM-操作指南.md` §八。

---

## 三、workflow 并行派发（多卡无耦合时）

> 定位：`docs/自动化协作协议.md` §3.6 并行派发的 DSH 原生实现。**workflow 脚本只能协调子代理**（无文件系统/网络/定时器访问），因此建卡、建 worktree、验收、合并等文件与 git 操作由 PM 在 workflow 外部完成；脚本内的 `agent()` 子代理拥有完整工具，可自行读 docs、写代码、写回报。

**meta**（workflow 工具参数）：

```json
{
  "name": "pm-parallel-dispatch",
  "description": "并行派发多张互不耦合任务卡给角色子代理并汇总结果",
  "phases": [{ "title": "并行执行", "detail": "各角色独立执行任务卡" }]
}
```

**args**：

```json
{
  "cards": [
    {
      "no": "TC-001",
      "label": "R02-后端工程师",
      "prompt": "<身份声明 + 认知路径 + 任务卡完整内容 + 禁编排约束>"
    }
  ]
}
```

**script**（放入 workflow 工具的 script 参数）：

```js
// 并行派发：每张卡一个独立 agent，全部落定后汇总（失败 agent 返回 null，标记为失败）
const results = await parallel(
  args.cards.map((c) => () =>
    agent(c.prompt, {
      label: c.no + "-" + c.label,
      schema: {
        type: "object",
        properties: {
          ok: { type: "boolean" },
          head_commit: { type: "string" },
          report_path: { type: "string" },
          summary: { type: "string" }
        },
        required: ["ok", "summary"]
      }
    })
  )
);
return {
  cards: args.cards.map((c, i) => ({
    no: c.no,
    label: c.label,
    result: results[i] || { ok: false, summary: "agent 执行失败（null）" }
  }))
};
```

> 约束：并发数受宿主子代理上限约束（个位数），超过上限时分批（`parallel` 分组多次跑）或退回串行；落定后 PM 逐个 `patrol` + 验收 + `merge-card`（有依赖顺序时按依赖合并，冲突按 `docs/git-workflow.md` §五处理）。

---

## 四、与 scripts/ 的分工

| 层 | 谁 | 工具 | 说明 |
|----|----|------|------|
| 脚本层（账本） | scripts/*.ps1 | pwsh | 建卡/建 WT/校验/巡检/状态/合并/密钥扫描——零改造直接复用 |
| 编排层（拉起/注入/监听） | 本驱动 | subagent / send_message / list_agents / workflow | 框架一直缺的一层，DSH 落地 |
| 决策层（人类拍板） | PM + 用户 | ask_user_question | 只问「做什么/花多少钱/什么时候好」 |

---

## 五、注意事项

1. worktree 兄弟目录：new-worktree.ps1 在仓库外建 `<仓库根>-TCXXX`，需确认沙箱写权限（当前 danger-full-access 无碍；沙箱收紧时需显式放行，见 `docs/dsh-capabilities.md`「环境依赖与边界」）。
2. 角色禁编排：派发 prompt 末尾必须带禁编排约束（禁止 `subagent`/`subagent_fork`/`workflow`/`send_message` 等），防 DSH 子代理套娃（AGENTS.md 启动流程第一步）。
3. 回报位置：代码类卡回报在 worktree 内，主工作区 `reports/` 副本可能过期——验收前先 `patrol.ps1` 定位实际路径。
4. 跨会话恢复：会话重启后 subagentId 失效，按 `PM-操作指南.md` §五从 SSOT 恢复后重新派发；角色按 AGENTS.md 从 docs 恢复**已落盘**认知。
5. workflow 边界：workflow 脚本不能直接访问文件系统/网络/定时器；文件与 git 操作一律由 PM（pwsh）或子代理（完整工具）执行。
6. 旧版 run_code 驱动：`run_code` 在当前宿主不可用；如仓库历史中存在旧版 `tools.*` 调用示例，以本文为准并删除。

---

## 变更记录

| 日期 | 变更内容 | 变更人 |
|------|---------|--------|
| 2026-08-16 | v2：run_code 版废弃，改为 pwsh / subagent / send_message / workflow 实际可用驱动（含按 phase 操作序列 + workflow 并行派发脚本） | R99 |
