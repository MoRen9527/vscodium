# Vscodium Business State

## Registry Role

- 本文件是 `vscodium` 的 business registry 工作层。
- `vscodium` 的 `product-state.md` 与 `code-state.md` 默认应以本文件作为业务上游约束。

## Module Business Role

- `vscodium` 是与 `Tripilot` 配套的 IDE 宿主基础设施和桌面工作台承载层。
- 它通过跟随上游升级，为 PC 自动化、本地开发工作流和宿主能力演进提供基础设施。

## Current Default Business Position

- 当前默认定位是 IDE 宿主基础设施，而不是业务产品本身。

## Boundary Notes

- 对 upstream 与本地业务定制必须分开描述。
- 涉及商业优先级和整体入口策略时，应先回到中央 `BusinessStrategy`。

## Sources

- `../../AGENTS.md`
- `../../README.md`
- `../../product.json`