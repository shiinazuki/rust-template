# rust-template

一个开箱即用的 Rust 项目模板，通过 [cargo-generate](https://cargo-generate.github.io/cargo-generate/) 生成。

生成出来的项目自带：统一的格式化 / Clippy 规则、测试与覆盖率、依赖安全与 License 审计、
拼写检查、Git 钩子、CHANGELOG 自动生成、发版与跨平台二进制分发流程，以及一套完整的 CI；
按需还能生成日志、错误处理的代码骨架。

> 这份 README 是**模板仓库自己的说明**，不会进入生成的项目。
> 生成项目里的 README 来自 [`_README.md`](_README.md)。

## 快速开始

先装 cargo-generate（需要 0.24 及以上，旧版用同一条命令升级）：

```bash
cargo install --locked cargo-generate
```

生成一个二进制项目：

```bash
cargo generate --git https://github.com/shiinazuki/rust-template --name my-app
```

生成一个库项目：

```bash
cargo generate --git https://github.com/shiinazuki/rust-template --name my-lib --lib
```

生成完成后：

```bash
cd my-app
git add -A && git commit -m "chore: 从模板初始化项目"
just doctor          # 体检工具链与配套工具
just install-tools   # 装齐配套 cargo 工具
just bootstrap       # 生成 Cargo.lock + 启用 git 钩子
just ci              # 跑一遍完整检查
```

> cargo-generate 会在目标目录 `git init`，但不会替你提交，生成完之后所有文件都还是
> untracked。首次提交要自己来：`just changelog` 这类依赖 git 历史的命令在没有任何提交时会报错。

## 生成时会问什么

交互式会依次询问下面几项；也可以全部用 `--define key=value` 在命令行给定，实现非交互生成。

| 变量 | 说明 | 可选值 / 默认 |
| --- | --- | --- |
| `description` | 项目简介，写入 `Cargo.toml` 的 `description` | 默认 `A Rust project` |
| `repo-owner` | 仓库所有者（GitHub / GitLab 的用户名或组织名），用于拼 `repository` 字段 | 允许字母数字与 `._/-`，GitLab 子组写 `group/subgroup` |
| `toolchain` | 写入 `rust-toolchain.toml` 的 channel | `stable`（默认）/ `nightly` |
| `license` | 开源协议 | `MIT`（默认）/ `Apache-2.0` / `MIT OR Apache-2.0` |
| `ci` | CI 平台 | `github`（默认）/ `gitlab` / `none` |
| `docker` | 是否生成 Dockerfile 与容器命令 | `false`（默认）/ `true` |
| `async_runtime` | 是否引入 tokio 并开启阻塞 API 禁令 | `false`（默认）/ `true` |
| `error_handling` | 是否生成错误处理骨架 | `true`（默认）/ `false` |
| `logging` | 是否生成日志骨架（tracing），仅 bin | `false`（默认）/ `true` |

> 没有单独的「托管平台」变量：`repository` 的域名由 `ci` 推导（`gitlab` → `gitlab.com`，
> 其余 → `github.com`）。`ci = none` 又托管在 GitLab 时，生成完手工改一下 `Cargo.toml`
> 的 `repository` 即可。

项目名与作者不在上表里，它们是 cargo-generate 的内置变量，不需要再定义一遍：

| 内置变量 | 来源 |
| --- | --- |
| `project-name` | `--name` 参数或交互输入 |
| `crate_name` | 由 `project-name` 自动转成 snake_case |
| `crate_type` | `--bin`（默认）/ `--lib` |
| `authors` / `username` | 从 git / cargo 配置里读出来 |

完整列表见[官方文档](https://cargo-generate.github.io/cargo-generate/templates/builtin_placeholders.html)。

非交互生成的完整例子：

```bash
cargo generate --git https://github.com/shiinazuki/rust-template \
  --name my-app --bin --silent \
  --define description="一个命令行工具" \
  --define repo-owner=shiinazuki \
  --define toolchain=stable \
  --define license="MIT OR Apache-2.0" \
  --define ci=github \
  --define docker=true \
  --define async_runtime=true \
  --define error_handling=true \
  --define logging=true
```

> `--silent` 模式下所有占位符都必须给全，漏一个就会直接失败。

### bin 与 lib 的差异

`--bin`（默认）和 `--lib` 决定生成哪套源码骨架，由 `cargo-generate.toml` 里的
`[conditional.'crate_type == ...']` 控制：

| 项目 | `--bin` | `--lib` |
| --- | --- | --- |
| 源码 | `src/lib.rs` + `src/main.rs` | `src/lib.rs` |
| 集成测试 | `tests/integration.rs` | `tests/integration.rs` |
| `missing_docs` lint | `allow` | `warn`（强制公开 API 写文档） |
| `error_handling` | thiserror 定义在 lib，`main` 用 anyhow 收口 | 只有 thiserror，公开导出 |
| `logging` | 按开关生成 `src/telemetry.rs` | 始终不生成 |
| Docker 相关文件 | 按 `docker` 开关 | 始终不生成（库没有可执行入口） |
| docs.rs 元数据 | 无 | `[package.metadata.docs.rs]` + `unexpected_cfgs` 登记 `docsrs` |
| CI 的 semver job | 跳过 | 以上一个 tag 为基线检查 API 破坏性变更 |
| `just flamegraph` | 可用 | 跳过（没有 bin target） |

bin 项目也有 `src/lib.rs`：`main.rs` 只做参数解析、日志初始化和错误收口，业务逻辑全在
lib 一侧，集成测试、benchmark、doctest 都只能 `use` 到 lib target 导出的 `pub` 项。
配套地，`just semver` 与 CI 的 semver job 只在纯库项目上跑，`missing_docs` 对 bin 仍是
`allow`；要同时对外发布库和命令行时，把这两处判断里的 `src/main.rs` 条件删掉即可。

`logging` 对库不生效：安装全局 tracing subscriber 是应用的职责。库里想发日志，
只加 `tracing` 依赖用它的宏即可。选了它去生成库时，post-script 会打印一行说明。

### 模板刻意不提供的两样东西

**开源社区文件**（`SECURITY.md`、`CODE_OF_CONDUCT.md`、`CONTRIBUTING.md`、
issue / PR（MR）模板、`CODEOWNERS`）只在「项目公开 + 期待外部贡献者」时才有价值，
真要开源时从别的项目拷一份过来即可。

**命令行参数骨架（clap）**：clap 的用法随项目差别太大（子命令、配置文件合并、shell 补全、
环境变量回落），模板给的 derive 样板留下来只会被推倒重写。要用的时候：

```bash
cargo add clap --features derive,env
```

参数定义单独放进 `src/cli.rs`（derive 一个 `Cli` 结构体，测试里可以直接构造），
`main.rs` 里只留 `let args = Cli::parse();` 一行。

### 功能开关的实际效果

| 开关 | `true` / 选中时 | `false` / 未选时 |
| --- | --- | --- |
| `ci = github` | 保留 `.github/`（workflows + dependabot） | 其余取值下整个 `.github/` 被 ignore |
| `ci = gitlab` | 保留 `.gitlab-ci.yml` | 其余取值下它被 ignore |
| `docker` | 生成 `Dockerfile`、`.dockerignore`、`docker.just` | 三者都不生成 |
| `async_runtime` | 加 tokio、入口变 `#[tokio::main]`、`clippy.toml` 启用阻塞 API 禁令 | 保持同步骨架，禁令以注释形式留在 `clippy.toml` |
| `error_handling` | 生成 `src/error.rs`，加 thiserror（bin 再加 anyhow），`main` 返回 `anyhow::Result<()>` | 不生成，`main` 返回 `io::Result<()>` |
| `logging` | 生成 `src/telemetry.rs`，加 tracing，`main` 里初始化 | 不生成，`main` 只把结果写到 stdout |

任何一个会加依赖的开关被打开时，post-script 都会删掉模板自带的 `Cargo.lock`——那份 lock
只锁了根 crate 一个包，留着必然过期，而 CI 全程用 `--locked`。

`docker.just` 通过根 `justfile` 里的 `import? 'docker.just'` 可选加载，没生成这个文件时
`import?` 会静默跳过（普通 `import` 则会报错）。

### License 文件的处理

模板里同时放着 `LICENSE-MIT` 和 `LICENSE-APACHE`，生成后由
[`post-script.rhai`](post-script.rhai) 按选择收拾：

- 选单一协议 → 删掉另一个，剩下的改名成 `LICENSE`
- 选 `MIT OR Apache-2.0` → 两个都保留（Rust 生态双协议的标准做法）

## 模板里有什么

生成项目会拿到这些配置文件：`rust-toolchain.toml`、`rustfmt.toml`、`clippy.toml`、
`deny.toml`、`.taplo.toml`、`.typos.toml`、`cliff.toml`、`release.toml`、`bacon.toml`、
`justfile`、`.config/nextest.toml`、`.cargo/config.toml`、`CLAUDE.md`、`.githooks/`、
`.devcontainer/`、`.editorconfig`、`.gitattributes`、`.gitignore`；按开关追加
`Dockerfile` / `.dockerignore` / `docker.just`，以及 `.github/`（build / release / audit
三条 workflow + dependabot）或 `.gitlab-ci.yml`。

逐个文件的作用见 [`_README.md`](_README.md) 的「项目里的各个配置文件」一节——那份表会跟着
生成的项目走，改说明只改那一处。更细的取舍写在各文件自己的注释里。

模板自身的机制文件：

| 文件 | 作用 |
| --- | --- |
| `cargo-generate.toml` | 占位符、`exclude` / `ignore`、按开关裁剪的 `conditional` |
| `post-script.rhai` | 生成后收尾：整理 LICENSE、换上 README、按需删 `Cargo.lock` |
| `_README.md` | 生成项目要用的 README，post-script 会把它改名成 `README.md` |

只属于模板仓库、不会进入生成项目的文件（在 `cargo-generate.toml` 的 `ignore` 里）：

| 文件 | 作用 |
| --- | --- |
| `README.md` | 就是本文件（严格说它在 `exclude` 而非 `ignore`，由 post-script 删掉后让 `_README.md` 顶上） |
| `CHANGELOG.md` | 模板自己的变更记录 |
| `template.just` | 模板维护命令（`just smoke` 等） |
| `scripts/smoke.sh` | 自测脚本：矩阵生成项目并逐个跑检查 |
| `.github/workflows/template-ci.yaml` | 模板自己的 CI |

## 维护这个模板

改模板前先过一遍这几条约束，下面各有一节：

- 模板仓库里跑不了 cargo，验证一律走 `just smoke`
- 源码里不要把包名写进宏参数（rustfmt 会折行）
- 花括号属于别的模板语言的文件要进 `exclude`
- TOML / YAML 里的 liquid 标签必须锚在注释行行尾
- 二进制资源必须显式 `exclude`，但 `LICENSE*` 不能
- 钩子里不要用 `system::command`

### 在模板仓库里跑不了 cargo

模板仓库根目录的 `rust-toolchain.toml` 里 channel 是 `{{ toolchain }}`，
`Cargo.toml` 里包名是 `{{ project-name }}`，两者都不是合法取值，所以在这个目录下
任何 cargo / rustup 命令都会直接报错：

```
error: custom toolchain '{{ toolchain }}' specified in override file ... is not installed
```

这是预期行为。`cargo generate` 本身也是 cargo 的子命令，所以在模板目录里执行
`cargo generate --path .` 同样会报错，自测脚本因此先 `cd` 到临时目录再用绝对路径指回模板。
`.githooks/pre-commit` 与 `.githooks/pre-push` 里都带了
`grep -qF '{{ project-name }}' Cargo.toml` 的守卫，在模板仓库里会自动跳过。

### 改完模板后的自测

这是唯一可靠的验证方式，而且已经脚本化了：

```bash
just smoke          # 10 组：覆盖每个开关的开与关，含 2 组 nightly、3 种协议
just smoke-full     # 19 组：bin 的 3 个源码开关全排列 + lib + nightly
                    #        + 三种 CI 平台 + 协议
just smoke-keep     # 跑完保留生成的项目，方便进去手工看
just template-lint  # 检查模板仓库自身：taplo + typos + zizmor + actionlint + shellcheck + lychee
```

每个组合会依次验证（逐条的实现和条件见 `scripts/smoke.sh`）：

- 能不能生成（liquid 语法、conditional 配置）
- `cargo +nightly fmt --check` —— 生成的代码必须开箱就是 rustfmt 干净的
- `cargo clippy -- -D warnings` —— 和 CI 同样的严格度
- 测试（nextest）与 doctest
- `RUSTDOCFLAGS="-D warnings" cargo doc` —— 文档警告，编译 / clippy / 测试都看不见它
- `cargo deny check` —— 某个开关引入的依赖可能带着不在白名单里的协议
- 留下来的 `Cargo.lock` 与 `Cargo.toml` 对得上（`cargo metadata --locked`）
- `justfile` 能被 just 解析
- README 里的 Markdown 表格没有被条件块裁出的空行截断
- 生成项目里的 TOML 都是合法 TOML
- `taplo fmt --check` —— 排版也要合规
- 没有残留未渲染的 `{{ }}` / `{% %}` —— 变量改名漏一处、`{% raw %}` 忘了配对就是这个症状，
  而它多半藏在注释和文档里，编译 / clippy / 测试都发现不了
- 文件清单与开关对得上 —— 逐个断言每个开关该生成、不该生成的文件
  （见 `scripts/smoke.sh` 的 `assert_layout`），并核对 README 的 license 徽章 URL
- `docker build` —— 默认关闭，`SMOKE_DOCKER=1` 打开（容器里从零编译，很慢）

CI 上由 [`.github/workflows/template-ci.yaml`](.github/workflows/template-ci.yaml)
跑同一个脚本：push / PR 跑默认矩阵，每周一定时跑完整矩阵——上游的 clippy、rustfmt、
依赖都在动，模板没改也可能某天就生成不出能过 CI 的项目了。

### 源码模板里不要把包名写进宏参数

rustfmt 限制调用参数列表宽度的是 `fn_call_width`（默认 60），不是 `max_width`（100）。
下面这行在包名短的时候好好的，包名一长就会被折成三行，生成出来的项目开箱过不了 `fmt --check`：

```rust
assert_eq!({{ crate_name }}::greet("world"), "Hello, world!");
```

对策是先绑到一个短变量，再让宏只碰这个变量：

```rust
let msg = {{ crate_name }}::greet("world");
assert_eq!(msg, "Hello, world!");
```

集成测试里统一走一条 `use {{ crate_name }}::{...};`，之后所有调用都是短名字
（导入顺序按 rustfmt 的规则是大写在前：`{Error, add, greet}`）。
自测矩阵里的 `a-deliberately-long-package-name-for-rustfmt` 一组专盯这件事。

### Liquid 与其它模板语法的冲突

模板文件默认会被 Liquid 引擎处理，`{{ }}` 和 `{% %}` 会被当成占位符替换掉。
下面这些文件里的花括号属于别的模板语言，必须写进 `cargo-generate.toml` 的
`exclude` 列表（文件照常复制，只是不做变量替换）：

| 文件 | 里面的花括号属于 |
| --- | --- |
| `cliff.toml` | git-cliff 的 Tera 模板 |
| `.github/workflows/**` | GitHub Actions 的 `${{ ... }}` |
| `justfile` / `docker.just` / `template.just` | just 自己的 `{{ 变量 }}` |
| `release.toml` | cargo-release 的 `{{version}}` |
| `.githooks/**` | 用来识别模板仓库的 `{{ project-name }}` 字面量 |
| `scripts/**` | shell 的 `${...}` |
| `.gitlab-ci.yml` | GitLab CI 的 `$VARIABLE` 与规则表达式 |
| `README.md` | 就是本文件，里面有大量占位符示例 |

⚠️ 改动这份 exclude 列表时，记得同步 `scripts/smoke.sh` 里「占位符残留」那条检查的
`--exclude` 参数——它靠排除这些文件来判断还有没有该渲染却没渲染的占位符。

exclude 的是 `.github/workflows/**` 而不是 `.github/**`：`.github/dependabot.yml` 里的
docker 那一段是按 `docker` 开关条件生成的，需要被渲染。整个目录一刀切的话，没生成
Dockerfile 的项目会被 dependabot 每周报一次 `No Dockerfiles nor Kubernetes YAML found in /`。

`exclude` 与 `ignore` 是两回事：

- `exclude` —— 文件会进入生成的项目，只是不做变量替换
  （其它模板引擎里叫 `copy_without_render`，cargo-generate 没有这个键，`exclude` 就是它）
- `ignore` —— 文件不会进入生成的项目

两者的匹配都发生在 `.liquid` 后缀被去掉之后，所以 `exclude = ["README.md"]` 会连
`README.md.liquid` 一起排除掉。本模板因此不用 `.liquid` 后缀，而是把生成项目的 README
命名为 `_README.md`，由 `post-script.rhai` 在生成后改名顶替。

### TOML / YAML 文件里的 liquid 标签必须锚在注释行

`Cargo.toml` / `clippy.toml` 里的条件块一律写成这样——标签挂在 TOML 注释行的行尾：

```toml
# 这里是版本目录{% if async_runtime %}
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
# feature 在此统一收口{% endif %}
```

这样文件在模板仓库里同时也是合法 TOML：编辑器不报错，`taplo fmt --check` 与自测脚本的
TOML 合法性检查照常工作。反例是单独占一行的裸 `{%- if ... %}`，或把标签挂在值的行尾
（`rustdoc-args = [...]{% endif %}`），两者都会让文件变成非法 TOML。

`.github/dependabot.yml` 同理（它是 `.github/` 下唯一需要渲染的文件）：`{% if %}` 挂在
`#` 注释行的行尾，`{% endif %}` 挂在一个不带引号的标量后面（`include: scope{% endif %}`
仍是合法的 plain scalar）。挂到 `- "*"` 这种带引号的值后面会让 YAML 直接解析失败：

```
found character '%' that cannot start any token
```

条件为假时留下的那几行注释要能独立读通——它们会原样留在生成的项目里。

### 二进制文件必须显式 exclude

cargo-generate 不会自动豁免二进制内容，图标、字体、测试夹具被 Liquid 处理过就会损坏。
`cargo-generate.toml` 里预置了一组通配（`*.png` / `*.woff2` / `assets/**` / `fixtures/**` 等），
加二进制资源时先确认它落在这些模式内。

⚠️ 反过来，`LICENSE-MIT` / `LICENSE-APACHE` 里的 `{{ authors }}` 和
`{{ "now" | date: "%Y" }}` 是有意要被渲染的，不能加进 exclude。

### 钩子里不要用 `system::command`

Rhai 的 `system::command` 受 cargo-generate 的命令确认机制管辖：交互式生成时每执行一条
外部命令都会弹一次确认，`--silent` 时直接报错中止：

```
Cannot prompt for system command confirmation in silent mode.
Use --allow-commands if you want to allow the template to run system commands
```

也就是说钩子里只要出现一条 `system::command`，所有非交互生成都必须额外带 `--allow-commands`。
本模板因此把「检查工具链组件」挪到了 `just doctor`，`post-script.rhai` 只做纯文件操作。
`post` 钩子运行时文件还在临时目录，所以钩子里 `git init` 也没有意义。

### 依赖的上游版本

四处需要跟进：

| 位置 | 形式 | 谁来更新 |
| --- | --- | --- |
| workflow 里的 action | commit hash + `# vX.Y.Z` 注释 | dependabot 每周一提 PR，模板仓库与生成项目都一样 |
| workflow 里的 `ACTIONLINT_VERSION` | 版本号 + 两个架构的 sha256 | 手动，`build.yaml` 与 `template-ci.yaml` 两处一起改 |
| `.gitlab-ci.yml` 的 release job 镜像 | `gitlab-org/cli` 的版本 tag | 手动 |
| `Cargo.toml` 里可选依赖的版本 | caret 版本 | 手动，改动很少 |

`.github/dependabot.yml` 会跟着模板一起进生成项目，但它同时也管着模板仓库自己，
所以模板这边的 action 版本一样有 dependabot 盯着，不必手动跟。`just template-update`
只是在你想手工更新时告诉你怎么查 hash。

⚠️ 手工改过 action 版本之后，dependabot 那条尚未合并的 PR 会变成冲突状态，而且它的目标
版本可能已经旧于你刚写进去的版本——那种 PR 直接关掉（`@dependabot close`），别合，
否则是降级。

⚠️ dependabot 的 **cargo 规则在模板仓库自身上必然失败**，Dependabot 页面上每周会看到一条
错误，这是预期行为：模板的 `Cargo.toml` 里 `name = "{{ project-name }}"` 不是合法包名，
`cargo metadata` 直接报 `invalid character` 退出。这条规则要留给生成出来的项目用，而
`dependabot.yml` 是同一份文件，没法只在模板这边关掉，忽略那条错误即可。

action 用 hash 而不是 tag，因为 tag 可变：上游账号被攻破就能把 `v3` 指向恶意提交
（2025 年 tj-actions 事件）。代价是不会自动跟进上游修复，所以 dependabot 的
`github-actions` 规则不是可选项。

## License

MIT OR Apache-2.0
