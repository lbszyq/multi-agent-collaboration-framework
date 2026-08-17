# code/ —— 业务代码根目录

本目录存放**所有与业务相关的代码**（前端、后端、测试、构建产物、迁移脚本等开发过程中产生的代码）。

## 规则

- 所有业务代码统一放在 `code/` 内，**禁止**在仓库根目录或 `docs/`、`roles/`、`scripts/`、`task-cards/`、`reports/` 等框架/协作目录下并行创建业务代码文件。
- 目录内部可按项目需要分层（如 `code/backend/`、`code/frontend/`），具体结构由 R01 在 `docs/architecture.md` 中定义。
- 任务卡「允许修改范围」、回报「文件清单」中的代码路径一律以本目录为根（约定见 `docs/architecture.md` §1.1）。