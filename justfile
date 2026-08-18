# 项目命令入口。`just` 列出全部命令，`just --list` 同理。
#
# 从 git remote 推导 owner/repo，git-cliff 用它生成 changelog 里的提交链接
gh_repo := `git remote get-url origin 2>/dev/null | sed -e 's,^git@github.com:,,' -e 's,^https://github.com/,,' -e 's,\.git$,,'`

# 列出所有可用命令
default:
    @just --list --unsorted

# ---------------------------------------------------------------------------
# 日常开发
# ---------------------------------------------------------------------------

[group('dev')]
[doc('快速检查代码编译')]
check:
    cargo check --all-targets --all-features

[group('dev')]
[doc('运行程序，额外参数原样透传：just run -- --help')]
run *args:
    cargo run --all-features {{ args }}

[group('dev')]
[doc('格式化代码（rustfmt.toml 用到 unstable 选项，必须走 nightly）')]
fmt:
    cargo +nightly fmt --all

[group('dev')]
[doc('自动修复 clippy 能修的问题并格式化')]
fix:
    cargo clippy --all-targets --all-features --fix --allow-dirty --allow-staged
    just fmt

[group('dev')]
[doc('启动后台实时监控 (bacon)')]
dev:
    bacon

[group('dev')]
[doc('生成并打开 API 文档')]
doc:
    cargo doc --no-deps --all-features --open

# ---------------------------------------------------------------------------
# 检查
# ---------------------------------------------------------------------------

[group('check')]
[doc('格式化检查 / clippy / 拼写检查')]
lint:
    cargo +nightly fmt --all -- --check
    cargo clippy --all-targets --all-features -- -D warnings
    typos

[group('check')]
[doc('运行测试（含 doctest）')]
test:
    #!/usr/bin/env bash
    set -euo pipefail
    cargo nextest run --all-targets --all-features
    # nextest 不跑 doctest，有 lib target 时补一次
    if [ -f src/lib.rs ]; then
        cargo test --doc --all-features
    fi

[group('check')]
[doc('生成覆盖率报告（lcov.info）')]
coverage:
    cargo llvm-cov nextest --all-features --lcov --output-path lcov.info

[group('check')]
[doc('依赖安全与 License 检查')]
audit:
    cargo deny check

[group('check')]
[doc('验证 Cargo.toml 里声明的 MSRV 真的能编译')]
msrv:
    #!/usr/bin/env bash
    set -euo pipefail
    version=$(grep -m1 '^rust-version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/')
    echo "MSRV = $version"
    rustup toolchain install "$version" --profile minimal
    cargo "+$version" check --locked --all-targets --all-features

[group('check')]
[doc('本地跑一遍 CI 会跑的全部检查')]
ci: lint test audit

# ---------------------------------------------------------------------------
# 依赖维护
# ---------------------------------------------------------------------------

[group('deps')]
[doc('按 Cargo.toml 的版本约束升级 Cargo.lock')]
update:
    cargo update
    cargo deny check

[group('deps')]
[doc('列出可升级的依赖（需要 cargo-outdated）')]
outdated:
    cargo outdated --root-deps-only --exit-code 1

[group('deps')]
[doc('更新 git submodule')]
update-submodule:
    git submodule update --init --recursive --remote

# ---------------------------------------------------------------------------
# 发布
# ---------------------------------------------------------------------------

[group('release')]
[doc('生成 / 更新 CHANGELOG.md')]
changelog:
    #!/usr/bin/env bash
    set -euo pipefail
    repo="{{ gh_repo }}"
    # --offline: 只用 owner/repo 拼链接，不去调 GitHub API（免 token、免限流，
    # 也避免仓库还没推上去时 git-cliff 因 404 直接 panic）
    if [ -z "$repo" ]; then
        echo "警告: 未检测到 GitHub origin remote，CHANGELOG 里的提交链接会不完整" >&2
        git cliff --offline -o CHANGELOG.md
    else
        GITHUB_REPO="$repo" git cliff --offline -o CHANGELOG.md
    fi

# 内部配方：给 cargo-release 的 pre-release-hook 用，把 CHANGELOG 生成到指定版本。
# 见 release.toml 的 pre-release-hook 配置。
[private]
_changelog-for version:
    #!/usr/bin/env bash
    set -euo pipefail
    repo="{{ gh_repo }}"
    args=(--offline --tag "v{{ version }}" -o CHANGELOG.md)
    if [ -z "$repo" ]; then
        git cliff "${args[@]}"
    else
        GITHUB_REPO="$repo" git cliff "${args[@]}"
    fi

[group('release')]
[doc('发版：跑全套检查 -> 抬版本号 -> 刷新 CHANGELOG -> 打 tag -> 推送。level: patch|minor|major')]
release level="patch": ci
    # 先干跑一遍确认改动符合预期，再真正执行
    cargo release {{ level }}
    @echo ""
    @echo "以上是预演结果。确认无误后执行："
    @echo "    just release-execute {{ level }}"

[group('release')]
[doc('真正执行发版（跳过预演）')]
release-execute level="patch": ci
    cargo release {{ level }} --execute

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

[group('setup')]
[doc('安装本项目用到的全部 cargo 工具')]
install-tools:
    cargo install --locked cargo-nextest cargo-deny cargo-llvm-cov cargo-release cargo-outdated
    cargo install --locked typos-cli git-cliff bacon
    rustup toolchain install nightly --profile minimal --component rustfmt

[group('setup')]
[doc('安装 pre-commit 钩子（pre-commit / commit-msg / pre-push）')]
hooks:
    pre-commit install --install-hooks
