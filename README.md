# rust-template

一个开箱即用的 Rust 项目模板，通过 [cargo-generate](https://cargo-generate.github.io/cargo-generate/) 生成。

生成出来的项目自带：统一的格式化 / Clippy 规则、测试与覆盖率、依赖安全与 License 审计、
拼写检查、Git 钩子、CHANGELOG 自动生成、发版流程，以及一套完整的 CI。

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

生成完成后，进入目录按提示跑几条命令即可开工：

```bash
just doctor
just install-tools
just hooks
just ci
```

## 生成时会问什么

交互式会依次询问下面几项；也可以全部用 `--define key=value` 在命令行给定，实现非交互生成。

| 变量 | 说明 | 可选值 / 默认 |
| --- | --- | --- |
| `description` | 项目简介，写入 `Cargo.toml` 的 `description` | 默认 `A Rust project` |
| `gh-username` | GitHub 用户名或组织名，用于拼 `repository` 字段 | 需符合 GitHub 用户名规则 |
| `toolchain` | 写入 `rust-toolchain.toml` 的 channel | `nightly`（默认）/ `stable` |
| `license` | 开源协议 | `MIT`（默认）/ `Apache-2.0` / `MIT OR Apache-2.0` |
| `ci` | CI 平台 | `github`（默认）/ `gitlab` / `none` |
| `docker` | 是否生成 Dockerfile 与容器命令 | `false`（默认）/ `true` |
| `async_runtime` | 是否引入 tokio 并开启阻塞 API 禁令 | `false`（默认）/ `true` |

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
  --define gh-username=shiinazuki \
  --define toolchain=stable \
  --define license="MIT OR Apache-2.0" \
  --define ci=github \
  --define docker=true \
  --define async_runtime=true
```

> `--silent` 模式下**所有**占位符都必须给全，漏一个就会直接失败。

### bin 与 lib 的差异

`--bin`（默认）和 `--lib` 决定生成哪套源码骨架，由 `cargo-generate.toml` 里的
`[conditional.'crate_type == ...']` 控制：

| | `--bin` | `--lib` |
| --- | --- | --- |
| 源码 | `src/main.rs` | `src/lib.rs` |
| 集成测试 | 无 | `tests/integration.rs` |
| `missing_docs` lint | `allow` | `warn`（强制公开 API 写文档） |
| Docker 相关文件 | 按 `docker` 开关 | 始终不生成（库没有可执行入口） |
| `just test` | 只跑 nextest | nextest + doctest |

### 功能开关的实际效果

| 开关 | `true` / 选中时 | `false` / 未选时 |
| --- | --- | --- |
| `ci = github` | 保留 `.github/`（workflows + dependabot） | 其余取值下整个 `.github/` 被 ignore |
| `ci = gitlab` | 保留 `.gitlab-ci.yml` | 其余取值下该文件被 ignore |
| `docker` | 生成 `Dockerfile`、`.dockerignore`、`docker.just` | 三者都不生成 |
| `async_runtime` | `Cargo.toml` 加 tokio、入口变 `#[tokio::main]`、`clippy.toml` 启用阻塞 API 禁令、删掉过期的 `Cargo.lock` | 保持同步骨架，禁令以注释形式留在 `clippy.toml` 里 |

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
| `_typos.toml` | 拼写检查的词表与排除规则 |
| `cliff.toml` | git-cliff 生成 CHANGELOG 的模板与分组规则 |
| `release.toml` | cargo-release 的发版流程配置 |
| `bacon.toml` | bacon 实时监控的任务定义 |
| `justfile` | 全部日常命令的入口（含 `just doctor` 环境体检） |
| `docker.just` | 容器命令，可选生成 |
| `Dockerfile` / `.dockerignore` | 多阶段构建 + distroless 运行镜像，可选生成 |
| `.config/nextest.toml` | 测试运行器配置（含 CI 专用 profile） |
| `.pre-commit-config.yaml` | Git 钩子（pre-commit / commit-msg / pre-push） |
| `.editorconfig` | 跨编辑器的基础排版约定 |
| `.gitattributes` | 入库换行统一、二进制标记、`Cargo.lock` 折叠 |
| `.vscode/` | rust-analyzer 配置与推荐插件 |
| `.github/workflows/` | CI：lint / test / deny / msrv / hack / miri / release + 每日安全审计 |
| `.github/dependabot.yml` | 依赖与 Actions 的自动升级 |
| `.gitlab-ci.yml` | GitLab CI 的等价流水线，可选生成 |

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
自测时必须先 `cd` 到模板目录之外，再用绝对路径指向模板（见下）。

（`.pre-commit-config.yaml` 里的 cargo 类钩子都带了
`grep -qF "{{ project-name }}" Cargo.toml && exit 0` 的守卫，正是为了在模板仓库里自动跳过。
所以 `pre-commit run --all-files` 在模板仓库里是可以正常跑的。）

### 改完模板后的自测

生成 bin / lib 两种项目各跑一遍完整检查，是唯一可靠的验证方式。
在模板仓库根目录执行：

```bash
template=$(pwd) tmp=$(mktemp -d) && cd "$tmp" && for kind in bin lib; do
  cargo generate --path "$template" --name "smoke-$kind" "--$kind" --silent \
    --define description="smoke test" \
    --define gh-username=example \
    --define toolchain=stable \
    --define license=MIT \
    --define ci=github \
    --define docker=false \
    --define async_runtime=false
  (cd "smoke-$kind" && just ci) && echo "✅ $kind" || echo "❌ $kind 失败"
done; echo "产物在 $tmp"
```

要点：先 `cd "$tmp"` 再调 `cargo generate`，避开模板仓库里那个不合法的
`rust-toolchain.toml`；`--define` 把所有占位符都给全，就不会弹交互提示。
把 `toolchain=stable` 换成 `nightly`、把 `docker` / `async_runtime` 换成 `true`
再各跑一遍，可以覆盖其余分支。

### Liquid 与其它模板语法的冲突

模板文件默认会被 Liquid 引擎处理，`{{ }}` 和 `{% %}` 会被当成占位符替换掉。
下面这些文件里的花括号属于**别的**模板语言，必须写进 `cargo-generate.toml` 的
`exclude` 列表（文件照常复制，只是不做变量替换）：

| 文件 | 里面的花括号属于 |
| --- | --- |
| `cliff.toml` | git-cliff 的 Tera 模板 |
| `.github/**` | GitHub Actions 的 `${{ ... }}` |
| `justfile` / `docker.just` | just 自己的 `{{ 变量 }}` |
| `release.toml` | cargo-release 的 `{{version}}` |
| `.pre-commit-config.yaml` | 钩子里用来识别模板仓库的 `{{ project-name }}` 字面量 |
| `README.md` | 就是本文件，里面有大量占位符示例 |

`exclude` 与 `ignore` 是两回事，别弄混：

- **`exclude`** —— 文件**会**进入生成的项目，只是不做变量替换
  （其它模板引擎里叫 `copy_without_render`，cargo-generate 没有这个键，`exclude` 就是它）
- **`ignore`** —— 文件**不会**进入生成的项目

⚠️ 一个容易踩的坑：`exclude` / `ignore` 的匹配发生在 **`.liquid` 后缀被去掉之后**，
所以 `exclude = ["README.md"]` 会连 `README.md.liquid` 一起排除掉。本模板因此
不用 `.liquid` 后缀，而是把生成项目的 README 命名为 `_README.md`，
由 `post-script.rhai` 在生成后改名顶替。

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
`git init` 是没有意义的（cargo-generate 自己会在最终目录建好仓库）。

### 依赖的上游版本

`.pre-commit-config.yaml` 里的 `rev`、workflow 里的 action 版本都是钉死的。
Actions 由 dependabot 自动升级；pre-commit 的 rev 需要手动跑一次：

```bash
pre-commit autoupdate
```

## License

MIT OR Apache-2.0
