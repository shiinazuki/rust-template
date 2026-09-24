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
  main.rs          可执行入口：{% if logging %}初始化日志、{% endif %}错误收口{% if logging %}
  telemetry.rs     日志 / 追踪初始化（tracing）{% endif %}
tests/
  integration.rs   集成测试：以外部使用者的视角调用 lib 的公开 API
```

二进制项目也有 `lib.rs`：集成测试（`tests/` 是独立 crate）、benchmark、doctest 都只能
`use` 到 `lib.rs` 导出的 `pub` 项。`main.rs` 长起来了，就说明有东西该往 `lib.rs` 挪。
{% endif %}
## 开发

工具链与配套工具、常用命令、CI、发版流程等开发说明见 [`docs/development.md`](docs/development.md)。

## License

协议在生成项目时选定，对应的许可证文件在仓库根目录：
单协议是 `LICENSE`，双协议（MIT OR Apache-2.0）则是 `LICENSE-MIT` 与 `LICENSE-APACHE`。
具体取值见 `Cargo.toml` 的 `license` 字段。
