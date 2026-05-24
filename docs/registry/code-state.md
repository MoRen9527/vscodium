# VSCodium Code State

## Repository Map

- `custom/`：本地定制入口
- `patches/`：定制补丁
- `vscode/src/`：上游源码镜像区
- 构建脚本：根级 shell 脚本和相关配置

## Current Code Health

- 仓库成熟度高，但规模和上游混入度也高。
- 仓库会周期性跟随上游版本升级，因此代码侧必须持续区分 upstream 同步层与本地定制层。
- 尚未建立 registry 级代码健康评分和 git 健康摘要。

## Change Tracking Baseline

- 关键关注本地 `custom/`、`patches/` 和 server bootstrap 入口。
- 与上游同步相关变化必须显式区分为 upstream 或 local，并说明是否属于定期升级带来的新功能吸收。
- 与 `Tripilot`、`Tride` 或 `TriHost` 边界相关的宿主基础设施变化，应同步回写中央 strategy 边界。

- 涉及具体项目代码仓库时，技术侧文档基线应按 `docs/engineering/DESIGN.md`、技术版 `ROADMAP.md`、技术版 `STATE.md` 以及 `docs/execution/<workstream>/<phase>/PLAN.md`、`SUMMARY.md`、`VERIFICATION.md` 维护；若缺失，应视为待补齐的技术或执行层缺口。

## Local CodeGraph Index

- 2026-05-24 已由 CTO 小狄技术线完成本地 CodeGraph 试点探测，并由本模块 CodeRegistry 接管索引限制说明。
- 索引范围只试探 `patches/` 本地补丁面；不对仓根、`upstream/` 或上游源码镜像做 CodeGraph 初始化，避免把周期性 upstream 噪音误写成本地代码事实。
- 当前摘要：0 files，0 nodes，0 edges，languages 为空。
- 说明：当前本地差异主要以 `.patch` 文件呈现，现有 CodeGraph parser 未产出可用语义图。该结果只能说明“当前 CodeGraph 不适合作为 vscodium 补丁面的语义索引”，不能说明本地补丁不存在。
- 后续 vscodium CodeRegistry 仍应以 `patches/`、`custom/`、构建脚本和 upstream/local 边界的人工梳理为主；`.codegraph/` 只作为本地探测缓存，不作为仓库真源提交。

## Git Health

- 尚未在 registry 中维护分支、补丁热区或同步压力摘要。

## Quality Risks

- 规模过大，若不先做本地定制过滤，Role Agents 会被噪音淹没。
- 若不持续区分周期性 upstream 升级与本地修改，后续很容易误判能力来源和改动责任边界。
- 宿主基础设施和业务能力边界容易混淆。
- 若把 vscodium 误写成正式宿主适配层或统一 runtime，会直接破坏 PC 端软件层与 TriMC/TriHost 的分层。

## Sources

- `../../custom/`
- `../../patches/`
- `../../vscode/src/`
- `../../AGENTS.md`
