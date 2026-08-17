# reports/ 目录

> 此目录存放各角色的完工回报文件。

## 谁来写

各角色完成 `task-cards/` 中的任务后，按 `reports/template.md` 格式编写回报并写入此目录。

## 谁来读

PM（R99）在此目录读取回报文件进行验收。

## 文件命名规范

```
reports/TC-{序号}-回报.md
```

例如：`reports/TC-001-回报.md`

> **注意**：`TC-XXX-回报.md` 是各角色（含 R03）的**完工回报**——它是 `validate-report.ps1` 校验的对象、PM 验收的依据。R03 的测试详细报告等**附属产物**（`TC-XXX-测试报告.md`、`screenshots/`、`logs/`、`test-data/`）不参与该校验，命名不受 `TC-XXX-回报.md` 约束（见 `roles/R03-QA工程师.md` §测试产物规范）。

## 写入时机

1. 角色完成 `task-cards/TC-XXX-*.md` 中定义的任务
2. 角色按 `reports/template.md` 格式编写回报
3. 将回报写入任务卡工作目录的 `reports/TC-XXX-回报.md`（代码类卡在 Worktree 内随代码提交；纯文档卡在主工作区执行时写入主工作区 `reports/`），然后在对话中按固定格式回复（含工作目录/分支/提交/工作区状态等定位信息，格式见 `roles/templates/worker-init.md`——完成信号格式唯一权威）
4. PM 读取回报文件进行验收（自动化模式：DSH 下等后台 subagent 落定自动通知后触发，`patrol.ps1` 定位回报；Codex 用 `wait_agent` 或轮询 `reports/`；手工模式：用户将完成消息告知 PM）

## 注意

- 不要手动删除此目录中的文件（归档由 PM 决定）
- 代码类卡（Worktree 模式）的回报在 Worktree 内提交，主工作区 `reports/` 的旧副本不代表最新——PM 用 `patrol.ps1` 枚举全部 Worktree 按修改时间取最新读取
- 回报文件可以覆盖更新（同一任务卡多次修改时）
