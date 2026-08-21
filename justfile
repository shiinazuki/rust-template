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

# 纯库项目没有可执行文件，`cargo run` 会直接报 "a bin target must be available"。
# 判断依据和下面的 flamegraph / semver 一致：有没有 src/main.rs。
[group('dev')]
[doc('运行程序，额外参数原样透传：just run -- --help（仅 bin 项目）')]
run *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f src/main.rs ]; then
        echo "没有 bin target，跳过（库项目请写一个 examples/ 再用 cargo run --example <名字>）"
        exit 0
    fi
    cargo run --all-features {{ args }}

# rustfmt 只管 .rs，项目里十来个 .toml 归 taplo 管（配置见 .taplo.toml）。
# 两条一起跑，免得「格式化过了」却还是挂在 CI 的 TOML 检查上。
[group('dev')]
[doc('格式化代码与 TOML（rustfmt.toml 用到 unstable 选项，必须走 nightly）')]
fmt:
    cargo +nightly fmt --all
    taplo fmt

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
[doc('采样生成火焰图 flamegraph.svg（仅 bin 项目；需要 cargo-flamegraph）')]
flamegraph *args:
    #!/usr/bin/env bash
    set -euo pipefail
    # 纯库项目没有可执行文件，--bin 会直接报 "no bin target"。
    # 想给库做性能分析的话，写一个 benches/ 或 examples/ 再用 --bench / --example。
    if [ ! -f src/main.rs ]; then
        echo "没有 bin target，跳过火焰图（库项目请用 --bench / --example）"
        exit 0
    fi
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

# 这几条和 CI 的 lint job 一一对应，少一条本地就拦不住对应的 CI 失败。
#
# 文档警告尤其容易漏：Cargo.toml 的 [workspace.lints.rustdoc] 里
# bare_urls / invalid_html_tags / private_intra_doc_links 都只是 warn，
# 本地不跑 cargo doc 根本看不见，推上去才在 CI 的 RUSTDOCFLAGS="-D warnings" 上挂掉。
[group('check')]
[doc('格式化检查 / TOML 排版 / clippy / 拼写检查 / 文档警告（与 CI 的 lint job 等价）')]
lint:
    cargo +nightly fmt --all -- --check
    taplo fmt --check
    cargo clippy --all-targets --all-features -- -D warnings
    typos
    RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --all-features --document-private-items

[group('check')]
[doc('运行测试（含 doctest）')]
test:
    #!/usr/bin/env bash
    set -euo pipefail
    cargo nextest run --all-targets --all-features
    # nextest 不跑 doctest，有 lib target 时补一次（bin 项目也有，见 src/lib.rs）
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

# 刻意不放进 `just ci`，两套 CI 里也**没有**对应的 job：cargo-machete 靠扫源码里的
# 符号判断，只在宏里用到的依赖会被误报——误报率高的检查一旦当上门禁，结果只会是
# 所有人都学会忽略它。误报时在 Cargo.toml 里加
# [package.metadata.cargo-machete] ignored = [...] 放行。
[group('check')]
[doc('找出声明了却没被用到的依赖（需要 cargo-machete）')]
unused:
    cargo machete

# 同样不放进 `just ci`：要和已发布的版本比对，本地没网或没发布过时没意义。
# 发布库之前手动跑一次，确认版本号该抬 patch 还是 minor/major。
[group('check')]
[doc('检查公开 API 有没有破坏性变更（仅纯库项目；需要 cargo-semver-checks）')]
semver:
    #!/usr/bin/env bash
    set -euo pipefail
    # bin 项目也有 lib target，但那是给自己的 main.rs 和集成测试用的内部库，
    # 不对外承诺 API，改签名不该被判成破坏性变更。判断依据是有没有 src/main.rs。
    # 你的项目确实要同时对外发布库和命令行时，把下面这段判断删掉即可。
    if [ ! -f src/lib.rs ] || [ -f src/main.rs ]; then
        echo "不是纯库项目，跳过 semver 检查"
        exit 0
    fi
    cargo semver-checks

# nightly 项目上 MSRV 检查不适用（可能用了 #![feature(...)]，在 stable 上必然编不过），
# 自动转去跑 `just nll`——那才是 nightly 项目真正需要的那道兜底。
# 判断依据是 rust-toolchain.toml 的 channel，和 CI 里的逻辑一致。
[group('check')]
[doc('验证 Cargo.toml 里声明的 MSRV 真的能编译（nightly 项目改跑 nll）')]
msrv:
    #!/usr/bin/env bash
    set -euo pipefail
    channel=$(grep -m1 '^channel' rust-toolchain.toml | sed -E 's/.*"([^"]+)".*/\1/')
    version=$(grep -m1 '^rust-version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ "${channel#nightly}" != "$channel" ]; then
        echo "工具链是 ${channel}：MSRV 检查不适用，改跑 NLL 兜底检查"
        exec just nll
    fi
    if [ -z "$version" ]; then
        echo "Cargo.toml 里没有 rust-version，跳过 MSRV 检查"
        exit 0
    fi
    echo "MSRV = $version"
    rustup toolchain install "$version" --profile minimal
    cargo "+$version" check --locked --all-targets --all-features

# 2026-08-06 起 nightly 默认启用了新一代借用检查器 Polonius，它比 stable 的 NLL
# 接受更多合法程序（最典型的是「条件返回一个借用，之后再可变借用同一个值」这类写法）。
#
# ⚠️ 麻烦在于这个差异**没有任何显式标记**：不像 #![feature(...)] 那样一眼可见，
#    没有属性、没有 lint、连 warning 都没有。于是在 nightly 上很容易写出一段
#    stable 编不过的代码而毫无察觉，Cargo.toml 里的 rust-version 却还写着老版本——
#    发库的话是下游用户先撞上，不发的话就是哪天想切回 stable 时才发现欠了一堆债。
#
# 这条配方用同一条 nightly 编译，只把借用检查器换回 stable 那套，把这类代码就地拦下。
# 刻意不放进 `just ci`：RUSTFLAGS 一变就是一次全量重编，不适合塞进随手跑的命令；
# CI 的 msrv job 每次都会跑它，本地在动了生命周期相关的代码之后手动跑一次就够。
# 等 Polonius 进了 stable（官方计划 2026 年底），这条配方连同注释一起删掉即可。
[group('check')]
[doc('用 stable 的借用检查器（NLL）编一遍，拦下只有 nightly 编得过的代码')]
nll:
    #!/usr/bin/env bash
    set -euo pipefail
    channel=$(grep -m1 '^channel' rust-toolchain.toml | sed -E 's/.*"([^"]+)".*/\1/')
    if [ "${channel#nightly}" = "$channel" ]; then
        echo "工具链是 ${channel}，本来用的就是 NLL，无需检查"
        exit 0
    fi
    # 换个 target 目录：RUSTFLAGS 一变，产物就和平时 `just check` 的 target/ 互不通用，
    # 混在一起会让两边反复全量重编。
    # ⚠️ RUSTFLAGS 是整体**覆盖** .cargo/config.toml 里的 rustflags，不是追加；
    #    以后在那边加了编译参数，记得同步到这一行。
    CARGO_TARGET_DIR=target/nll RUSTFLAGS=-Zpolonius=off \
        cargo check --locked --all-targets --all-features

# CI 的 miri job 在本地的等价物：在解释器里跑测试，检测未定义行为（越界、悬垂指针、
# 数据竞争、对齐错误）。本模板默认 `unsafe_code = "forbid"`，你自己的代码里跑不出 UB，
# 它的价值在于**依赖里的 unsafe** 也会被一并检查到。
#
# 判断条件和 CI 完全一致：只在 nightly 上可用；检测到 tokio 就跳过（起 runtime 要 epoll，
# miri 不支持这类系统调用，留着只会得到一个永远红着的检查）。
# 刻意不放进 `just ci`：miri 比原生慢一到两个数量级，不适合塞进随手跑的命令。
[group('check')]
[doc('在 miri 解释器里跑测试检测未定义行为（仅 nightly；有 tokio 时自动跳过）')]
miri:
    #!/usr/bin/env bash
    set -euo pipefail
    channel=$(grep -m1 '^channel' rust-toolchain.toml | sed -E 's/.*"([^"]+)".*/\1/')
    if [ "${channel#nightly}" = "$channel" ]; then
        echo "工具链是 ${channel}：miri 仅 nightly 可用，跳过"
        exit 0
    fi
    if grep -qE '^[[:space:]]*tokio[[:space:]]*=' Cargo.toml; then
        echo "检测到 tokio：miri 不支持 epoll 等系统调用，跳过"
        exit 0
    fi
    # --allow-downgrade：miri 组件偶尔会在某天的 nightly 里缺席，有了它 rustup 会
    # 自动退回到最近一个带 miri 的 nightly，而不是直接失败。
    rustup toolchain install nightly --allow-downgrade --profile minimal --component miri,rust-src
    cargo +nightly miri setup
    # -Zmiri-disable-isolation：允许测试读时钟 / 环境变量，否则很多测试直接报错
    MIRIFLAGS=-Zmiri-disable-isolation cargo +nightly miri test --locked --all-features

# 覆盖 CI 里的 lint / test / deny 三个 job。
# 刻意不含 hack / msrv / nll：第一个要装 cargo-hack，第二个会 `rustup toolchain install`
# 往你机器上装一整条工具链，第三个换了 RUSTFLAGS 等于一次全量重编，
# 都不适合塞进「随手跑一下」的命令里。
# 它们各自是独立配方（just hack / just msrv / just nll），CI 上照常会跑。
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
[doc('发版预演：跑全套检查 + 干跑一遍，看清楚会改什么。level: patch|minor|major')]
release level="patch": ci
    # 先干跑一遍确认改动符合预期，再真正执行
    cargo release {{ level }}
    @echo ""
    @echo "以上是预演结果。确认无误后执行："
    @echo "    just release-execute {{ level }}"

# ⚠️ 这条**不**依赖 `ci`：正常流程是先 `just release` 预演（那一步已经跑过全套检查），
#    确认无误后紧接着执行这条，两分钟内再跑一遍完全相同的检查纯属浪费。
#    真要单独用它发版（跳过预演），请自己先跑一次 `just ci`。
#    另外 release.toml 里 verify = true，cargo-release 自己还会做一次打包校验。
[group('release')]
[doc('真正执行发版（跳过预演；请确保刚跑过 just release 或 just ci）')]
release-execute level="patch":
    cargo release {{ level }} --execute

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

# 刚 `cargo generate` 出来之后跑的第一条命令。
#
# 为什么要单独有它：模板自带的 Cargo.lock 只锁了根 crate 一个包，一旦生成时选了
# 带依赖的开关（tokio / tracing / thiserror / anyhow），那份 lock 就对不上，
# post-script 会主动删掉它。而 CI 与 Dockerfile 全程用 `--locked`——
# 没有 lock 就会在第一次推送时失败，报错信息离「你选了哪个开关」很远。
[group('setup')]
[doc('首次拉起项目：生成 Cargo.lock、安装 pre-commit 钩子')]
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    # cargo fetch 只解析依赖树并下载，不编译，是生成 Cargo.lock 最快的方式
    cargo fetch
    echo "✓ Cargo.lock 已就绪"
    if command -v pre-commit >/dev/null 2>&1; then
        pre-commit install --install-hooks
    else
        echo "- 未装 pre-commit，跳过钩子（pipx install pre-commit 之后跑 just hooks 补上）"
    fi
    echo ""
    echo "接下来：just doctor 体检工具链，just ci 走一遍完整检查。"

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
             cargo-machete cargo-semver-checks cargo-hack typos taplo git-cliff bacon; do
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
        taplo-cli          # TOML 格式化与检查
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
