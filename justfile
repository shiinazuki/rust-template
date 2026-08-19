# 项目命令入口。`just` 列出全部命令，`just --list` 同理。
#
# Docker 相关命令拆在 docker.just 里，用可选 import 引进来：
# 生成项目时没选 Docker，那个文件不存在，`import?` 会静默跳过（普通 import 会报错）。
import? 'docker.just'
# 模板仓库自己的维护配方（生成出来的项目里没有这个文件，import? 会静默跳过）
import? 'template.just'

#
# 从 git remote 推导「托管平台 + owner/repo」，git-cliff 用它生成 changelog 里的提交链接。
# 平台要单独识别：GitHub 用 GITHUB_REPO，GitLab 用 GITLAB_REPO，喂错变量的话
# cliff.toml 会照着另一个平台的域名拼链接，生成一份全是死链的 CHANGELOG。
origin_url := `git remote get-url origin 2>/dev/null || true`
# git@host:owner/repo.git 与 https://host/owner/repo.git 两种写法都剥成 owner/repo
repo_slug := `git remote get-url origin 2>/dev/null | sed -E -e 's,^[^/@]+@[^:]+:,,' -e 's,^[a-z]+://[^/]+/,,' -e 's,\.git$,,' || true`
repo_host := if origin_url =~ 'gitlab' { "gitlab" } else { if origin_url =~ 'github' { "github" } else { "" } }
# 包名（本文件不做 liquid 替换，只能从 Cargo.toml 里读）
pkg := `grep -m1 '^name' Cargo.toml | sed -E 's/.*"(.*)".*/\1/'`

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

[group('dev')]
[doc('跑 benchmark（benches/ 下有 target 时才有意义，profile.bench 已配好优化）')]
bench *args:
    cargo bench --all-features {{ args }}

# 用的是 profiling profile：优化等级与 release 一致，但保留符号，
# 否则火焰图上全是地址而不是函数名。
#
# macOS 上 cargo-flamegraph 走 dtrace，需要 sudo；不想给 sudo 就换 samply：
#     cargo build --profile profiling && samply record ./target/profiling/<包名>
[group('dev')]
[doc('采样生成火焰图 flamegraph.svg（需要 cargo-flamegraph）')]
flamegraph *args:
    cargo flamegraph --profile profiling --bin {{ pkg }} {{ args }}

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

# 这四条和 CI 的 lint job 一一对应，少一条本地就拦不住对应的 CI 失败。
#
# 文档警告尤其容易漏：Cargo.toml 的 [workspace.lints.rustdoc] 里
# bare_urls / invalid_html_tags / private_intra_doc_links 都只是 warn，
# 本地不跑 cargo doc 根本看不见，推上去才在 CI 的 RUSTDOCFLAGS="-D warnings" 上挂掉。
[group('check')]
[doc('格式化检查 / clippy / 拼写检查 / 文档警告（与 CI 的 lint job 等价）')]
lint:
    cargo +nightly fmt --all -- --check
    cargo clippy --all-targets --all-features -- -D warnings
    typos
    RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --all-features --document-private-items

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
[doc('生成 HTML 覆盖率报告并在浏览器里打开')]
coverage-html:
    cargo llvm-cov nextest --all-features --html --open

[group('check')]
[doc('依赖安全与 License 检查')]
audit:
    cargo deny check

# 和 CI 的 hack job 等价。只跑 `--all-features` 会漏掉「单独开某个 feature 编不过」，
# 而使用者恰恰可能只开其中一个。--depth 2 限制组合爆炸。
[group('check')]
[doc('遍历 feature 幂集做检查（需要 cargo-hack）')]
hack:
    cargo hack --feature-powerset --depth 2 --no-dev-deps check

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

# 覆盖 CI 里的 lint / test / deny 三个 job。
# 刻意不含 hack 与 msrv：前者要装 cargo-hack，后者会 `rustup toolchain install`
# 往你机器上装一整条工具链，都不适合塞进「随手跑一下」的命令里。
# 它们各自是独立配方（just hack / just msrv），CI 上照常会跑。
[group('check')]
[doc('本地跑一遍 CI 的主要检查（lint / test / audit）')]
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
    # --offline: 只用 owner/repo 拼链接，不去调平台 API（免 token、免限流，
    # 也避免仓库还没推上去时 git-cliff 因 404 直接 panic）
    just _cliff --offline -o CHANGELOG.md

# 内部配方：给 cargo-release 的 pre-release-hook 用，把 CHANGELOG 生成到指定版本。
# 见 release.toml 的 pre-release-hook 配置。
[private]
_changelog-for version:
    #!/usr/bin/env bash
    set -euo pipefail
    just _cliff --offline --tag "v{{ version }}" -o CHANGELOG.md

# 内部配方：带上正确的平台变量调用 git-cliff。
# 两个 changelog 配方共用，免得平台判断逻辑抄两份、改一处漏一处。
[private]
_cliff *args:
    #!/usr/bin/env bash
    set -euo pipefail
    slug="{{ repo_slug }}"
    host="{{ repo_host }}"
    if [ -z "$slug" ] || [ -z "$host" ]; then
        echo "警告: 未识别到 github / gitlab 的 origin remote，CHANGELOG 里的提交链接会不完整" >&2
        git cliff {{ args }}
    elif [ "$host" = "gitlab" ]; then
        GITLAB_REPO="$slug" git cliff {{ args }}
    else
        GITHUB_REPO="$slug" git cliff {{ args }}
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
[doc('体检：检查工具链组件与配套 cargo 工具是否齐全，并给出补装命令')]
doctor:
    #!/usr/bin/env bash
    # 刻意不加 `set -e`：体检要把所有问题一次列全，不能碰到第一个就退出。
    set -uo pipefail
    missing=0

    echo "== 工具链 =="
    if ! command -v rustup >/dev/null 2>&1; then
        echo "  ✗ 未找到 rustup（https://rustup.rs）"
        exit 1
    fi
    channel=$(grep -m1 '^channel' rust-toolchain.toml | sed -E 's/.*"([^"]+)".*/\1/')
    echo "  rust-toolchain.toml 声明的 channel: ${channel}"
    rustc --version 2>/dev/null | sed 's/^/  /' || {
        echo "  ✗ 工具链 ${channel} 尚未安装 -> rustup toolchain install"
        missing=1
    }

    echo "== 组件 =="
    installed=$(rustup component list --installed 2>/dev/null)
    # llvm-tools 在 `component list` 里显示为 llvm-tools（不带 -preview 后缀）
    for c in clippy rust-src llvm-tools; do
        if grep -q "^${c}" <<<"$installed"; then
            echo "  ✓ ${c}"
        else
            echo "  ✗ ${c} -> rustup component add ${c}"
            missing=1
        fi
    done

    # 格式化恒定依赖 nightly 的 rustfmt：rustfmt.toml 里用了 unstable 选项，
    # stable 的 rustfmt 会静默忽略它们（不报错，但也不生效）。
    if rustup component list --toolchain nightly --installed 2>/dev/null | grep -q '^rustfmt'; then
        echo "  ✓ rustfmt (nightly)"
    else
        echo "  ✗ rustfmt (nightly) -> rustup toolchain install nightly --allow-downgrade --profile minimal --component rustfmt"
        missing=1
    fi

    echo "== 配套工具 =="
    for t in cargo-nextest cargo-deny cargo-llvm-cov cargo-release cargo-outdated \
             cargo-machete cargo-semver-checks cargo-hack typos git-cliff bacon; do
        if command -v "$t" >/dev/null 2>&1; then
            echo "  ✓ ${t}"
        else
            echo "  ✗ ${t} -> just install-tools"
            missing=1
        fi
    done

    echo "== 可选 =="
    for t in pre-commit cargo-binstall cargo-flamegraph docker; do
        command -v "$t" >/dev/null 2>&1 \
            && echo "  ✓ ${t}" \
            || echo "  - ${t}（未安装，非必需）"
    done

    echo ""
    if [ "$missing" -eq 0 ]; then
        echo "一切就绪，可以 just ci 了。"
    else
        echo "有缺失项，按上面的 -> 提示补装后重跑 just doctor。"
        exit 1
    fi

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
        cargo-hack         # feature 幂集检查，和 CI 的 hack job 对齐
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
    # --allow-downgrade：某天的 nightly 偶尔会缺 rustfmt 组件，加上它 rustup 会自动
    # 退回到最近一个组件齐全的 nightly，而不是直接拒绝安装。
    rustup toolchain install nightly --allow-downgrade --profile minimal --component rustfmt

[group('setup')]
[doc('安装 pre-commit 钩子（pre-commit / commit-msg / pre-push）')]
hooks:
    pre-commit install --install-hooks
