# ADR（Architecture Decision Records）

> 由 R01-架构师 维护。记录架构冻结后所有架构层面的决策。
> 区别于 `docs/decisions.md`：decisions.md 是项目级通用决策（流程/排期/角色），
> ADR 是**架构级技术决策**（如数据库选型、后端框架选型等）。

---

## 何时需要 ADR

满足以下**任意一条**就必须写 ADR：

- [ ] 架构冻结点之后，对 `architecture.md` / `contracts/` 的任何修改
- [ ] 技术选型的重大变更（换数据库、换框架、换核心库）
- [ ] 引入新的基础设施依赖（新增消息队列、新增缓存层、新增搜索引擎）
- [ ] 模块划分的调整（拆分/合并模块、改变模块间依赖方向）
- [ ] 数据模型的结构性调整（改变实体关系、改变核心表设计）
- [ ] R02/R04/R05 提出"契约偏离"，R01 判定需要架构层面响应

## ADR 编号规则

`ADR-{序号}-{关键词}`，序号从 001 开始，全局递增。

## 模板

新建 ADR 时按 `docs/adr/template.md` 模板创建（含背景/候选方案/决策/后果等章节）。

## 状态说明

| 状态 | 含义 |
|------|------|
| proposed | 提议中，尚未决策 |
| accepted | 已接受，当前生效 |
| superseded | 被后续 ADR 取代（注明取代它的 ADR 编号） |
| deprecated | 已废弃，不再适用 |

## 生命周期与批准流程

```
R01 起草 ADR（状态=proposed，写入 docs/adr/）
        ↓
PM 验收（对照 architecture.md §14 索引 + 影响分析）
        ├── 重大技术选型（换数据库/框架/核心库/引入基础设施）→ 先向用户汇报，用户确认后放行
        ↓
PM 验收通过 → 状态=accepted，登记 architecture.md §14 索引
        ↓
后续被新 ADR 取代 → superseded（注明取代编号）；废弃 → deprecated（均由 R01 提出、PM 确认）
```

- **proposed ADR 未经验收不得作为架构变更依据**——R01 不得按未验收的 ADR 修改 `architecture.md` / `contracts/`
- ADR 状态字段由 R01 维护；`accepted` / `superseded` / `deprecated` 流转须经 PM 确认
- 重大技术选型类 ADR 属人类决策节点（影响"怎么做核心架构/花多少钱"），PM 须先向用户汇报并确认，再验收放行

---


## ADR 索引

见 `docs/architecture.md` §14 ADR 索引。
