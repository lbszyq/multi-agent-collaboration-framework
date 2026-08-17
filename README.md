# 多 Agent 协同开发模式

> **一句话概括**：PM 产出任务卡并派发，角色（独立对话）完成后写回报到仓库，PM 验收形成闭环；重要决策节点（角色组合确认、原型确认、产品验收、需求变更代价确认）由用户决定。派发/回报默认走手工粘贴（用户当信使），自动化编排仅在宿主支持时启用。

---

## 核心理念

每个角色是一个独立对话（手工模式为侧边栏对话，自动化模式为子代理），上下文完全隔离，只从 docs 建立认知。PM 产出任务卡与派发指令，用户手动粘贴派发（手工模式）或由宿主自动注入（自动化模式）；角色完成后写回报，PM 验收。重要决策节点由用户拍板。

---

## 工作流程

```
PM 产出任务卡（写入 task-cards/）
    │
    ▼
PM 输出派发文本块（角色身份 + 任务卡）→ 用户粘贴到角色对话
    │
    ▼
角色读 docs/ → 执行 → 写回报到 reports/ → 对话回报"已完成"
    │
    ▼
用户转述给 PM → PM 巡检 reports/ → 逐条验收 → 通过归档 / 不通过驳回
```

---

## 快速上手

1. 将 `roles/R99-PM.md` 作为 PM 对话（主编排线程）的第一条消息
2. 对它说："初始化多 Agent 协作，我要做 XX 项目"
3. PM 推荐角色组合，向你确认（人工决策节点）
4. 你确认后，PM 自动拉起角色子代理并注入初始化消息与 skill
5. PM 产出任务卡 → 注入子代理执行 → 回报 → PM 验收；原型确认 / 产品验收等节点由你拍板

---

## 目录结构

```
├── README.md                    ← 本文件
├── AGENTS.md                    ← 所有角色对话的入口
├── code/                        ← 业务代码根目录（所有业务相关代码，禁止与框架/协作目录并行）
├── PM-操作指南.md               ← PM 操作手册
├── lessons.md                   ← 框架经验记录（项目复制回框架仓库供学习，见 PM-操作指南 §十一）
├── docs/
│   ├── project-status.md        ← 项目实时状态（共享真相）
│   ├── architecture.md          ← 架构与接口契约
│   ├── decisions.md             ← 决策记录
│   ├── thread-routing.md        ← 对话路由表
│   ├── 自动化协作协议.md         ← 完整协议文档
│   ├── codex-capabilities.md    ← Codex 可用能力说明
│   ├── dsh-capabilities.md      ← DSH（DeepSeek Harness）协作能力与术语速查
│   ├── dsh-pm-driver.md         ← DSH PM 编排驱动（pwsh/subagent/workflow 参考实现）
│   ├── cloudbase-capabilities.md ← CloudBase（腾讯云开发）部署/数据/AI 映射
│   ├── 质量验收标准.md             ← 四层质量门槛体系
│   ├── 变更管理流程.md             ← 需求变更管理流程
│   ├── 轻量任务通道.md             ← 简单任务低摩擦通道（light 卡）
│   ├── 初始化清单.md                 ← PM 初始化操作清单（空项目：Git 基线/规模/角色/质量裁剪）
│   ├── 存量项目接入清单.md           ← 已有代码/历史项目的逆向接入清单
│   ├── 规则权威索引.md               ← 高频规则唯一权威映射（收敛重复）
│   ├── adr/                      ← 架构决策记录（ADR）
│   │   ├── README.md
│   │   └── template.md
│   ├── changes/                  ← CR 文档存档
│   │   └── README.md
│   ├── contracts/                ← API 契约文件
│   │   └── README.md
│   ├── design/                   ← 设计资产管理
│   │   └── history/              ← 设计版本归档
│   │       └── template.md
│   ├── retrospectives/           ← 阶段复盘文档（RT-XXX）
│   └── templates/                ← 产出物模板（PRD/设计系统/AI 评估/Agent 可观测性）
├── roles/
│   ├── R99-PM.md                ← PM 编排者
│   ├── R10-产品经理.md           ← 产品产出者
│   ├── R11-UIUX设计师.md         ← 设计产出者
│   ├── R01-架构师.md             ← 技术角色
│   ├── R02-后端工程师.md
│   ├── R03-QA工程师.md
│   ├── R04-前端工程师.md
│   ├── R05-数据工程师.md
│   ├── R06-DevOps工程师.md
│   ├── R07-iOS工程师.md
│   ├── R08-Android工程师.md
│   ├── R09-AI工程师.md
│   ├── README.md                ← 角色体系说明
│   └── templates/
│       └── role-definition.md   ← 角色定义模板
├── .github/workflows/             ← CI 自动检查（push/PR 时运行 validate-framework + patrol，见 scripts/README.md）
├── scripts/                     ← 框架工具（建卡/建 Worktree/校验/巡检/状态生成/合并/框架一致性检查）
├── task-cards/
│   ├── template.md             ← 含 front-matter（状态唯一权威）
│   └── archive/
└── reports/
    ├── README.md
    └── template.md             ← 含 front-matter
```

---


> **规模选择**：不是所有项目都需要全部文件。参考 `docs/项目规模适配指南.md` 选择 Light / Standard / Enterprise 级别。Light 模式只需 ~8 个核心文件 + 4 个角色文件 + `scripts/` 最小工具集、3-5 个角色即可启动（worktree/校验/巡检依赖脚本，见 `docs/项目规模适配指南.md`）。
>
> **扩展性说明**：当前框架默认子代理自动化编排（PM 拉起 / 注入 / 监听），并行角色数受宿主环境子代理并发上限约束（通常为个位数，见 `docs/codex-capabilities.md`「环境依赖与边界」），超过上限时分批派发或退回手工模式；日常建卡、回报校验、巡检、状态生成与合并可复用 `scripts/` 工具集。代码类任务卡一律独立 Worktree 隔离（主工作区归 PM 专用），并行卡从同一基线创建、天然物理隔离；`project-status.md` / `thread-routing.md` 任务表由 `scripts/generate-status.ps1` 自动生成，状态唯一权威是任务卡 front-matter。框架的文档体系（SSOT + 任务卡 + 回报）在自动化场景下同样适用。

---

## 框架经验记录（lessons.md）

新项目运行中遇到的**框架问题**（流程卡壳、脚本缺陷、文档矛盾、模板冗余、规则误报）由 PM 随手记入项目根目录 lessons.md；用户将 lessons.md 复制回框架仓库，框架仓库每次迭代前先读 lessons.md 处理 [open] 条目——采纳则落地改动并标 [done]，不采纳则标 [done] 不采纳（理由）。格式与约定见 lessons.md 与 PM-操作指南.md §十一。

## 核心设计决策

1. **子代理即角色**：每个角色默认 = 一个常驻子代理（上下文完全隔离）；同一角色确需并行时按「临时并行实例」例外执行（见 `roles/README.md`「常驻与并行实例规则」）；手工 fallback 下为 Codex 独立对话
2. **文档即真相（SSOT）**：`architecture.md` > `prd.md` > `design-system.md` > `质量验收标准.md` > `decisions.md` > `task-cards` > 对话（完整优先级表见 AGENTS.md「事实来源优先级」）。对话是通信通道，不是事实存储。任何对话都能独立从 docs 建立认知
3. **任务卡即合约**：精确的允许/禁止修改范围 + 可验证的验收标准
4. **重要节点人工决策**：角色组合确认、原型确认、产品验收、需求变更代价确认由用户拍板；其余流程由 PM 自动化编排
5. **先原型后实现**：前端先搭可交互原型让用户确认，确认后方可进入完整实现
6. **状态单一化**：任务状态唯一权威 = `task-cards/*.md` 文件头 front-matter；`project-status.md` / `thread-routing.md` 任务表由 `scripts/generate-status.ps1` 自动生成，禁止手改
7. **统一工作区模型**：代码类任务卡一律独立 Worktree，主工作区归 PM 专用；合并动作由 PM 统一执行（`scripts/merge-card.ps1`）

---

## 适用范围

- ✅ 多模块、前后端+数据库的中型项目
- ✅ 需持续迭代的商业项目
- ✅ AI 团队按角色分工协作
- ❌ 一次性 demo、单文件脚本





