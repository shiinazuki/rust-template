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

# ⚠️ 如果你在 ~/.cargo/config.toml 里设了全局共享的 build.target-dir，
#    `cargo clean` 清掉的是那个共享目录，会连带删掉其它项目的编译缓存。
#    只想清本项目的话改成 `cargo clean -p <包名>`。
[group('dev')]
[doc('清理编译产物与本地生成的报告')]
clean:
    cargo clean
    rm -f lcov.info junit.xml flamegraph.svg perf.data perf.data.old

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

# 刻意不放进 `just ci`：cargo-machete 靠扫源码里的符号判断，只在宏里用到的依赖会被
# 误报。误报时在 Cargo.toml 里加 [package.metadata.cargo-machete] ignored = [...] 放行。
[group('check')]
[doc('找出声明了却没被用到的依赖（需要 cargo-machete）')]
unused:
    cargo machete

# 同样不放进 `just ci`：要和已发布的版本比对，本地没网或没发布过时没意义。
# 发布库之前手动跑一次，确认版本号该抬 patch 还是 minor/major。
[group('check')]
[doc('检查公开 API 有没有破坏性变更（仅 lib 项目；需要 cargo-semver-checks）')]
semver:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f src/lib.rs ]; then
        echo "没有 lib target，跳过 semver 检查"
        exit 0
    fi
    cargo semver-checks

# nightly 项目自动跳过：可能用了 #![feature(...)]，在 stable 上必然编不过，
# 检查没有意义。判断依据是 rust-toolchain.toml 的 channel，和 CI 里的逻辑一致。
[group('check')]
[doc('验证 Cargo.toml 里声明的 MSRV 真的能编译（nightly 项目自动跳过）')]
msrv:
    #!/usr/bin/env bash
    set -euo pipefail
    channel=$(grep -m1 '^channel' rust-toolchain.toml | sed -E 's/.*"([^"]+)".*/\1/')
    version=$(grep -m1 '^rust-version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ "${channel#nightly}" != "$channel" ]; then
        echo "工具链是 ${channel}，跳过 MSRV 检查"
        exit 0
    fi
    if [ -z "$version" ]; then
        echo "Cargo.toml 里没有 rust-version，跳过 MSRV 检查"
        exit 0
    fi
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
    #!/usr/bin/env bash
    set -euo pipefail
    tools=(
        cargo-nextest      # 测试运行器
        cargo-deny         # 依赖安全与 License 检查
        cargo-llvm-cov     # 覆盖率
        cargo-release      # 发版
        cargo-outdated     # 检查依赖是否有新版本
        cargo-machete      # 找出没用到的依赖
        cargo-semver-checks # 公开 API 的破坏性变更检查
        typos-cli          # 拼写检查
        git-cliff          # 生成 CHANGELOG
        bacon              # 后台实时监控
    )
    # 这些工具从源码编译一遍要十几分钟。cargo-binstall 直接下载上游发布的预编译
    # 二进制，几十秒就能装完；没有预编译包的会自动退回源码编译。
    if command -v cargo-binstall >/dev/null 2>&1; then
        cargo binstall --no-confirm --locked "${tools[@]}"
    else
        echo "提示：先装 cargo-binstall 能直接下预编译二进制，比源码编译快一个数量级："
        echo "        cargo install cargo-binstall"
        echo "      （其它安装方式见 https://github.com/cargo-bins/cargo-binstall）"
        echo "本次先用 cargo install 逐个编译，请耐心等待……"
        echo ""
        cargo install --locked "${tools[@]}"
    fi
    rustup toolchain install nightly --profile minimal --component rustfmt

[group('setup')]
[doc('安装 pre-commit 钩子（pre-commit / commit-msg / pre-push）')]
hooks:
    pre-commit install --install-hooks
