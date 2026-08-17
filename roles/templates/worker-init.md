# Worker 对话初始化模板

> PM 拉起角色子代理时注入的初始化消息（自动化模式）；手工 fallback 下由用户粘贴为对话首条消息。
> **注入硬约束**：必须把 `[R0X]-[岗位名]` 替换为真实值（如「R01-架构师」）。缺少角色身份的初始化消息无效——子代理会按 AGENTS.md 兜底回复"就绪，等待角色指派"而空转。
> **规则归属**：启动流程/SSOT/安全红线见 `AGENTS.md`；回报格式见 `reports/template.md`；派发/回报/验收闭环见 `docs/自动化协作协议.md`。本文件只定义注入消息骨架与完成信号格式。高频规则唯一权威映射见 `docs/规则权威索引.md`。

---

## 注入模板

> 用下方模板组装注入消息。**除占位符外不要再重复 AGENTS.md / reports/template.md 的规则**——角色会自己读这些文件；重复反而增加漂移和 token 成本。

```
你是本项目的 **[R0X]-[岗位名]**（如「R01-架构师」）。

请按 AGENTS.md 启动流程执行：
- 认知模式：**[full | lean]**（首次/重启=full；常驻续卡=lean，见 docs/dsh-capabilities.md「常驻精简上下文协议」）
- 当前任务卡：**[TC-XXX 完整内容 / 任务卡路径]**

你是执行者，不是 PM——禁止 `subagent` / `subagent_fork` / `workflow` / `send_message`（向他人派发）等编排动作，只做任务卡范围内的事。
完成后按 `reports/template.md` 写回报并写入任务卡工作目录的 `reports/TC-XXX-回报.md`（与代码一并提交），再按下方「完成信号定位信息格式」回复。
```

---

## 完成信号定位信息格式

> 完成信号格式的唯一权威（与 `reports/template.md` front-matter 字段一致）。PM 验收依赖此定位信息；缺失 → 标记"定位信息不完整，暂不验收"。

```
TC-XXX 已完成待验收。
仓库根目录：D:/项目/项目名
工作目录类型：worktree / main（main = 主工作区，与任务卡 front-matter `workdir: 主工作区` 对应）
Worktree：D:/项目/项目名-TCXXX（worktree 时填写）
分支：feature/TC-XXX-xxx
最新提交：abcdef1
工作区状态：干净 / 有未提交修改
回报文件：reports/TC-XXX-回报.md
```

> 如果工作区有未提交修改，必须明确写出"工作区状态：有未提交修改"，并列出文件及原因；此时不得声称任务已完成，只能报告为部分完成或受阻。

---

## 使用说明

### DSH 一步派发（DSH 宿主推荐）
`subagent` 接收完整独立 prompt，无需两步派发：把「注入模板」中的 `[当前任务卡]` 替换为任务卡完整内容，直接作为 `prompt` 注入（详见 `docs/dsh-capabilities.md` §三「一步派发协议」）。

### 常驻续卡（DSH 默认）
首次/重启用 full；后续卡用 `send_message` 注入 lean 变体（`[认知模式]=lean`，可只发「注入模板」+ 任务卡，或按 `docs/dsh-capabilities.md`「常驻精简上下文协议」精简）。角色保持常驻 idle，不关闭。

### 手工 fallback
用户将「注入模板」（含任务卡）粘贴为角色对话首条消息。
