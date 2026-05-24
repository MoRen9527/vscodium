# VSCodium Product State

## Module Overview

- `vscodium` 是与 `Tripilot` 配套的工具基础设施和宿主环境之一。
- 它在商业模式中承担 PC 端软件层中的 IDE 入口、宿主环境和桌面工具基础设施能力。
- 它直接采用开源上游项目作为基础，并会定期跟随上游升级，以获得新功能和宿主能力演进。

## Current Product Scope

- 提供宿主环境、构建与分发基础。
- 与 `Tripilot`、`Tride` 一起构成 PC 端软件层中的 IDE 与桌面工具基础设施能力域。
- 通过定期跟随上游版本，为 PC 端软件层持续吸收 IDE 宿主侧的新功能。
- 作为用户承载本地自动化、PC 软件自动化与 `vibe coding` 的桌面宿主之一。
- 与 `TriLC` 协同承接本地化任务在 IDE 宿主侧的承载与执行环境准备。
- 不承担正式宿主适配或切换语义；正式宿主配置由 `TriHost` 负责。

- 涉及具体项目代码仓库时，产品侧文档基线应按 `PROJECT.md`、`REQUIREMENTS.md`、产品版 `ROADMAP.md` 和产品版 `STATE.md` 维护；若缺失，应视为待补齐的产品真源缺口。

## Current Progress

- 已具备根级 `AGENTS.md`、`README.md`、`product.json` 和首版 registry 工作层。
- 当前产品状态需要严格区分 upstream 能力与本地业务定制。
- 当前已明确采用“上游持续跟进 + 本地定制分层描述”的产品口径。
- 当前边界已与中央口径对齐为 PC 端软件层中的 IDE 宿主基础设施，而不是统一 runtime 或正式宿主层。

## Bug And Gap State

- 仓库体量很大，产品侧容易误把 upstream 事实当作本地业务能力。
- 若不持续说明“新功能来自上游周期性升级”，容易把宿主演进误写成本地产品团队独立交付。
- 当前缺少精简后的本地定制产品摘要。

## Cross-Module Dependencies

- 与 `Tripilot`、`Tride` 共同构成 PC 端软件层。
- 与 `TriLC` 协同完成本地域任务的桌面宿主承载。
- 与 `TriHost` 存在未来正式宿主适配边界关系，但不承担该层职责。
- 与 `TriMetaverse` 的总体商业模式和中央策略保持对齐。

## Architecture State

- 当前更像 PC 端软件层中的 IDE 宿主基础设施和构建层，而不是单独的业务产品模块。

## Sources

- `../../AGENTS.md`
- `../../README.md`
- `../../product.json`
