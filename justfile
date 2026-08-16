# 从 git remote 推导 owner/repo，git-cliff 用它生成 changelog 里的提交链接
gh_repo := `git remote get-url origin 2>/dev/null | sed -e 's,^git@github.com:,,' -e 's,^https://github.com/,,' -e 's,\.git$,,'`

# 列出所有可用命令
default:
    @just --list

# 快速检查代码编译
check:
    cargo check --all-targets --all-features

# 格式化代码（rustfmt.toml 用到 unstable 选项，必须走 nightly）
fmt:
    cargo +nightly fmt --all

# 格式化 / clippy / 拼写检查
lint:
    cargo +nightly fmt --all -- --check
    cargo clippy --all-targets --all-features -- -D warnings
    typos

# 运行测试
test:
    #!/usr/bin/env bash
    set -euo pipefail
    cargo nextest run --all-targets --all-features
    # nextest 不跑 doctest，有 lib target 时补一次
    if [ -f src/lib.rs ]; then
        cargo test --doc --all-features
    fi

# 生成覆盖率报告（lcov.info）
coverage:
    cargo llvm-cov nextest --all-features --lcov --output-path lcov.info

# 依赖安全与 License 检查
audit:
    cargo deny check

# 本地跑一遍 CI 会跑的全部检查
ci: lint test audit

# 启动后台实时监控 (bacon)
dev:
    bacon

# 生成 / 更新 CHANGELOG.md
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

# 发布新版本：打 tag、刷新 changelog、推送
release: ci
    cargo release tag --execute
    just changelog
    git commit -a -n -m "chore(release): update CHANGELOG.md" || true
    git push origin main
    cargo release push --execute

# 更新 git submodule
update-submodule:
    git submodule update --init --recursive --remote
