# {{ project-name }}

{{ description }}

## 开发环境

### Rust 工具链

工具链版本由 [`rust-toolchain.toml`](rust-toolchain.toml) 固定（stable），首次进入目录时 rustup 会自动安装。

格式化额外需要 nightly —— [`rustfmt.toml`](rustfmt.toml) 里用到了 `imports_granularity`、
`group_imports`、`wrap_comments` 等 unstable 选项，stable 的 rustfmt 会静默忽略它们：

```bash
rustup toolchain install nightly --profile minimal --component rustfmt
```

### 配套工具

```bash
cargo install just                        # 命令入口（见 justfile）
cargo install cargo-nextest --locked      # 测试
cargo install --locked cargo-deny         # 依赖安全与 License 检查
cargo install typos-cli                   # 拼写检查
cargo install cargo-llvm-cov              # 覆盖率
cargo install git-cliff                   # 生成 CHANGELOG
cargo install cargo-release               # 发版
cargo install bacon                       # 后台实时监控
```

### pre-commit

```bash
pipx install pre-commit
pre-commit install
```

`pre-commit install` 会同时装上 `pre-commit`、`commit-msg`、`pre-push` 三类钩子：
提交前跑格式化 / clippy / 拼写检查，提交时校验 commit message 规范，推送前跑全量测试。

## 常用命令

```bash
just              # 列出所有命令
just check        # 快速检查编译
just fmt          # 格式化（nightly）
just lint         # 格式化检查 + clippy + typos
just test         # 运行测试
just coverage     # 生成覆盖率报告 lcov.info
just audit        # cargo deny check
just ci           # 本地跑一遍 CI 的全部检查
just dev          # bacon 实时监控
just changelog    # 刷新 CHANGELOG.md
just release      # 打 tag、刷新 changelog、推送
```

## 提交规范

本项目使用 [Conventional Commits](https://www.conventionalcommits.org/)，
`CHANGELOG.md` 由 [git-cliff](https://git-cliff.org/) 依据提交信息自动生成：

```
feat(parser): 支持嵌套表达式
fix: 修正边界条件下的 panic
docs: 补充 README
```

commit message 由 pre-commit 的 `conventional-pre-commit` 钩子强制校验。

## VSCode 推荐插件

- rust-analyzer: Rust 语言支持
- crates: Rust 包管理
- Even Better TOML: TOML 文件支持
- Error Lens: 错误提示优化
- Better Comments: 优化注释显示
- GitLens: Git 增强
- indent-rainbow: 缩进显示优化
- TODO Highlight: TODO 高亮
- YAML: YAML 文件支持

## License

MIT，详见 [LICENSE](LICENSE)。
