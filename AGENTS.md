# AGENTS.md

给 AI 编码助手（Claude Code / Codex / Cursor 等）的项目约定。人类同样适用。

本项目有几条**反直觉**的约定，照通用 Rust 习惯来会直接把 CI 打红。开工前先读完这一页。

> 看到的是未替换的占位符？说明你在**模板仓库**里，不是生成出来的项目。
> 模板仓库根目录跑不了任何 `cargo` 命令，改模板的规矩见 `README.md`。

## 命令入口一律走 just

```bash
just            # 列出全部命令
just check      # 快速编译检查
just test       # 测试（nextest + doctest）
just lint       # 格式化 / TOML / clippy / 拼写 / 文档，与 CI 的 lint job 等价
just ci         # 提交前跑这个：lint + test + audit
```

**改完代码后至少跑一次 `just lint`**。不要只跑 `cargo build` 就宣称完成——CI 卡的是
clippy 和 rustdoc，不是编译。

## 五条最容易踩的

### 1. 格式化必须走 nightly，而且要走 `just fmt`

```bash
just fmt        # 不要手写 cargo fmt，也不要手写 cargo +nightly fmt
```

`rustfmt.toml` 用了 `imports_granularity` / `group_imports` / `wrap_comments` 等
**unstable 选项**。stable 的 rustfmt 会**静默忽略**它们——不报错，但也不格式化，
于是你以为格式化过了，CI 上照样挂。绝不要写 `cargo fmt`。

也不要图省事写死 `cargo +nightly fmt`：`rust-toolchain.toml` 的 channel 如果被钉成了
日期版本（`nightly-2026-08-18`），`+nightly` 指的是**另一条**工具链，排版结果可能和
CI 不一致。`just fmt` 会从 channel 推导出正确的那一条（见 justfile 顶部的
`fmt_toolchain`），两套 CI 用的是同一套规则。

### 2. CI 是零警告

`cargo clippy -- -D warnings` 加 `RUSTDOCFLAGS="-D warnings"`。任何一条 warning
（包括文档里的死链、缺失的 `# Errors` 段）都会让构建失败。

### 3. 不许靠压制 lint 来过 CI

发现 clippy 报错，**改代码**，不要加 `#[allow]`。确实必须压制时：

```rust
#[expect(clippy::needless_pass_by_value, reason = "trait 签名要求按值传")]
```

- 用 `#[expect]` 而不是 `#[allow]`（`clippy::allow_attributes` 是 warn，而 CI 零容忍）。
  区别在于这条 lint 以后不再触发时，`expect` 会反过来提醒你删掉它。
- **必须带 `reason = "..."`**。
- `unsafe_code = "forbid"`，`forbid` 连 `#[allow]` 都推翻不了。需要 unsafe 请先说明理由，
  由人决定要不要把它降成 `deny`。

### 4. 默认工具链是 nightly，借用检查器不一样

nightly 用的是 Polonius，它比 stable 的 NLL 接受更多程序，而且**没有任何提示**
——没有属性、没有 lint、连 warning 都没有。也就是说你可能写出一段
「nightly 编得过、stable 编不过」的代码而毫无察觉。

碰了生命周期 / 借用相关的代码后，跑：

```bash
just nll        # 同一条 nightly，但把借用检查器换回 NLL
```

### 5. 输出不要用 println!

程序的正常输出走 `src/main.rs` 里的 `print_line()`。`println!` 在下游管道提前关闭时
（`prog | head -1`）会 panic。日志走 stderr，业务输出走 stdout，两者不要混。

## 代码放哪里

- **业务逻辑一律写在 `src/lib.rs` 那一侧。** `src/main.rs` 只做参数解析、日志初始化、
  错误收口，保持在几十行以内。
- 理由不是审美：`main.rs` 里的东西集成测试（`tests/`）、benchmark、doctest 都够不着。
- 加了 `pub` 的东西就是对外承诺。内部用的类型标 `pub(crate)`（`unreachable_pub` 是 warn）。
{% if error_handling %}
## 错误处理的分工

- **库那一侧（`src/error.rs`）**用 `thiserror` 定义具体、可 `match` 的错误类型。
- **应用那一侧（`main.rs`）**才用 `anyhow`，配合 `.context()` 补上下文。
- **绝不要让库的公开 API 返回 `anyhow::Error`**——那等于剥夺调用方分类处理错误的能力。
- 新增错误变体直接加进 `Error` 枚举即可，它标了 `#[non_exhaustive]`，不算破坏性变更。
- 公开函数返回 `Result` 时，文档注释里要写 `# Errors` 段。
{% endif %}{% if async_runtime %}
## 异步：禁止阻塞 API

`clippy.toml` 里 `disallowed-types` / `disallowed-methods` 封了 `std::fs::*` 和
`std::process::Command`——一次同步 read 就能把 runtime 的一个 worker 线程钉死。
一律用 `tokio::fs::*` / `tokio::process::Command`。

确实必须同步（比如启动时读一次配置）时，在那一处写
`#[expect(clippy::disallowed_methods, reason = "启动期一次性读取，此时 runtime 还没起")]`。
{% endif %}
## 依赖

- 版本统一声明在 `Cargo.toml` 的 `[workspace.dependencies]`，成员里只写
  `foo = { workspace = true }`。
- **加依赖之后必须跑 `just audit`**（cargo-deny）。它会卡：不在允许清单里的 License、
  未知来源、有安全公告的版本、通配符版本号。
- 不要手改 `Cargo.lock`。CI 和 Dockerfile 全程 `--locked`，lock 与 manifest 对不上会直接失败。
- 引入新依赖前先想想标准库有没有（`[bans.std-replacements]` 会拦 `lazy_static` 这类）。

## 测试

- `just test` 跑 nextest **和** doctest。只跑 `cargo nextest run` 会漏掉 doctest。
- nextest 默认每个测试一个进程、全部并行。共享资源（同一个端口 / 数据库 / 临时文件）的
  测试要用 `.config/nextest.toml` 里的 `[test-groups]` 串行化，不要在测试里加 `Mutex`。
- 集成测试（`tests/`）只能访问 `pub` 项——这正是它的价值，它替你回答「导出的够不够用」。
- 测试里用 `unwrap` / `expect` / `panic` 是允许的，已在 `clippy.toml` 里统一放行。

## 提交

`just hooks` 启用后有三层检查，**不要用 `--no-verify` 绕过**：

| 钩子 | 跑什么 |
| --- | --- |
| `pre-commit` | 按改动的文件类型跑 rustfmt / clippy / taplo / cargo-deny / typos + 私钥检测，秒级 |
| `commit-msg` | 校验下面的提交格式 |
| `pre-push` | 完整的 `just ci` |

提交信息用 Conventional Commits：

```
feat(cli): 支持 --json 输出
fix: 下游管道提前关闭时不再 panic
refactor!: greet 改为返回 Result      # ! = 破坏性变更
```

type 取值：`build chore ci docs feat fix perf refactor revert style test`。
CHANGELOG 由 `cliff.toml` 按 type 分组生成，`cargo-release` 也靠它判断版本号怎么抬。

## 不要做的事

- 不要新增配置文件。这个项目的配置已经比源码多，加东西前先问。
- 不要改 `Cargo.toml` 的 `[workspace.lints]`、`clippy.toml`、`rustfmt.toml`、`deny.toml`
  来让检查通过——那是在拆报警器。
- 不要在 `main.rs` 里堆业务逻辑。
- 不要因为"CI 太慢"就删 job。
- 拿不准的时候问，不要猜着改配置。
