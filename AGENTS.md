# VSCodium Agent Rules

## Module Role

- vscodium 是与 Tripilot 配套的工具基础设施和宿主环境之一。
- vscodium 直接采用开源上游项目作为基础，并会定期跟随上游版本升级，以获得新功能与宿主能力演进。
- 当商业模式涉及 IDE 入口、宿主能力、扩展环境和桌面工具基础设施时，需要考虑本模块。

## Strategy Delegation

- 总商业模式、当前商业实验、vscodium 是否进入当前路径、与 Tripilot 的边界，先咨询 `TriMetaverse/BusinessStrategy`。
- 不要在本地把 upstream 体量误当作商业优先级本身。

## Local Fact Sources

- 产品事实：`README.md`、`product.json`
- 代码事实：`custom/`、`patches/`、`vscode/src/`、构建脚本

## Current Registries

- `VscodiumBusinessStrategyRegistry`
- `VscodiumProductRegistry`
- `VscodiumCodeRegistry`

当前 registry agent canonical discovery 位于 `vscodium/.github/agents/`。同名中央 discovery 文件不应在 `TriMetaverse/.github/agents/` 并行保留；中央只通过 manifest 和 registry closeout 工作流路由本模块 registry。

## Update Discipline

- 对 upstream 与本地定制必须分开描述，避免把上游事实误记为本地业务能力。
- 对定期 upstream 升级带来的新功能，应明确区分“来自上游同步”与“本地新增定制能力”。
