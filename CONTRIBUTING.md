# 参与 {{ project-name }}

## 环境准备

```bash
just doctor          # 体检：缺什么会直接告诉你补装命令
just install-tools   # 安装配套 cargo 工具
just hooks           # 安装 git 钩子（pre-commit / commit-msg / pre-push）
just ci              # 跑一遍完整检查，确认环境就绪
```

`just` 不带参数列出全部命令。

## 开发流程

1. 从 `main` 切分支，命名随意，`feat/xxx`、`fix/xxx` 之类即可。
2. 写代码。`just dev` 会用 bacon 盯着文件变化实时重跑 clippy，反馈比手动 `cargo check` 快得多。
3. 提交。commit message 必须符合 [Conventional Commits](https://www.conventionalcommits.org/)，
   `CHANGELOG.md` 是由它自动生成的：

   ```
   feat(parser): 支持嵌套表达式
   fix: 修正边界条件下的 panic
   docs: 补充 README
   ```

   常用类型：`feat` / `fix` / `docs` / `refactor` / `perf` / `test` / `chore` / `ci` / `build`。
   破坏性变更在正文里写一行 `BREAKING CHANGE: ...`，或者在类型后加 `!`（`feat!: ...`）。

4. 推之前跑 `just ci`。pre-push 钩子也会跑一遍全量测试。
5. 开 PR，按模板填写。

## 代码约定

这些都由工具强制，不需要背：

- 格式化走 nightly rustfmt（`just fmt`）——`rustfmt.toml` 里用了 unstable 选项，
  stable 的 rustfmt 会**静默忽略**它们，结果就是你和 CI 格式化出来的东西不一样。
- clippy 以 `-D warnings` 运行，`pedantic` 组默认开启。
  觉得某条 lint 不合理，改 `Cargo.toml` 里的 `[workspace.lints]` 并在 PR 里说明，
  不要在源码里散落一堆 `#[allow]`。
- 默认禁止 `unsafe`（`unsafe_code = "forbid"`）。确实需要时先在 issue 里讨论。
- 新增依赖会经过 `cargo deny`：协议不在白名单、来源不明的 git 依赖都会被拦下。

## 测试

```bash
just test            # 单元测试 + 集成测试 + doctest
just coverage        # 覆盖率报告 lcov.info
just coverage-html   # HTML 版并直接打开
```

改了行为就补测试。修 bug 时，先写一个能复现的失败测试，再动手修——
这样能确保你修的确实是那个问题，也能防止它再回来。

## 提问与报障

- Bug 与功能建议走 issue 模板。
- **安全问题不要开公开 issue**，见 [SECURITY.md](SECURITY.md)。
