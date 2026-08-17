# Git 协作规范

> 多 Agent 并行开发时，Git 是代码协作的唯一真相来源。本文档定义分支策略、合并权限和冲突处理。

---

## 一、分支策略

```
main（生产就绪，只接受 develop 合并）
 │
develop（集成分支，各 feature 合并到这里）
 │
 ├── feature/TC-001-sample-module  ← R02 后端
 ├── feature/TC-002-sample-page    ← R04 前端
 ├── feature/TC-003-sample-ai      ← R09 AI
 └── infra/TC-010-ci-pipeline      ← R06 DevOps
```

| 分支类型 | 命名规则 | 从哪分出 | 合并到哪 | 谁合并 |
|---------|---------|---------|---------|--------|
| feature | `feature/TC-{序号}-{简述}` | develop | develop | PM（验收后统一执行，见 §2.3/§三） |
| infra | `infra/TC-{序号}-{简述}` | develop | develop | PM（验收后统一执行，见 §2.3/§三） |
| ai | `ai/TC-{序号}-{简述}` | develop | develop | PM（验收后统一执行，见 §2.3/§三） |
| hotfix | `hotfix/{简述}` | main | main + develop | PM 指派 |

---

## 二、分支生命周期与基线规则

### 2.1 默认串行流程

除非任务卡明确标注为并行任务，所有依赖关系明确的任务都遵循以下流程：

```text
develop（最新整合状态）
    ↓ 创建任务分支
feature/TC-XXX（角色开发）
    ↓ 提交回报
PM 验收
    ↓ 验收通过
合并回 develop
    ↓
下一张任务卡从最新 develop 创建分支
```

因此，**下一张任务卡默认必须从最新的 `develop` 创建**，而不是从旧 feature 分支或旧的 develop 创建。这样它才能自动包含之前已验收并合并的任务内容。

### 2.2 创建任务分支前的强制检查

PM 派发任务卡前必须确认：

```powershell
git -C "<仓库根目录>" fetch --all
git -C "<仓库根目录>" worktree list --porcelain
git -C "<develop 所在 Worktree>" pull --ff-only
git -C "<develop 所在 Worktree>" log -1 --oneline develop
```

先通过 `git worktree list --porcelain` 找到当前检出 `develop` 的 Worktree，再在该 Worktree 中执行更新。不得假设仓库根目录当前就检出了 `develop`，也不得在 `develop` 已被其他 Worktree 占用时重复 `switch develop`。

然后从该最新提交创建 feature 分支和 Worktree，并将以下信息写入任务卡文件头 front-matter（建议用 `.\scripts\new-worktree.ps1` 自动回填）：

```text
base_branch：develop
base_commit：abcdef1
target_branch：develop
```

如果任务必须基于尚未合并的前置分支开发，必须在任务卡中明确写出：

```text
基线分支：feature/TC-XXX
base_commit：abcdef1
原因：依赖 TC-XXX，等待其合并前先进行受控并行开发
```

这种分支属于例外，不得作为默认流程；前置分支合并后，后续分支应 rebase 或重新从最新 `develop` 创建。

### 2.3 验收后的合并闭环

PM 验收通过后，必须由 **PM 执行合并**（可用 `.\scripts\merge-card.ps1 -Card TC-XXX`）并完成以下动作：

1. 确认目标 feature 分支工作区干净；
2. 由 PM 将 feature 分支合并到 `develop`（`git merge --no-ff`）；
3. 在 `develop` 上运行受影响的测试或构建检查；
4. 记录合并提交和目标分支；
5. 将任务卡 front-matter 状态更新为 `merged`（merge-card.ps1 自动完成）；
6. 后续任务从合并后的最新 `develop` 创建；
7. **清理已合并的 feature 分支与 worktree**（merge-card.ps1 默认自动执行；若清理失败或被 `-SkipCleanup` 跳过，手动执行 `git worktree remove <workdir>` + `git branch -d <branch>`）；
8. 运行 `.\scripts\patrol.ps1` 巡检，确认「已合并残留」无告警。

仅有 feature 分支提交但尚未合并到 `develop` 时，任务只能视为“验收通过待合并”，不能作为后续任务的默认基线。

### 2.4 并行任务

互不依赖且修改文件无交集的任务可以从同一个 `develop` 基线并行创建：

```text
develop（同一个基线）
├── feature/TC-018
└── feature/TC-019
```

并行任务都验收通过后，分别合并回 `develop`。如果第二个任务合并时发生冲突，必须暂停并按冲突处理流程解决，不能直接覆盖先合并的任务。

并行任务不能把彼此的 feature 分支作为默认基线；只有任务卡明确声明依赖时，才允许这样做。

> **工作区隔离**：所有任务卡（含串行，代码类）一律使用独立 Worktree，主工作区归 PM 专用——见 §4。并行任务从同一基线创建分支时，各卡工作区天然物理隔离。

### 2.5 未合并分支巡检

PM 每次派发新任务前，应检查是否存在已经 `accepted` 但尚未合并的 feature 分支：

```powershell
git branch --no-merged develop
git log --graph --oneline --decorate --all
```

如果存在未合并的前置任务，PM 必须先合并，或在新任务卡中明确记录例外基线和依赖关系，不得静默从旧 `develop` 创建新任务。

---

## 三、合并权限

| 操作 | 谁可以做 | 前置条件 |
|------|---------|---------|
| 创建 feature 分支 | 对应角色 | 收到任务卡 |
| 提交 commit | 对应角色 | 在允许修改范围内 |
| 合并到 develop | PM（可用 `.\scripts\merge-card.ps1`） | 任务卡状态 accepted |
| 合并到 main | R06（或 PM 指派） | staging 验证通过 + PM 上线批准 |

> **原则**：任何人都可以提交到自己分支；合并到共享分支（develop/main）必须 PM 验收通过。

---

## 四、Worktree 定位与验收

> **风险背景（为什么代码类任务必须隔离）**：Git 分支切换不会隔离**未提交**的本地改动——多角色共享同一物理工作区时，角色遗留的未提交文件会被其他角色的 checkout / commit 一并带走，造成交叉污染与分支串扰。因此**代码类任务卡（含串行）一律独立 worktree 隔离**。

### 4.1 分支与目录的关系

分支不是目录。Worktree 是某个分支对应的一份实际文件目录；同一仓库可以同时拥有多个 Worktree，但同一分支不能被多个 Worktree 同时检出。

**分支是每张任务卡的必需项；代码类任务卡一律使用独立 Worktree。**

- **代码类任务卡（含串行任务）一律独立 Worktree**：工作目录写入任务卡 front-matter `workdir`。创建 Worktree 使用 `.\scripts\new-worktree.ps1 -Number {XXX} -Summary {简述}`——一条命令完成分支创建、worktree add 与基线提交记录，并自动回填任务卡 front-matter（`workdir` / `base_branch` / `base_commit`）。
- **纯文档/纯配置类任务卡**（不涉及业务代码，如 PM 自行维护的文档更新）：可在主工作区执行，front-matter `workdir` 填「主工作区」并在 `workdir_note` 写明理由。
- **主工作区归 PM 专用，默认检出 `develop`（集成分支）**：主工作区只检出 `develop` / `main`，供 PM 维护 `docs/` 与 `task-cards/` 及验收归档；角色不得在主工作区检出或切换业务 feature 分支。**PM 建卡、回填 front-matter、改状态、归档等全部操作必须在 `develop` 检出状态下进行并 commit 到 `develop`**——若主工作区停留在 `main`，任务卡文件不会进入 `develop`（feature 分支从 develop 创建），角色在 Worktree 中看不到任务卡、`merge-card.ps1` 在 develop 上找不到任务卡，合并闭环断裂。初始化时主工作区切换到 develop 见 `docs/初始化清单.md` §二。
- **已有角色占用主工作目录时**：新任务不能强行切换该目录，应创建独立 Worktree，或等待目录释放。
- **执行纪律**：角色所有命令（改代码/测试/git 提交）一律在任务卡「工作目录」内执行；禁止在他人 worktree 或主工作区（develop）操作。

每张任务卡开始执行时，角色必须确认并在**回报文件头 front-matter** 记录分支和实际工作目录（`workdir_type` / `worktree` / `branch` / `base_commit` / `head_commit` / `workspace_status`，见 `reports/template.md`）：

```text
任务卡：TC-XXX
工作目录类型：worktree
Worktree：D:/项目/项目名-TCXXX
分支：feature/TC-XXX-xxx
基线提交：abcdef1
```

### 4.1.1 回报落盘规则

> 代码类任务卡的回报在**任务卡 Worktree 内**编写并写入该 Worktree 的 `reports/TC-XXX-回报.md`，与代码一同提交（合并进 develop 后主工作区自动获得该文件）；纯文档/纯配置卡在主工作区执行时，回报写入主工作区 `reports/`。PM 通过 `patrol.ps1`（枚举全部 Worktree 取最新）或 `git worktree list --porcelain` 定位读取，不直接依赖主工作区 `reports/` 副本。

### 4.2 PM 定位的权威来源

`git worktree list --porcelain` 是分支与 Worktree 路径映射的权威查询方式。PM 验收某个任务时，必须在任务回报指定的实际工作目录中检查；使用 Worktree 时先通过该命令核对目录：

```powershell
git worktree list --porcelain
git -C "<worktree>" status --short --branch
git -C "<worktree>" log -1 --oneline
git -C "<worktree>" diff
```

验收时至少确认：

- 当前目录确实是任务回报中的工作目录；
- 当前分支与任务卡、回报文件中的分支一致；
- 最新提交属于该任务；
- 工作区干净，或已明确记录未提交文件及原因；
- 回报文件存在且内容已纳入最新提交。

工作区存在未提交修改时，PM 不得将任务判定为“验收通过”或允许合并；应要求角色先提交、补充回报，或将任务标记为 `partial` / `blocked`。

### 4.3 三种完成状态

| 状态 | 含义 | 是否允许合并 |
|------|------|--------------|
| `done` / 已完成待验收 | 角色已完成实现并提交回报，PM 尚未验收 | 否 |
| `accepted` / 验收通过 | PM 已核对 Worktree、代码、测试和回报 | 是 |
| `merged` / 已合并 | 已进入 `develop` 或其他目标共享分支 | 已完成 |

“角色口头说已完成”只能触发验收，不能直接视为 `accepted` 或 `merged`。

---

## 五、冲突处理

```
角色 A 提交
     ↓
PM 合并到 develop → 成功
     ↓
角色 B 提交
     ↓
PM 合并到 develop → 冲突！
     ↓
角色 B 暂停
     ↓
回报标注"Git 冲突"：
  - 冲突文件：xxx
  - 冲突原因：两个角色修改了同一文件
  - 建议：需要 PM 协调
     ↓
PM 决策：
  ├── PM 先合并 A → B rebase 后再提交
  └── 手动解决冲突 → PM 指定责任人
```

### 冲突预防

| ✅ 做法 | ❌ 做法 |
|--------|--------|
| 任务卡标注"文件 X 已被 R0X 锁定，请绕行" | 两张卡同时修改同一文件 |
| `git pull --rebase` 后再 push | `git push --force` |
| 提交前本地跑测试 | 跳过测试直接 push |

---

## 六、Commit 格式

各角色提交遵循以下统一格式（角色文件中无独立「提交规范」小节，以本节为唯一权威）：

```
<type>(TC-{序号}): <简述>

# 示例
feat(TC-001): add user authentication API
fix(TC-001): handle token expiry edge case
ci(TC-010): add backend lint to CI pipeline
prompt(TC-012): update agent prompt rules, eval metrics {X}%
```

> **禁止的 commit message**：`update code`、`fix bug`、`wip`、`.`——必须描述做了什么。

---

## 七、Git 与 SSOT 的关系

- Git 仓库是**代码**的单一事实来源
- `docs/` 目录是**设计/契约/决策**的单一事实来源
- 两者互补：代码实现契约，契约解释代码

> 冲突处理优先级：`docs/architecture.md`（契约） > Git 中的代码（实现）。代码偏离契约时，以契约为准——代码是错的，需要修复。
