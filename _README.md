# {{ project-name }}
{% if ci == "github" %}
[![build](https://github.com/{{ repo-owner }}/{{ project-name }}/actions/workflows/build.yaml/badge.svg)](https://github.com/{{ repo-owner }}/{{ project-name }}/actions/workflows/build.yaml)
[![audit](https://github.com/{{ repo-owner }}/{{ project-name }}/actions/workflows/audit.yaml/badge.svg)](https://github.com/{{ repo-owner }}/{{ project-name }}/actions/workflows/audit.yaml)
{% elsif ci == "gitlab" %}
[![pipeline](https://gitlab.com/{{ repo-owner }}/{{ project-name }}/badges/main/pipeline.svg)](https://gitlab.com/{{ repo-owner }}/{{ project-name }}/-/pipelines)
[![coverage](https://gitlab.com/{{ repo-owner }}/{{ project-name }}/badges/main/coverage.svg)](https://gitlab.com/{{ repo-owner }}/{{ project-name }}/-/pipelines)
{% endif %}![license](https://img.shields.io/badge/license-{{ license | replace: "-", "--" | replace: " ", "%20" }}-blue)
{% if crate_type == "lib" %}
<!-- 发布到 crates.io 之后把下面两行的注释去掉 -->
<!-- [![crates.io](https://img.shields.io/crates/v/{{ project-name }}.svg)](https://crates.io/crates/{{ project-name }}) -->
<!-- [![docs.rs](https://docs.rs/{{ project-name }}/badge.svg)](https://docs.rs/{{ project-name }}) -->
{% endif %}
{{ description }}

## 快速开始

```bash
git add -A && git commit -m "chore: 从模板初始化项目"   # 生成器只做了 git init

just doctor          # 体检：工具链组件与配套工具是否齐全（会告诉你缺什么、怎么装）
just install-tools   # 安装配套 cargo 工具（首次）
just bootstrap       # 生成 Cargo.lock + 安装 git 钩子（首次）
just ci              # 跑一遍完整检查，确认环境就绪
just dev             # 开始写代码：bacon 盯着文件变化实时重跑 clippy
```

`just` 不带参数会列出全部命令（按用途分组）。

## 项目骨架
{% if crate_type == "lib" %}
```
src/
  lib.rs           公开 API 入口{% if error_handling %}
  error.rs         公开错误类型（thiserror）{% endif %}
tests/
  integration.rs   集成测试：以外部使用者的视角调用公开 API
```
{% else %}```
src/
  lib.rs           业务逻辑都写在这一侧{% if error_handling %}
  error.rs         领域错误类型（thiserror）{% endif %}
  main.rs          可执行入口：初始化日志、错误收口{% if logging %}
  telemetry.rs     日志 / 追踪初始化（tracing）{% endif %}
tests/
  integration.rs   集成测试：以外部使用者的视角调用 lib 的公开 API
```

**为什么二进制项目也有 `lib.rs`**：`main.rs` 里的东西集成测试（`tests/` 是独立
crate）、benchmark、doctest 都够不着，逻辑留在那边就只能靠手工跑一遍程序来验证。
把 `main.rs` 保持薄薄一层、逻辑放进 `lib.rs`，这三样立刻都能用上。

所以 `main.rs` 长起来了，就说明有东西该往 `lib.rs` 挪了。
{% endif %}
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
rustup toolchain install nightly --allow-downgrade --profile minimal --component rustfmt
```
{% else %}
本项目本身就跑在 nightly 上，`+nightly` 指向的是同一个工具链，不需要额外安装。

nightly 是滚动更新的，偶尔会出现某个版本缺 `rustfmt` / `clippy` 组件，或者 clippy 新增的
lint 让 CI 的 `-D warnings` 突然挂掉。前者用 `rustup toolchain install nightly --allow-downgrade`
就能绕过（自动退回到组件齐全的那天）；后者真遇上了就把 `channel` 钉成日期版本，例如
`channel = "nightly-2026-08-01"`——但那之后 `+nightly` 会指向另一个工具链，
需要单独安装，或把命令里的 `+nightly` 去掉。
{% endif %}
### MSRV

`Cargo.toml` 里的 `rust-version` 声明了最低支持版本。它**只是下限，不限制上限**，
用更新的 stable 或 nightly 编译都没问题。
{% if toolchain == "stable" %}
`just msrv` 和 CI 的 msrv job 会真的用那个版本编译一遍来验证声明属实。
{% else %}
`just msrv` 和 CI 的 msrv job 本来会用那个版本编译一遍验证声明属实，但 nightly 项目上
这项检查不适用——代码里可能有 `#![feature(...)]`，那种写法在任何 stable 上都编不过。
它们会自动转去跑 `just nll`，那才是 nightly 项目真正需要的那道兜底。

### nightly 的借用检查器比 stable 宽

2026-08-04 起，nightly 默认启用了新一代借用检查器 **Polonius**，它比 stable 的 NLL
接受更多合法程序。最典型的是「条件返回一个借用，之后再可变借用同一个值」：

```rust
fn get_or_insert(map: &mut HashMap<u32, String>) -> &String {
    if let Some(v) = map.get(&22) {
        return v; // stable 认为这个借用一直活到函数结束
    }
    map.insert(22, String::from("hi")); // 于是这里报 E0502
    &map[&22]
}
```

这段代码在 nightly 上编得过，在 stable 上编不过。

麻烦的地方在于**这个差异没有任何显式标记**：不像 `#![feature(...)]` 那样一眼可见，
它没有属性、没有 lint、连 warning 都没有。于是完全可能在 nightly 上写出一段 stable
编不过的代码而毫无察觉，而 `Cargo.toml` 里的 `rust-version` 依旧写着一个早期版本——
发布成库的话是下游用户先撞上，不发布的话就是哪天想切回 stable 时才发现欠了一堆债。

`just nll` 用同一条 nightly 编译，只把借用检查器换回 NLL（`-Zpolonius=off`），
就地拦下这类代码。CI 的 msrv job 每次都会跑它；本地则在动过生命周期相关的代码之后
手动跑一次就够——它换了 `RUSTFLAGS`，等于一次全量重编，所以刻意没进 `just ci`。

官方计划 2026 年底把 Polonius 推进 stable。到那时：确实有代码靠它才编得过的话，
把 `rust-version` 抬到那一版；随后 `just nll`、CI 里对应的 step 和这一节都可以删掉。
{% endif %}
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
| `cargo-hack` | feature 幂集检查 |
| `typos-cli` | 拼写检查 |
| `taplo-cli` | TOML 格式化与检查（rustfmt 只管 `.rs`） |
| `git-cliff` | 生成 CHANGELOG |
| `bacon` | 后台实时监控 |

### pre-commit

```bash
pipx install pre-commit
just hooks
```

`just hooks` 会装上 `pre-commit`、`commit-msg`、`pre-push` 三类钩子：
提交前跑格式化 / clippy / 拼写检查，提交时校验 commit message 规范，推送前跑全量测试。

### 容器里开发（可选）

[`.devcontainer/`](.devcontainer/) 里有一份 Dev Container 配置，
VS Code 的 Dev Containers 插件或 GitHub Codespaces 可以直接用，
省掉本机装工具链的过程。

## 常用命令

`just` 直接列出全部命令（按用途分组）。

```bash
just                    # 列出所有命令
just doctor             # 环境体检
just bootstrap          # 首次拉起：生成 Cargo.lock + 安装 git 钩子
just check              # 快速检查编译
just run -- --help      # 运行程序（仅 bin 项目），-- 后的参数透传给程序
just fmt                # 格式化 .rs（nightly rustfmt）与 .toml（taplo）
just fix                # clippy --fix 自动修复 + 格式化
just dev                # bacon 实时监控
just doc                # 生成并打开 API 文档
just bench              # 跑 benchmark
just flamegraph         # 采样生成火焰图（仅 bin 项目）
just clean              # 清理编译产物与本地报告

just lint               # 格式化检查（.rs + .toml）+ clippy + typos + 文档警告
just test               # 运行测试（含 doctest）
just coverage           # 生成覆盖率报告 lcov.info
just coverage-html      # HTML 覆盖率报告并打开
just audit              # cargo deny check
just hack               # feature 幂集检查
just msrv               # 验证 MSRV 能编译（nightly 项目自动转去跑 nll）
just nll                # 用 stable 的借用检查器编一遍（仅 nightly 项目有意义）
just miri               # 在解释器里跑测试检测未定义行为（仅 nightly，有 tokio 时自动跳过）
just ci                 # 本地跑一遍 CI 的主要检查（lint / test / audit）

just unused             # 找出没用到的依赖（cargo-machete）
just semver             # 公开 API 破坏性变更检查（仅纯库项目）

just update             # 升级 Cargo.lock 并重新审计
just outdated           # 列出可升级的依赖

just changelog          # 刷新 CHANGELOG.md
just release minor      # 发版预演：跑全套检查 + 干跑一遍，不改动任何东西
just release-execute minor  # 真正发版：抬版本号 + CHANGELOG + tag + 推送
                            # （紧接在 release 之后跑，不再重复跑一遍检查）
```
{% if docker and crate_type == "bin" %}
容器相关命令来自 [`docker.just`](docker.just)（根 justfile 用 `import?` 可选加载）：

```bash
just docker-build       # 构建镜像（多阶段 + distroless，同时打 latest 与版本号 tag）
just docker-run -- --help   # 运行镜像
just docker-inspect     # 用 dive 看分层体积
just docker-scan        # 用 trivy 扫已知漏洞
just docker-clean       # 删除本地镜像
```

镜像里的二进制是用 [cargo-auditable](https://github.com/rust-secure-code/cargo-auditable)
构建的：依赖清单（名字 + 版本）被编进二进制的一个专用 section，于是
`just docker-scan` 的 trivy、以及 `cargo audit bin <二进制>` 都能直接对着**产物**查 CVE。
没有它，trivy 扫这个镜像只看得到 distroless 基础层，你自己那一整棵 Rust 依赖树对它完全隐形。
体积代价约 1%，运行时零开销；不需要就把 `Dockerfile` 里那一层删掉。
{% endif %}
`just ci` 包含 `lint` / `test` / `audit` 三项。其中 `lint` 和 CI 的 lint job 严格对齐，
**含 `cargo doc` 的文档警告检查**——`[workspace.lints.rustdoc]` 里 `bare_urls`、
`invalid_html_tags` 这些都只是 `warn`，本地不跑 `cargo doc` 就看不见，
推上去才会在 CI 的 `RUSTDOCFLAGS="-D warnings"` 上挂掉。

`unused`、`semver`、`hack`、`msrv`、`nll`、`miri` 刻意留在外面手动跑：第一个对宏里用到的依赖会误报，
第二个需要和已发布版本联网比对，第三个要额外装 cargo-hack、feature 多起来还会变慢，
第四个会 `rustup toolchain install` 往你机器上装一整条工具链，
第五个换了 `RUSTFLAGS` 等于一次全量重编，第六个比原生慢一到两个数量级——
都不适合塞进「随手跑一下」的命令里。

除 `unused` 外，它们在两套 CI 里都有对应的 job（`semver` 只对纯库项目生效，
`miri` 只在 nightly 上跑）。`unused` 刻意**没有**进任何 CI：误报率高的检查一旦当上门禁，
结果只会是所有人都学会忽略它。需要时手动跑 `just unused`。

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
| `profiling` | 继承 release 但保留符号，火焰图才有可读函数名：`just flamegraph` |
| `bench` | 继承 release 且保留符号，保证 benchmark 测的是优化后的代码 |

`Cargo.toml` 末尾还注释着两项按需打开的配置：`build-override`（加速 proc-macro 编译）
和 `overflow-checks`（release 下也检查整数溢出，账务 / 协议解析类项目建议打开）。
{% if async_runtime %}
### 异步运行时

项目已引入 [tokio](https://tokio.rs/)（`rt-multi-thread` + `macros`）。{% if crate_type == "lib" %}
它在 `[dev-dependencies]` 里：库这一侧只有 `#[tokio::test]` 用得到它，
放进 `[dependencies]` 等于让每个使用者都白拉一份 tokio。真要在库里跑异步逻辑时再挪过去
——但**不要**在库里装 runtime，起不起 runtime 是应用的决定。{% else %}
入口是 `#[tokio::main]`。{% endif %}

同时 [`clippy.toml`](clippy.toml) 里启用了 `disallowed-types` / `disallowed-methods`：
用到 `std::fs` / `std::process` 这类**阻塞** API 会被拦下（CI 是 `-D warnings`，
直接构建失败）——一次同步 `read` 就足以把 runtime 的一个 worker 线程钉死，
请改用 `tokio::fs` 对应项。

⚠️ 这条禁令**不区分 async 上下文**：clippy 看不出一处调用是不是在 `async fn` 里，
所以同步代码、测试、`build.rs` 里的 `std::fs` 一样会被拦。
确有必要时在那一处写 `#[expect(clippy::disallowed_types, reason = "...")]` 说明原因——
用 `expect` 而不是 `allow` 是本模板的约定（`clippy::allow_attributes` 在盯着）：
等哪天那处代码改掉、lint 不再触发时，`expect` 会反过来提醒你把压制项删掉。
{% endif %}{% if error_handling %}
### 错误处理
{% if crate_type == "lib" %}
[`src/error.rs`](src/error.rs) 里用 [thiserror](https://docs.rs/thiserror) 定义了公开错误类型
`Error` 与 `Result<T>` 别名，并从 `lib.rs` 重新导出。

库只用 thiserror、不用 anyhow，这是有意的：库抛 `anyhow::Error` 等于告诉调用方
「出错了，但我不告诉你是什么错」，对方除了打印之外什么都做不了。
`Error` 上标了 `#[non_exhaustive]`，以后新增变体不构成破坏性变更。
{% else %}
两层分工，[`src/error.rs`](src/error.rs)（属于 lib 那一侧）与 `main.rs` 各管一段：

- **库层**用 [thiserror](https://docs.rs/thiserror) 定义**具体**错误（`Error::EmptyName`），
  调用方可以 `match` 之后分别处理——该重试的重试，该降级的降级；
- **`main`** 用 [anyhow](https://docs.rs/anyhow) 收口，`.context("...")` 补充上下文后统一上报。

`main.rs` 里那行 `{{ crate_name }}::greet(&name).context("...")?` 就是分界线：
左边是可以 `match` 的具体错误，右边开始是「打印给人看」的 anyhow。

只有 anyhow 的项目，在需要「按错误类型决定要不要重试」时会非常难受；
全都手写 enum 又太啰嗦。两者搭配是应用层的常见解法。
{% endif %}{% endif %}{% if logging and crate_type == "bin" %}
### 日志

[`src/telemetry.rs`](src/telemetry.rs) 用 [tracing](https://docs.rs/tracing) +
`tracing-subscriber` 初始化全局 subscriber：

- 过滤规则运行时可调：`RUST_LOG=warn,{{ crate_name }}=debug`，不必重新编译；
- 日志写 **stderr**，stdout 留给程序真正的输出，管道和重定向才不会串味——
  `main.rs` 里的 `println!` 是程序输出，`tracing::info!` 是日志，各走各的，
  所以把日志级别调到 `warn` 也不会把程序的结果一起吞掉；
- 过滤表达式写错、或 `RUST_LOG` 被设成空串时，退回 `main.rs` 里
  `telemetry::init("info")` 给的默认级别，而不是得到一个「进程正常启动、
  却一条日志都不打」的空 filter；
- `RUST_LOG` 写成一个裸词（`RUST_LOG=inof`）时会提示一句——按 `EnvFilter` 的语法
  裸词是**目标名**不是级别，它解析得**成功**，于是默认指令失效、日志一条都不打，
  这一类 `EnvFilter` 自己不会出声。

要输出 JSON 给日志采集系统、或者接 OpenTelemetry，文件末尾的注释里写了怎么改。
{% endif %}
## 项目里的各个配置文件

| 文件 | 作用 |
| --- | --- |
| [`rust-toolchain.toml`](rust-toolchain.toml) | 固定工具链版本与组件 |
| [`rustfmt.toml`](rustfmt.toml) | 格式化规则（含 unstable 选项，走 nightly） |
| [`clippy.toml`](clippy.toml) | Clippy 行为配置（lint 开关在 `Cargo.toml` 的 `[workspace.lints]`） |
| [`deny.toml`](deny.toml) | 依赖的安全公告 / License / 重复版本 / 来源审计 |
| [`.taplo.toml`](.taplo.toml) | TOML 格式化规则（rustfmt 只管 `.rs`，`.toml` 归 taplo） |
| [`.typos.toml`](.typos.toml) | 拼写检查的词表与排除规则 |
| [`cliff.toml`](cliff.toml) | git-cliff 生成 CHANGELOG 的模板与分组规则 |
| [`release.toml`](release.toml) | cargo-release 的发版流程配置 |
| [`bacon.toml`](bacon.toml) | bacon 实时监控的任务定义 |
| [`justfile`](justfile) | 全部日常命令的入口 |{% if docker and crate_type == "bin" %}
| [`docker.just`](docker.just) | 容器相关命令（被 justfile 可选 import） |
| [`Dockerfile`](Dockerfile) | 多阶段构建 + distroless 运行镜像 |{% endif %}
| [`.config/nextest.toml`](.config/nextest.toml) | 测试运行器配置（含 CI 专用 profile 与测试分组示例） |
| [`.cargo/config.toml`](.cargo/config.toml) | cargo 项目级配置：网络重试、链接器 / 并行前端 / 镜像源的开关都收在这里 |
| [`.pre-commit-config.yaml`](.pre-commit-config.yaml) | Git 钩子（pre-commit / commit-msg / pre-push） |
| [`.editorconfig`](.editorconfig) | 跨编辑器的基础排版约定 |
| [`.gitattributes`](.gitattributes) | 入库换行统一、二进制标记、`Cargo.lock` 折叠 |
| [`.devcontainer/`](.devcontainer/) | Dev Container / Codespaces 配置 |{% if ci == "github" %}
| [`.github/workflows/`](.github/workflows/) | CI（build / release / audit） |
| [`.github/dependabot.yml`](.github/dependabot.yml) | 依赖自动升级：cargo / actions{% if docker and crate_type == "bin" %} / docker 基础镜像{% endif %} |{% endif %}{% if ci == "gitlab" %}
| [`.gitlab-ci.yml`](.gitlab-ci.yml) | GitLab CI：lint / test / deny / hack / msrv / semver / miri + tag 触发 release |{% endif %}
{% if ci == "github" %}
## CI

推送和 PR 触发 [`build.yaml`](.github/workflows/build.yaml)，并行跑这些 job：

- **detect** —— 探测仓库里有哪些 target，供下面的 job 做条件判断（几秒钟）
- **lint** —— 格式化（`.rs` 走 rustfmt、`.toml` 走 taplo）、拼写、clippy（`-D warnings`）、文档警告
- **test** —— `cargo check` + nextest（CI profile：不 fail-fast、失败重试、输出 JUnit）+ 覆盖率 + doctest
- **deny** —— 依赖的安全公告 / License / 重复版本 / 来源
- **workflows** —— 用 [zizmor](https://docs.zizmor.sh/) 审计 workflow 的**安全性**（脚本注入、
  过宽权限、缓存投毒），再用 [actionlint](https://github.com/rhysd/actionlint) 查**正确性**
  （表达式写错、不存在的 job 依赖、`run:` 里的 shell 语法）——两者不重叠
- **msrv / nll** —— stable 项目：用 `Cargo.toml` 里声明的最低版本编译一遍；
  nightly 项目：改用 `-Zpolonius=off` 编一遍，拦下只有新借用检查器才编得过的代码
- **hack** —— 遍历 feature 幂集，防止「单独开某个 feature 编不过」
- **semver** —— 以上一个 tag 为基线检查公开 API 破坏性变更（仅**纯库**项目，没有 tag 时跳过；
  二进制项目的 `src/lib.rs` 是自用的内部库，不对外承诺 API）
- **miri** —— 在解释器里跑测试检测未定义行为（**仅 nightly**，stable 项目自动跳过）
- **docker** —— 构建一次容器镜像确认 Dockerfile 没坏（仅选了 Docker 的项目；只构建不推送）

打 `v*` tag 触发 [`release.yaml`](.github/workflows/release.yaml)：

- **verify** —— 把 tag 指向的 commit 从零验证一遍，并核对 tag 与 `Cargo.toml` 版本一致
- **github-release** —— git-cliff 生成变更说明并创建 Release
- **binaries** —— 五个目标平台（Linux musl x64/arm64、macOS x64/arm64、Windows x64）
  交叉编译、打包、生成 sha256 并挂到 Release 上（仅 bin 项目）。
  再往上一层是**构建来源证明**（SLSA provenance，Sigstore 签名，`gh attestation verify` 可验）：
  校验和只能证明「文件没被改过」，证明回答的是「它是谁造的」——**默认关闭**，
  需要在仓库 Variables 里加 `ATTEST_BUILD_PROVENANCE=true`（私有仓库需要 GitHub Enterprise）
- **crates-io** —— 用 crates.io 的 Trusted Publishing（OIDC，无需长期 token）发布，
  **默认关闭**，需要在仓库 Variables 里加 `PUBLISH_TO_CRATES_IO=true`

[`audit.yaml`](.github/workflows/audit.yaml) 每天定时跑一次依赖审计——
安全公告是「代码没动风险也会变」的东西，只靠 PR 触发发现不了。

两点值得注意：

- **CI 与发布分成两个 workflow**，因为发布流程刻意不使用编译缓存。缓存是可写的，
  一旦发布产物建立在缓存之上，「污染缓存」就等价于「污染 release 二进制」。
- **按 target 裁剪的 job（semver / binaries / docker）一律靠 `detect` 传出的 outputs 判断**，
  而不是在 job 级写 `if: hashFiles(...)`。job 级的 `if:` 在 checkout 之前就求值，
  那时工作区还是空的，hashFiles 恒为空串——条件永远不成立，job 被静默跳过，不报任何错。
- **第三方 action 全部用 commit hash 钉死**（后面的 `# vX.Y.Z` 是给人看的）。
  tag 是可变的，上游账号一旦被攻破，把 `v3` 指向恶意提交就能直接进你的 CI。
  hash 由 dependabot 每周自动更新。

> Miri 比原生慢一到两个数量级，且不支持大多数 FFI / 系统调用。项目一旦引入 C 依赖或做真实 IO，
> 这个 job 会开始失败——那时直接把它从 workflow 里删掉即可，它是可选项。
{% endif %}{% if ci == "gitlab" %}
## CI

推送和 MR 会触发 [`.gitlab-ci.yml`](.gitlab-ci.yml)：

- **lint** —— 格式化（`.rs` 走 rustfmt、`.toml` 走 taplo）、拼写、clippy（`-D warnings`）、文档警告
- **test** —— `cargo check` + nextest + 覆盖率（MR 页面直接显示百分比）+ JUnit 报告
- **deny** —— 依赖的安全公告 / License / 重复版本 / 来源
- **hack** —— feature 幂集检查
- **msrv** —— 用声明的最低版本编译一遍；nightly 项目改成用 `-Zpolonius=off` 编一遍，
  拦下只有新借用检查器才编得过的代码
- **semver** —— 以上一个 tag 为基线检查公开 API 破坏性变更（仅**纯库**项目，没有 tag 时跳过）
- **miri** —— 在解释器里跑测试检测未定义行为（**仅 nightly**，检测到 tokio 时自动跳过）

打 `v*` tag 时额外跑 **verify-tag**（从零验证 + 核对版本号）、**changelog**、
**build-binary**、**release**。

> 依赖的安全公告是「代码没动风险也会变」的东西，只靠 MR 触发发现不了。
> 建议到 CI/CD → Schedules 配一条每日定时流水线，专门跑 `deny`
> （GitHub 那边对应的是 `audit.yaml`）。

配套 cargo 工具用 cargo-binstall 下预编译二进制，并单独缓存 `.cargo-home/bin/`：
第一条流水线之后就不会再花时间装工具了。
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

## License

协议在生成项目时选定，对应的许可证文件在仓库根目录：
单协议是 `LICENSE`，双协议（MIT OR Apache-2.0）则是 `LICENSE-MIT` 与 `LICENSE-APACHE`。
具体取值见 `Cargo.toml` 的 `license` 字段。
