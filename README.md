# rust-template

一个开箱即用的 Rust 项目模板，通过 [cargo-generate](https://cargo-generate.github.io/cargo-generate/) 生成。

生成出来的项目自带：统一的格式化 / Clippy 规则、测试与覆盖率、依赖安全与 License 审计、
拼写检查、Git 钩子、CHANGELOG 自动生成、发版与跨平台二进制分发流程，以及一套完整的 CI；
按需还能生成命令行、日志、错误处理的代码骨架。

> 这份 README 是**模板仓库自己的说明**，不会进入生成的项目。
> 生成项目里的 README 来自 [`_README.md`](_README.md)。

## 快速开始

先装 cargo-generate（只需一次）：

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
just doctor
just install-tools
just hooks
just ci
```

> ⚠️ cargo-generate 会在目标目录 `git init`，但**不会**替你提交——
> 生成完之后所有文件都还是 untracked。首次提交要自己来（`just changelog`
> 这类依赖 git 历史的命令在没有任何提交时会直接报错）。

## 生成时会问什么

交互式会依次询问下面几项；也可以全部用 `--define key=value` 在命令行给定，实现非交互生成。

| 变量 | 说明 | 可选值 / 默认 |
| --- | --- | --- |
| `description` | 项目简介，写入 `Cargo.toml` 的 `description` | 默认 `A Rust project` |
| `repo-owner` | 仓库所有者（GitHub / GitLab 的用户名或组织名），用于拼 `repository` 字段 | 允许字母数字与 `._/-`，GitLab 子组写 `group/subgroup` |
| `toolchain` | 写入 `rust-toolchain.toml` 的 channel | `nightly`（默认）/ `stable` |
| `license` | 开源协议 | `MIT`（默认）/ `Apache-2.0` / `MIT OR Apache-2.0` |
| `ci` | CI 平台 | `github`（默认）/ `gitlab` / `none` |
| `docker` | 是否生成 Dockerfile 与容器命令 | `false`（默认）/ `true` |
| `async_runtime` | 是否引入 tokio 并开启阻塞 API 禁令 | `false`（默认）/ `true` |
| `error_handling` | 是否生成错误处理骨架 | `true`（默认）/ `false` |
| `cli` | 是否生成命令行骨架（clap），**仅 bin** | `false`（默认）/ `true` |
| `logging` | 是否生成日志骨架（tracing），**仅 bin** | `false`（默认）/ `true` |
| `open_source` | 是否生成开源社区文件（见下） | `false`（默认）/ `true` |

> 没有单独的「托管平台」变量：`repository` 的域名由 `ci` 推导（`gitlab` → `gitlab.com`，
> 其余 → `github.com`）。`ci = none` 又托管在 GitLab 时，生成完手工改一下 `Cargo.toml`
> 的 `repository` 即可。

**项目名与作者不在上表里**，它们是 cargo-generate 的内置变量，不需要（也不该）再定义一遍：

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
  --define cli=true \
  --define logging=true \
  --define open_source=false
```

> `--silent` 模式下**所有**占位符都必须给全，漏一个就会直接失败。

### bin 与 lib 的差异

`--bin`（默认）和 `--lib` 决定生成哪套源码骨架，由 `cargo-generate.toml` 里的
`[conditional.'crate_type == ...']` 控制：

| | `--bin` | `--lib` |
| --- | --- | --- |
| 源码 | `src/lib.rs` + `src/main.rs` | `src/lib.rs` |
| 集成测试 | `tests/integration.rs` | `tests/integration.rs` |
| `missing_docs` lint | `allow` | `warn`（强制公开 API 写文档） |
| `error_handling` | thiserror 定义在 lib，`main` 用 anyhow 收口 | 只有 thiserror，公开导出 |
| `cli` / `logging` | 按开关生成 `src/cli.rs` / `src/telemetry.rs` | **始终不生成**（见下） |
| Docker 相关文件 | 按 `docker` 开关 | 始终不生成（库没有可执行入口） |
| docs.rs 元数据 | 无 | `[package.metadata.docs.rs]` + `unexpected_cfgs` 登记 `docsrs` |
| CI 的 semver job | 跳过 | 以上一个 tag 为基线检查 API 破坏性变更 |
| `just flamegraph` | 可用 | 跳过（没有 bin target） |

#### bin 项目为什么也有 `src/lib.rs`

这是 Rust 里的主流布局，也是模板刻意做的选择：`main.rs` 只做参数解析、日志初始化
和错误收口，业务逻辑全在 lib 那一侧。

理由很实在——**`main.rs` 里的东西够不着**：集成测试（`tests/` 是独立 crate）、
benchmark、doctest 都只能 `use` 到 lib target 导出的 `pub` 项。逻辑留在 `main.rs`
里就只能靠手工跑一遍程序来验证，而这件事没有人会每次都做。

配套的两处判断也跟着调整了，免得内部库被当成对外 API：

- `just semver` 与 CI 的 semver job 只在**纯库**项目（有 `src/lib.rs`、没有
  `src/main.rs`）上跑。bin 的 lib target 是自用的，改签名不该被判成破坏性变更；
- `missing_docs` 对 bin 仍是 `allow`——内部库不必每个函数都写文档。

项目确实要同时对外发布库和命令行时，把这两处判断里的 `src/main.rs` 条件删掉即可。

`cli` / `logging` 对库不生效是有意的：解析命令行、安装全局 tracing subscriber
都是**应用**的职责。库替调用方做这些决定属于越界——一个库如果自己装了 subscriber，
使用它的程序就没法再自己配置日志了。库里想发日志，只加 `tracing` 依赖用它的宏即可。
选了这两项去生成库时，post-script 会打印一行说明，不会静默忽略。

### 为什么社区文件默认不生成

`SECURITY.md`、`CODE_OF_CONDUCT.md`、`CONTRIBUTING.md`、issue / PR（MR）模板、`CODEOWNERS`
这几份文件，只有在「项目公开 + 期待外部贡献者」时才产生价值：

- `SECURITY.md` 是告诉陌生人「发现漏洞别开公开 issue」——没有陌生人就没有意义；
- issue 模板是给外部报障者用的表单；
- `CODEOWNERS` 要配合分支保护规则才有约束力，单人仓库里它什么也不做；
- `CONTRIBUTING.md` 的内容和生成项目的 README 重了一大半。

私有仓库或个人项目里，它们是你永远不会打开、但每次 `ls` 都会看见的一堆文件。
所以默认关闭，需要时把 `open_source` 打开即可——能力没删，只是移出了默认路径。

协作模板按平台分发，两边是对等的：

| | `ci = github` | `ci = gitlab` | `ci = none` |
| --- | --- | --- | --- |
| issue 模板 | `.github/ISSUE_TEMPLATE/`（YAML 表单） | `.gitlab/issue_templates/`（Markdown） | 无 |
| PR / MR 模板 | `.github/PULL_REQUEST_TEMPLATE.md` | `.gitlab/merge_request_templates/Default.md` | 无 |
| `CODEOWNERS` | 仓库根目录 | 仓库根目录 | 仓库根目录 |
| 三份 md | 都有 | 都有 | 都有 |

`CODEOWNERS` 刻意放在**仓库根目录**而不是 `.github/` 下：根目录是 GitHub 与 GitLab
唯一都认的位置（GitHub 认根 / `.github/` / `docs/`，GitLab 认根 / `.gitlab/` / `docs/`）。
放进 `.github/` 的话，`ci != github` 时它会被那条 ignore 规则连坐删掉，
而且就算留下来 GitLab 也读不到。

`ci = none` 时没有 issue / MR 模板，因为不知道该按哪个平台的约定放——
post-script 会打印一行说明，不会静默少给。

### 功能开关的实际效果

| 开关 | `true` / 选中时 | `false` / 未选时 |
| --- | --- | --- |
| `ci = github` | 保留 `.github/`（workflows + dependabot + issue / PR 模板） | 其余取值下整个 `.github/` 被 ignore |
| `ci = gitlab` | 保留 `.gitlab-ci.yml` 与 `.gitlab/`（issue / MR 模板） | 其余取值下两者都被 ignore |
| `docker` | 生成 `Dockerfile`、`.dockerignore`、`docker.just` | 三者都不生成 |
| `async_runtime` | 加 tokio、入口变 `#[tokio::main]`、`clippy.toml` 启用阻塞 API 禁令 | 保持同步骨架，禁令以注释形式留在 `clippy.toml` |
| `error_handling` | 生成 `src/error.rs`，加 thiserror（bin 再加 anyhow） | 不生成，`main` 返回 `()` |
| `cli` | 生成 `src/cli.rs`，加 clap，`main` 里解析参数 | 不生成 |
| `logging` | 生成 `src/telemetry.rs`，加 tracing，`main` 里初始化 | 不生成，输出走 `println!` |
| `open_source` | 生成 `SECURITY.md` / `CODE_OF_CONDUCT.md` / `CONTRIBUTING.md` / `CODEOWNERS`，外加当前 CI 平台对应的 issue 与 PR/MR 模板（见上表） | 一个都不生成 |

任何一个会加依赖的开关被打开时，post-script 都会删掉模板自带的 `Cargo.lock`
——那份 lock 只锁了根 crate 一个包，留着必然过期，而 CI 全程用 `--locked`。

`docker.just` 通过根 `justfile` 里的 `import? 'docker.just'` 可选加载——
没生成这个文件时 `import?` 会静默跳过（普通 `import` 则会报错）。

### License 文件的处理

模板里同时放着 `LICENSE-MIT` 和 `LICENSE-APACHE`，生成后由
[`post-script.rhai`](post-script.rhai) 按选择收拾：

- 选单一协议 → 删掉另一个，剩下的改名成 `LICENSE`
- 选 `MIT OR Apache-2.0` → 两个都保留（Rust 生态双协议的标准做法）

## 模板里有什么

| 文件 | 作用 |
| --- | --- |
| `rust-toolchain.toml` | 固定工具链版本与组件 |
| `rustfmt.toml` | 格式化规则（含 unstable 选项，走 nightly） |
| `clippy.toml` | Clippy 行为配置（lint 开关在 `Cargo.toml` 的 `[workspace.lints]`） |
| `deny.toml` | 依赖的安全公告 / License / 重复版本 / 来源审计 |
| `.taplo.toml` | TOML 格式化规则（rustfmt 只管 `.rs`，`.toml` 归 taplo） |
| `.typos.toml` | 拼写检查的词表与排除规则 |
| `cliff.toml` | git-cliff 生成 CHANGELOG 的模板与分组规则 |
| `release.toml` | cargo-release 的发版流程配置 |
| `bacon.toml` | bacon 实时监控的任务定义 |
| `justfile` | 全部日常命令的入口（含 `just doctor` 环境体检） |
| `docker.just` | 容器命令，可选生成 |
| `Dockerfile` / `.dockerignore` | 多阶段构建 + distroless 运行镜像，可选生成 |
| `.config/nextest.toml` | 测试运行器配置（CI profile + 测试分组示例） |
| `.pre-commit-config.yaml` | Git 钩子（pre-commit / commit-msg / pre-push） |
| `.devcontainer/` | Dev Container / Codespaces 配置 |
| `.editorconfig` / `.gitattributes` / `.gitignore` | 编辑器与 git 的基础约定 |
| `.vscode/` | rust-analyzer 配置与推荐插件 |
| `CONTRIBUTING.md` / `SECURITY.md` / `CODE_OF_CONDUCT.md` / `CODEOWNERS` | 社区文件，`open_source` 开关控制 |
| `.github/workflows/build.yaml` | CI：lint / test / deny / workflows / msrv / hack / semver / miri |
| `.github/workflows/release.yaml` | tag 触发：验证 → Release → 跨平台二进制 → crates.io |
| `.github/workflows/audit.yaml` | 每日定时依赖安全审计 |
| `.github/dependabot.yml` | cargo / actions / docker 三类依赖的自动升级 |
| `.github/ISSUE_TEMPLATE/` `PULL_REQUEST_TEMPLATE.md` | GitHub 协作模板，`open_source` 开关控制 |
| `.gitlab-ci.yml` | GitLab CI 的等价流水线，可选生成 |
| `.gitlab/issue_templates/` `.gitlab/merge_request_templates/` | GitLab 协作模板，`open_source` 开关控制 |

只属于模板仓库、**不会**进入生成项目的文件（在 `cargo-generate.toml` 的 `ignore` 里）：

| 文件 | 作用 |
| --- | --- |
| `README.md` | 就是本文件（严格说它在 `exclude` 而非 `ignore`，由 post-script 删掉后让 `_README.md` 顶上） |
| `CHANGELOG.md` | 模板自己的变更记录 |
| `template.just` | 模板维护命令（`just smoke` 等） |
| `scripts/smoke.sh` | 自测脚本：矩阵生成项目并逐个跑检查 |
| `.github/workflows/template-ci.yaml` | 模板自己的 CI |

各文件的详细说明写在文件自己的注释里，以及生成项目的 [`_README.md`](_README.md)。

## 维护这个模板

### ⚠️ 在模板仓库里跑不了 cargo

模板仓库根目录的 `rust-toolchain.toml` 里 channel 是 `{{ toolchain }}`，
`Cargo.toml` 里包名是 `{{ project-name }}` —— 两者都不是合法取值，所以在这个目录下
**任何 cargo / rustup 命令都会直接报错**：

```
error: custom toolchain '{{ toolchain }}' specified in override file ... is not installed
```

这是预期行为，不是环境坏了。

注意 `cargo generate` 本身也是 `cargo` 的子命令，所以**在模板目录里执行
`cargo generate --path .` 同样会报这个错**——rustup 在 cargo 真正启动之前就失败了。
自测脚本因此会先 `cd` 到临时目录，再用绝对路径指回模板。

（`.pre-commit-config.yaml` 里的 cargo 类钩子都带了
`grep -qF "{{ project-name }}" Cargo.toml && exit 0` 的守卫，正是为了在模板仓库里自动跳过。
所以 `pre-commit run --all-files` 在模板仓库里是可以正常跑的。）

### 改完模板后的自测

**这是唯一可靠的验证方式**，而且已经脚本化了：

```bash
just smoke          # 12 组：覆盖每个开关的开与关，含 2 组 nightly、3 种协议
just smoke-full     # 28 组：bin 的 4 个源码开关全排列 + lib + nightly
                    #        + 社区文件组合 + 协议
just smoke-keep     # 跑完保留生成的项目，方便进去手工看
just template-lint  # 检查模板仓库自身：pre-commit + zizmor + actionlint + shellcheck + lychee
```

每个组合会依次验证：

1. 能不能生成（liquid 语法、conditional 配置）
2. `cargo +nightly fmt --check` —— 模板里的源码排版错一个空行，
   使用者第一次跑 CI 就会挂在这上面
3. `cargo clippy -- -D warnings` —— 和 CI 同样的严格度
4. 测试（nextest）与 doctest
5. `RUSTDOCFLAGS="-D warnings" cargo doc` —— 文档警告。编译 / clippy / 测试都看不见
   它，写错一个 intra-doc 链接要等使用者跑 CI 才会红
6. `cargo deny check` —— 某个开关引入的依赖可能带着不在白名单里的协议
7. 留下来的 `Cargo.lock` 与 `Cargo.toml` 对得上（`cargo metadata --locked`）
8. `justfile` 能被 just 解析
9. README 里的 Markdown 表格没有被条件块裁出的空行截断
10. 生成项目里的 TOML 都是合法 TOML
11. `taplo fmt --check` —— 排版也要合规，否则使用者第一次跑 CI 会红在
    一个跟他毫无关系的地方
12. **没有残留未渲染的 `{{ }}` / `{% %}`** —— 变量改名漏一处、`{% raw %}` 忘了配对，
    症状就是它，而编译 / clippy / 测试统统发现不了（多半藏在注释和文档里）
13. **文件清单与开关对得上** —— `conditional` / `ignore` 写错的典型症状是**少了一个文件**：
    代码照样编过，问题要等使用者去用那个功能时才暴露。这一条把每个开关该生成、
    不该生成的文件逐个断言了一遍（见 `scripts/smoke.sh` 里的 `assert_layout`），
    并顺带核对 README 的 license 徽章 URL——shields.io 把 `-` 当字段分隔符，
    协议名里的 `-` 不转义成 `--` 的话整张徽章 404，而那是一张图片，本地看不出来
14. `docker build` —— 默认关闭，`SMOKE_DOCKER=1` 打开（容器里从零编译，很慢）；
    模板 CI 里只有每周的完整矩阵会开

CI 上由 [`.github/workflows/template-ci.yaml`](.github/workflows/template-ci.yaml)
跑同一个脚本：push / PR 跑默认矩阵，每周一定时跑完整矩阵——
上游的 clippy、rustfmt、依赖都在动，模板没改也可能某天就生成不出能过 CI 的项目了。

### ⚠️ 源码模板里不要把包名写进宏参数

rustfmt 限制调用参数列表宽度的是 `fn_call_width`（默认 **60**），不是 `max_width`
（100）。所以下面这行在包名短的时候好好的，包名一长就会被 rustfmt 折成三行，
生成出来的项目**开箱就过不了 `fmt --check`**：

```rust
assert_eq!({{ crate_name }}::greet("world"), "Hello, world!");
```

对策是先绑到一个短变量，再让宏只碰这个变量：

```rust
let msg = {{ crate_name }}::greet("world");
assert_eq!(msg, "Hello, world!");
```

集成测试里则统一走一条 `use {{ crate_name }}::{...};`，之后所有调用都是短名字。
（导入顺序按 rustfmt 的规则是大写在前：`{Error, add, greet}`。）

自测矩阵里专门有一组 `a-deliberately-long-package-name-for-rustfmt` 盯这件事——
短名字的组合永远测不出来。

### Liquid 与其它模板语法的冲突

模板文件默认会被 Liquid 引擎处理，`{{ }}` 和 `{% %}` 会被当成占位符替换掉。
下面这些文件里的花括号属于**别的**模板语言，必须写进 `cargo-generate.toml` 的
`exclude` 列表（文件照常复制，只是不做变量替换）：

| 文件 | 里面的花括号属于 |
| --- | --- |
| `cliff.toml` | git-cliff 的 Tera 模板 |
| `.github/workflows/**` | GitHub Actions 的 `${{ ... }}` |
| `justfile` / `docker.just` / `template.just` | just 自己的 `{{ 变量 }}` |
| `release.toml` | cargo-release 的 `{{version}}` |
| `.pre-commit-config.yaml` | 钩子里用来识别模板仓库的 `{{ project-name }}` 字面量 |
| `scripts/**` | shell 的 `${...}` |
| `.gitlab-ci.yml` | GitLab CI 的 `$VARIABLE` 与规则表达式 |
| `README.md` | 就是本文件，里面有大量占位符示例 |

⚠️ 改动这份 exclude 列表时，记得同步 `scripts/smoke.sh` 里第 12 项检查的 `--exclude`
参数——那条检查靠排除这些文件来判断「还有没有该渲染却没渲染的占位符」。

⚠️ 注意 exclude 的是 `.github/workflows/**` 而**不是** `.github/**`：
`CODEOWNERS` 和 issue 模板里的 `{{ repo-owner }}` 是**需要**被替换的。

`exclude` 与 `ignore` 是两回事，别弄混：

- **`exclude`** —— 文件**会**进入生成的项目，只是不做变量替换
  （其它模板引擎里叫 `copy_without_render`，cargo-generate 没有这个键，`exclude` 就是它）
- **`ignore`** —— 文件**不会**进入生成的项目

⚠️ 一个容易踩的坑：`exclude` / `ignore` 的匹配发生在 **`.liquid` 后缀被去掉之后**，
所以 `exclude = ["README.md"]` 会连 `README.md.liquid` 一起排除掉。本模板因此
不用 `.liquid` 后缀，而是把生成项目的 README 命名为 `_README.md`，
由 `post-script.rhai` 在生成后改名顶替。

### TOML 文件里的 liquid 标签必须锚在注释行

`Cargo.toml` / `clippy.toml` 里的条件块一律写成这样——标签挂在 TOML **注释行的行尾**：

```toml
# 这里是版本目录{% if async_runtime %}
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
# feature 在此统一收口{% endif %}
```

好处是文件在模板仓库里**同时也是合法 TOML**：编辑器的 TOML 语言服务不报错，
`check-toml` 钩子照常检查，`tomllib` 也能解析（自测脚本会验证这一点）。

反例是单独占一行的裸 `{%- if ... %}`，或者把标签挂在**值**的行尾
（`rustdoc-args = [...]{% endif %}`）——两者都会让文件变成非法 TOML。

### 二进制文件必须显式 exclude

cargo-generate 不会自动豁免二进制内容——图标、字体、测试夹具一旦被 Liquid 处理过就会损坏。
`cargo-generate.toml` 里已经预置了一组通配（`*.png` / `*.woff2` / `assets/**` / `fixtures/**` 等），
往模板里加二进制资源时先确认它落在这些模式内。

⚠️ **反过来也要小心**：`LICENSE-MIT` / `LICENSE-APACHE` 里的 `{{ authors }}` 和
`{{ "now" | date: "%Y" }}` 是**有意**要被渲染的。"凡是不确定就 exclude"在这里是错的，
会生成出带着原始占位符的许可证文件。

### 钩子里不要用 `system::command`

Rhai 的 `system::command` 受 cargo-generate 的命令确认机制管辖：

- 交互式生成时，每执行一条外部命令都会弹一次确认；
- `--silent` 时**直接报错中止**：

  ```
  Cannot prompt for system command confirmation in silent mode.
  Use --allow-commands if you want to allow the template to run system commands
  ```

也就是说，钩子里只要出现一条 `system::command`，所有非交互生成都必须额外带 `--allow-commands`。
本模板因此把"检查工具链组件"这类需求挪到了 `just doctor`——在真正的项目目录里跑，
随时可重跑，不受生成期限制。`post-script.rhai` 只做纯文件操作。

同理，`post` 钩子运行时文件**还在临时目录**、尚未移动到目标位置，所以钩子里
`git init` 是没有意义的（cargo-generate 自己会在最终目录建仓库，但不会提交）。

### 依赖的上游版本

三处需要跟进，都有对应的自动化：

| 位置 | 形式 | 谁来更新 |
| --- | --- | --- |
| workflow 里的 action | commit hash + `# vX.Y.Z` 注释 | 生成项目里由 dependabot 每周更新；模板仓库自己要手动跑 `just template-update` |
| `.pre-commit-config.yaml` 的 `rev` | tag | `pre-commit autoupdate`（含在 `just template-update` 里） |
| `Cargo.toml` 里可选依赖的版本 | caret 版本 | 手动，改动很少 |

action 用 hash 而不是 tag，是因为 tag 是可变的：上游账号一旦被攻破，
把 `v3` 指向恶意提交就能直接进所有使用者的 CI（2025 年 tj-actions 事件就是这么发生的）。
代价是不会自动跟进上游修复，所以 dependabot 的 `github-actions` 规则不是可选项。

## License

MIT OR Apache-2.0
