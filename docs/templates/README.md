# docs/templates/ 目录

> 存放各产出角色的**交付物模板**。项目初始化时随框架一并复制，角色产出时以此为骨架，避免每次现场发挥导致质量不可控。

---

## 模板清单

| 模板 | 使用角色 | 产出物 | 落盘位置（项目内） |
|------|---------|--------|-------------------|
| `prd-template.md` | R10 产品经理 | 产品需求文档（PRD） | `docs/prd.md` |
| `requirements-template.md` | R10 产品经理 | 需求条目（REQ） | `docs/requirements/*` |
| `design-system-template.md` | R11 UI/UX 设计师 | 设计系统文档 | `docs/design-system.md` |
| `ai-evaluation-template.md` | R09 AI 工程师 | AI 评估报告 | `docs/ai-evaluation.md` |
| `agent-observability-template.md` | R09 AI 工程师 | Agent 链路可观测性设计/实现说明 | `docs/ai-observability.md` |

> 命名约定：项目落盘文件不带 `-template` 后缀（如 `docs/prd.md`），与 `docs/architecture.md`、`docs/contracts/` 的引用保持一致。

---

## 使用方式

1. PM 初始化项目时，指示对应角色"按 `docs/templates/` 对应模板产出"。
2. 角色复制模板到目标路径，删除模板中的说明性注释（`<!-- -->`），逐节填写。
3. 模板中标注"条件章节"（如 AI 能力需求）的内容，不适用时删除该节并说明理由。
4. 产出物冻结后，修改必须走 `docs/变更管理流程.md` 的正式 CR 流程。

## 变更记录

| 日期 | 变更内容 | 变更人 |
|------|---------|--------|
| — | — | — |
