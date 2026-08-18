# {{ project-name }}

{{ description }}

## 开发环境

### Rust 工具链

工具链由 [`rust-toolchain.toml`](rust-toolchain.toml) 固定为 **{{ toolchain }}**，首次进入目录时 rustup 会自动安装。
注意这个文件会**覆盖你 rustup 的全局默认工具链**，在本项目目录内一律以它为准。

[`rustfmt.toml`](rustfmt.toml) 用到了 `imports_granularity`、`group_imports`、`wrap_comments`
等 unstable 选项，只有 nightly 的 rustfmt 才认，所以格式化命令统一写成 `cargo +nightly fmt`。
{% if toolchain == "stable" %}
本项目跑在 stable 上，需要额外装一次 nightly 的 rustfmt：

```bash
rustup toolchain install nightly --profile minimal --component rustfmt
```
{% else %}
本项目本身就跑在 nightly 上，`+nightly` 指向的是同一个工具链，不需要额外安装。

nightly 是滚动更新的，偶尔会出现某个版本缺 `rustfmt` / `clippy` 组件，或者 clippy 新增的
lint 让 CI 的 `-D warnings` 突然挂掉。真遇上了就把 `channel` 钉成日期版本，例如
`channel = "nightly-2026-08-01"`——但那之后 `+nightly` 会指向另一个工具链，
需要单独安装 nightly，或把命令里的 `+nightly` 去掉。
{% endif %}
### MSRV

`Cargo.toml` 里的 `rust-version` 声明了最低支持版本。它**只是下限，不限制上限**，
用更新的 stable 或 nightly 编译都没问题。

`just msrv` 和 CI 的 msrv job 会真的用那个版本编译一遍来验证声明属实；
但如果 `rust-toolchain.toml` 的 channel 是 nightly，这项检查会**自动跳过**——
nightly 项目可能用了 `#![feature(...)]`，那种代码在任何 stable 上都编不过，检查没有意义。

### 配套工具

一条命令装齐：

```bash
just install-tools
```

或者手动逐个安装：

```bash
cargo install just                            # 命令入口（见 justfile）
cargo install --locked cargo-nextest          # 测试
cargo install --locked cargo-deny             # 依赖安全与 License 检查
cargo install --locked typos-cli              # 拼写检查
cargo install --locked cargo-llvm-cov         # 覆盖率
cargo install --locked cargo-outdated         # 检查依赖是否有新版本
cargo install --locked git-cliff              # 生成 CHANGELOG
cargo install --locked cargo-release          # 发版
cargo install --locked bacon                  # 后台实时监控
```

### pre-commit

```bash
pipx install pre-commit
just hooks
```

`just hooks` 会装上 `pre-commit`、`commit-msg`、`pre-push` 三类钩子：
提交前跑格式化 / clippy / 拼写检查，提交时校验 commit message 规范，推送前跑全量测试。

## 常用命令

`just` 直接列出全部命令（按用途分组）。

```bash
just                    # 列出所有命令
just check              # 快速检查编译
just run -- --help      # 运行程序，-- 后的参数透传给程序
just fmt                # 格式化（nightly）
just fix                # clippy --fix 自动修复 + 格式化
just dev                # bacon 实时监控
just doc                # 生成并打开 API 文档

just lint               # 格式化检查 + clippy + typos
just test               # 运行测试（含 doctest）
just coverage           # 生成覆盖率报告 lcov.info
just audit              # cargo deny check
just msrv               # 验证 MSRV 能编译
just ci                 # 本地跑一遍 CI 的全部检查

just update             # 升级 Cargo.lock 并重新审计
just outdated           # 列出可升级的依赖

just changelog          # 刷新 CHANGELOG.md
just release minor      # 发版预演（不改动任何东西）
just release-execute minor  # 真正发版：抬版本号 + CHANGELOG + tag + 推送
```

## 项目里的各个配置文件

| 文件 | 作用 |
| --- | --- |
| [`rust-toolchain.toml`](rust-toolchain.toml) | 固定工具链版本与组件 |
| [`rustfmt.toml`](rustfmt.toml) | 格式化规则（含 unstable 选项，走 nightly） |
| [`clippy.toml`](clippy.toml) | Clippy 行为配置（lint 开关在 `Cargo.toml` 的 `[lints]`） |
| [`deny.toml`](deny.toml) | 依赖的安全公告 / License / 重复版本 / 来源审计 |
| [`_typos.toml`](_typos.toml) | 拼写检查的词表与排除规则 |
| [`cliff.toml`](cliff.toml) | git-cliff 生成 CHANGELOG 的模板与分组规则 |
| [`release.toml`](release.toml) | cargo-release 的发版流程配置 |
| [`bacon.toml`](bacon.toml) | bacon 实时监控的任务定义 |
| [`.config/nextest.toml`](.config/nextest.toml) | 测试运行器配置（含 CI 专用 profile） |
| [`.pre-commit-config.yaml`](.pre-commit-config.yaml) | Git 钩子 |
| [`.editorconfig`](.editorconfig) | 跨编辑器的基础排版约定 |
| [`.github/workflows/`](.github/workflows/) | CI：lint / test / deny / msrv / release + 每日安全审计 |
| [`.github/dependabot.yml`](.github/dependabot.yml) | 依赖与 Actions 的自动升级 |

## CI

推送和 PR 会触发 [`build.yaml`](.github/workflows/build.yaml)，并行跑四个 job：

- **lint** —— 格式化、拼写、clippy（`-D warnings`）、文档警告
- **test** —— `cargo check` + nextest（CI profile：不 fail-fast、失败重试、输出 JUnit）+ 覆盖率 + doctest
- **deny** —— 依赖的安全公告 / License / 重复版本 / 来源
- **msrv** —— 用 `Cargo.toml` 里声明的最低版本编译一遍

打上 `v*` tag 后，在上面三项通过的前提下额外跑 **release** job：用 git-cliff 生成本次的变更说明并创建 GitHub Release。

[`audit.yaml`](.github/workflows/audit.yaml) 每天定时跑一次依赖审计——安全公告是"代码没动风险也会变"的东西，只靠 PR 触发发现不了。

## 提交规范

本项目使用 [Conventional Commits](https://www.conventionalcommits.org/)，
`CHANGELOG.md` 由 [git-cliff](https://git-cliff.org/) 依据提交信息自动生成：

```
feat(parser): 支持嵌套表达式
fix: 修正边界条件下的 panic
docs: 补充 README
```

commit message 由 pre-commit 的 `conventional-pre-commit` 钩子强制校验。

## VSCode

[`.vscode/extensions.json`](.vscode/extensions.json) 列出了推荐插件，打开项目时 VSCode 会提示安装；
[`.vscode/settings.json`](.vscode/settings.json) 已经把 rust-analyzer 配好：保存时用 clippy 检查（参数与 CI 一致），
格式化走 nightly rustfmt，避免编辑器和 CI 的结果不一致。

## License

协议在生成项目时选定，对应的许可证文件在仓库根目录：
单协议是 `LICENSE`，双协议（MIT OR Apache-2.0）则是 `LICENSE-MIT` 与 `LICENSE-APACHE`。
具体取值见 `Cargo.toml` 的 `license` 字段。
