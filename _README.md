# {{ project-name }}

{{ description }}

## 快速开始

```bash
just doctor          # 体检：工具链组件与配套工具是否齐全（会告诉你缺什么、怎么装）
just install-tools   # 安装配套 cargo 工具（首次）
just hooks           # 安装 git 钩子（首次，需要先装 pre-commit）
just ci              # 跑一遍完整检查，确认环境就绪
just dev             # 开始写代码：bacon 盯着文件变化实时重跑 clippy
```

`just` 不带参数会列出全部命令（按用途分组）。

## 开发环境

### Rust 工具链

工具链由 [`rust-toolchain.toml`](rust-toolchain.toml) 固定为 **{{ toolchain }}**，首次进入目录时 rustup 会自动安装。
注意这个文件会**覆盖你 rustup 的全局默认工具链**，在本项目目录内一律以它为准。

同时会装上 `rustfmt`、`clippy`、`rust-src`（rust-analyzer 解析标准库要用，
缺了它编辑器里对 `std` 没有补全和跳转）和 `llvm-tools-preview`（覆盖率要用）。
`rust-analyzer`、`miri`、交叉编译 target 等可选项在该文件里以注释列出，按需打开。

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

先装 [just](https://github.com/casey/just)（命令入口，见 [`justfile`](justfile)），
再让它把剩下的装齐：

```bash
cargo install just
just install-tools
just doctor          # 确认真的都装上了
```

`install-tools` 会优先用 [cargo-binstall](https://github.com/cargo-bins/cargo-binstall)
直接下载上游发布的预编译二进制——这些工具从源码编译一遍要十几分钟，binstall 只要几十秒。
强烈建议先装上它：

```bash
cargo install cargo-binstall
```

装的是这些（也可以按需逐个 `cargo install --locked <名字>`）：

| 工具 | 用途 |
| --- | --- |
| `cargo-nextest` | 测试运行器（比 `cargo test` 快，输出也更清楚） |
| `cargo-deny` | 依赖安全公告与 License 检查 |
| `cargo-llvm-cov` | 覆盖率 |
| `cargo-release` | 发版 |
| `cargo-outdated` | 检查依赖是否有新版本 |
| `cargo-machete` | 找出声明了却没用到的依赖 |
| `cargo-semver-checks` | 公开 API 的破坏性变更检查 |
| `typos-cli` | 拼写检查 |
| `git-cliff` | 生成 CHANGELOG |
| `bacon` | 后台实时监控 |

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
just doctor             # 环境体检
just check              # 快速检查编译
just run -- --help      # 运行程序，-- 后的参数透传给程序
just fmt                # 格式化（nightly）
just fix                # clippy --fix 自动修复 + 格式化
just dev                # bacon 实时监控
just doc                # 生成并打开 API 文档
just clean              # 清理编译产物与本地报告

just lint               # 格式化检查 + clippy + typos
just test               # 运行测试（含 doctest）
just coverage           # 生成覆盖率报告 lcov.info
just audit              # cargo deny check
just msrv               # 验证 MSRV 能编译
just ci                 # 本地跑一遍 CI 的全部检查

just unused             # 找出没用到的依赖（cargo-machete）
just semver             # 公开 API 破坏性变更检查（仅 lib 项目）

just update             # 升级 Cargo.lock 并重新审计
just outdated           # 列出可升级的依赖

just changelog          # 刷新 CHANGELOG.md
just release minor      # 发版预演（不改动任何东西）
just release-execute minor  # 真正发版：抬版本号 + CHANGELOG + tag + 推送
```
{% if docker %}
容器相关命令来自 [`docker.just`](docker.just)（根 justfile 用 `import?` 可选加载）：

```bash
just docker-build       # 构建镜像（多阶段 + distroless）
just docker-run -- --help   # 运行镜像
just docker-inspect     # 用 dive 看分层体积
just docker-clean       # 删除本地镜像
```
{% endif %}
`just ci` 只包含 `lint` / `test` / `audit` 三项，和 CI 上跑的一致。
`unused` 和 `semver` 刻意留在外面手动跑：前者对宏里用到的依赖会误报，
后者需要和已发布版本联网比对——都不适合当成每次提交的硬性门槛。

## 工程结构

`Cargo.toml` 里已经铺好了 workspace 骨架：`[workspace.package]`、
`[workspace.dependencies]`、`[workspace.lints]` 三段是给**将来拆分子 crate** 准备的。
现在只有根 crate 一个成员，它通过 `version.workspace = true` / `[lints] workspace = true`
继承这些配置。等你要拆出 `crates/core`、`crates/cli` 时，
只需在 `members` 里登记，子 crate 里同样写 `.workspace = true` 即可，
版本号与 lint 规则不会各自漂移。

### 编译 profile

| profile | 用途 |
| --- | --- |
| `dev` | 自身代码 O0 保证调试体验；依赖 O2（`[profile.dev.package."*"]`），运行时快一个数量级 |
| `test` | O1，比 O0 跑得快又不用等 O3 的编译时间 |
| `release` | O3 + thin LTO + `codegen-units = 1` + strip |
| `profiling` | 继承 release 但保留符号，火焰图才有可读函数名：`cargo build --profile profiling` |
| `bench` | 继承 release 且保留符号，保证 benchmark 测的是优化后的代码 |
{% if async_runtime %}
### 异步运行时

项目已引入 [tokio](https://tokio.rs/)（`rt-multi-thread` + `macros`），入口是 `#[tokio::main]`。

同时 [`clippy.toml`](clippy.toml) 里启用了 `disallowed-types` / `disallowed-methods`：
在 async 上下文里误用 `std::fs` / `std::process` 这类**阻塞** API 会直接报错——
一次同步 `read` 就足以把 runtime 的一个 worker 线程钉死。请改用 `tokio::fs` 对应项。
确有必要时在那一处写 `#[allow(clippy::disallowed_types)]` 并说明原因。
{% endif %}
## 项目里的各个配置文件

| 文件 | 作用 |
| --- | --- |
| [`rust-toolchain.toml`](rust-toolchain.toml) | 固定工具链版本与组件 |
| [`rustfmt.toml`](rustfmt.toml) | 格式化规则（含 unstable 选项，走 nightly） |
| [`clippy.toml`](clippy.toml) | Clippy 行为配置（lint 开关在 `Cargo.toml` 的 `[workspace.lints]`） |
| [`deny.toml`](deny.toml) | 依赖的安全公告 / License / 重复版本 / 来源审计 |
| [`_typos.toml`](_typos.toml) | 拼写检查的词表与排除规则 |
| [`cliff.toml`](cliff.toml) | git-cliff 生成 CHANGELOG 的模板与分组规则 |
| [`release.toml`](release.toml) | cargo-release 的发版流程配置 |
| [`bacon.toml`](bacon.toml) | bacon 实时监控的任务定义 |
| [`justfile`](justfile) | 全部日常命令的入口 |{% if docker %}
| [`docker.just`](docker.just) | 容器相关命令（被 justfile 可选 import） |
| [`Dockerfile`](Dockerfile) | 多阶段构建 + distroless 运行镜像 |{% endif %}
| [`.config/nextest.toml`](.config/nextest.toml) | 测试运行器配置（含 CI 专用 profile） |
| [`.pre-commit-config.yaml`](.pre-commit-config.yaml) | Git 钩子（pre-commit / commit-msg / pre-push） |
| [`.editorconfig`](.editorconfig) | 跨编辑器的基础排版约定 |
| [`.gitattributes`](.gitattributes) | 入库换行统一、二进制标记、`Cargo.lock` 折叠 |
| [`.vscode/`](.vscode/) | rust-analyzer 配置与推荐插件 |{% if ci == "github" %}
| [`.github/workflows/`](.github/workflows/) | CI：lint / test / deny / msrv / hack / miri / release + 每日安全审计 |
| [`.github/dependabot.yml`](.github/dependabot.yml) | 依赖与 Actions 的自动升级 |{% endif %}{% if ci == "gitlab" %}
| [`.gitlab-ci.yml`](.gitlab-ci.yml) | GitLab CI：lint / test / deny / msrv + tag 触发 release |{% endif %}
{% if ci == "github" %}
## CI

推送和 PR 会触发 [`build.yaml`](.github/workflows/build.yaml)，并行跑这些 job：

- **lint** —— 格式化、拼写、clippy（`-D warnings`）、文档警告
- **test** —— `cargo check` + nextest（CI profile：不 fail-fast、失败重试、输出 JUnit）+ 覆盖率 + doctest
- **deny** —— 依赖的安全公告 / License / 重复版本 / 来源
- **msrv** —— 用 `Cargo.toml` 里声明的最低版本编译一遍（nightly 项目自动跳过）
- **hack** —— 用 cargo-hack 遍历 feature 幂集，防止"单独开某个 feature 编不过"
- **miri** —— 在解释器里跑测试检测未定义行为（**仅 nightly**，stable 项目自动跳过）

打上 `v*` tag 后，在 lint / test / deny / hack 通过的前提下额外跑 **release** job：
用 git-cliff 生成本次的变更说明并创建 GitHub Release。

[`audit.yaml`](.github/workflows/audit.yaml) 每天定时跑一次依赖审计——安全公告是"代码没动风险也会变"的东西，只靠 PR 触发发现不了。

> Miri 比原生慢一到两个数量级，且不支持大多数 FFI / 系统调用。项目一旦引入 C 依赖或做真实 IO，
> 这个 job 会开始失败——那时直接把它从 workflow 里删掉即可，它是可选项。
{% endif %}{% if ci == "gitlab" %}
## CI

推送和 MR 会触发 [`.gitlab-ci.yml`](.gitlab-ci.yml)：

- **lint** —— 格式化、拼写、clippy（`-D warnings`）、文档警告
- **test** —— `cargo check` + nextest + 覆盖率（MR 页面直接显示百分比）+ JUnit 报告
- **deny** —— 依赖的安全公告 / License / 重复版本 / 来源
- **msrv** —— 用声明的最低版本编译一遍（nightly 项目自动跳过）

打上 `v*` tag 时额外跑 **changelog** + **release**，用 git-cliff 生成说明并创建 GitLab Release。
{% endif %}{% if ci == "none" %}
## CI

生成时选择了不带 CI 配置。需要时可以从模板仓库把 `.github/` 或 `.gitlab-ci.yml` 拷回来，
或直接用 `just ci` 在本地跑同一套检查。
{% endif %}
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
