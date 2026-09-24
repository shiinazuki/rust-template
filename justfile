# 项目命令入口。`just` 列出全部命令，`just --list` 同理。
#
# Docker 相关命令拆在 docker.just 里，可选加载（文件不存在时 `import?` 静默跳过）
import? 'docker.just'
# 模板仓库自己的维护配方，生成出来的项目里没有这个文件
import? 'template.just'

#
# 从 git remote 推导「托管平台 + owner/repo」，git-cliff 用它生成 changelog 里的提交链接。
# GitHub 用 GITHUB_REPO，GitLab 用 GITLAB_REPO，两者要分开识别。
origin_url := `git remote get-url origin 2>/dev/null || true`
# git@host:owner/repo.git 与 https://host/owner/repo.git 两种写法都剥成 owner/repo
repo_slug := `git remote get-url origin 2>/dev/null | sed -E -e 's,^[^/@]+@[^:]+:,,' -e 's,^[a-z]+://[^/]+/,,' -e 's,\.git$,,' || true`
repo_host := if origin_url =~ 'gitlab' { "gitlab" } else { if origin_url =~ 'github' { "github" } else { "" } }
# 包名（本文件不做 liquid 替换，只能从 Cargo.toml 里读）
pkg := `grep -m1 '^name' Cargo.toml | sed -E 's/.*"(.*)".*/\1/'`

# rust-toolchain.toml 声明的 channel。两套 CI 与 git 钩子都调用本文件的配方，不再各自解析。
channel := `grep -m1 '^channel' rust-toolchain.toml 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || true`

# CI 环境（GitHub / GitLab 都会设 CI）里给 cargo 命令加 --locked；本地由 `just ci` 的 _lock-fresh 把关
locked := if env("CI", "") == "" { "" } else { "--locked" }

# 列出所有可用命令
default:
    @just --list --unsorted

# 「你在模板仓库里，这里跑不了 cargo」的统一闸门，被下面几条常用配方依赖。
#
# 判断依据是 Cargo.toml 里还有没有 liquid 标签。用 `{%` 而不是 `{{`：
# 后者是 just 自己的插值语法。
[private]
_generated-only:
    #!/usr/bin/env bash
    set -euo pipefail
    if grep -q '{%' Cargo.toml 2>/dev/null; then
        {
            echo "✗ 这里是【模板仓库】，不是生成出来的项目——跑不了 cargo。"
            echo
            echo "  Cargo.toml 里还是 liquid 占位符，rust-toolchain.toml 的 channel"
            echo "  也不是合法工具链名。"
            echo
            echo "  模板仓库该跑的是："
            echo "      just smoke          # 生成 10 组项目并逐个跑完整检查（模板真正的 CI）"
            echo "      just smoke-full     # 19 组完整矩阵"
            echo "      just template-lint  # 检查模板仓库自身（taplo / typos / zizmor / ...）"
            echo
            echo "  想验证某个具体组合：just smoke-keep 跑完保留现场，再进那个目录跑 just ci。"
        } >&2
        exit 1
    fi

# ---------------------------------------------------------------------------
# 日常开发
# ---------------------------------------------------------------------------

[group('dev')]
[doc('快速检查代码编译')]
check: _generated-only
    cargo check --all-targets --all-features

[group('dev')]
[doc('运行程序，额外参数原样透传：just run -- --help（仅 bin 项目）')]
run *args: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f src/main.rs ]; then
        echo "没有 bin target，跳过（库项目请写一个 examples/ 再用 cargo run --example <名字>）"
        exit 0
    fi
    cargo run --all-features {{ args }}

# rustfmt 管 .rs，taplo 管 .toml（配置见 .taplo.toml），两条一起跑
[group('dev')]
[doc('格式化代码与 TOML')]
fmt: _generated-only
    cargo fmt --all
    taplo fmt

[group('dev')]
[doc('自动修复 clippy 能修的问题并格式化')]
fix: _generated-only
    cargo clippy --all-targets --all-features --fix --allow-dirty --allow-staged
    just fmt

[group('dev')]
[doc('启动后台实时监控 (bacon)')]
dev: _generated-only
    bacon

[group('dev')]
[doc('生成并打开 API 文档')]
doc: _generated-only
    cargo doc --no-deps --all-features --open

[group('dev')]
[doc('跑 benchmark（benches/ 下有 target 时才有意义，profile.bench 已配好优化）')]
bench *args: _generated-only
    cargo bench --all-features {{ args }}

# 用 profiling profile 采样：优化等级与 release 一致，另带完整调试信息。
# macOS 上 cargo-flamegraph 走 dtrace，需要 sudo；也可以换 samply：
#     cargo build --profile profiling && samply record ./target/profiling/<包名>
[group('dev')]
[doc('采样生成火焰图 flamegraph.svg（仅 bin 项目；需要 cargo-flamegraph）')]
flamegraph *args: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    # 库项目没有 bin target，改用 --bench / --example 做性能分析
    if [ ! -f src/main.rs ]; then
        echo "没有 bin target，跳过火焰图（库项目请用 --bench / --example）"
        exit 0
    fi
    cargo flamegraph --profile profiling --bin {{ pkg }} {{ args }}

# 在 ~/.cargo/config.toml 里设了共享 build.target-dir 时，改用 `cargo clean -p <包名>`
# 只清本项目。
[group('dev')]
[doc('清理编译产物与本地生成的报告')]
clean: _generated-only
    cargo clean
    # 与 .gitignore 里那几类本地产物对齐
    rm -rf coverage
    rm -f lcov.info junit.xml flamegraph.svg profile.json perf.data* *.profraw *.profdata

# ---------------------------------------------------------------------------
# 检查
# ---------------------------------------------------------------------------

# 两套 CI 的 lint job 直接跑这条，最后一条把 rustdoc 的警告也升级成错误
[group('check')]
[doc('格式化检查 / TOML 排版 / clippy / 拼写检查 / 文档警告（CI 的 lint job 跑的就是它）')]
lint: _generated-only
    cargo fmt --all -- --check
    taplo fmt --check
    cargo clippy {{ locked }} --all-targets --all-features -- -D warnings
    typos
    RUSTDOCFLAGS="-D warnings" cargo doc {{ locked }} --no-deps --all-features --document-private-items

[group('check')]
[doc('运行测试（含 doctest）')]
test: _generated-only && doctest
    cargo nextest run {{ locked }} --all-targets --all-features

# nextest 不跑 doctest
[group('check')]
[doc('运行文档测试（没有 lib target 时跳过）')]
doctest: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f src/lib.rs ]; then
        cargo test {{ locked }} --doc --all-features
    fi

# 跑一遍测试，从同一份数据出 lcov 与汇总；CI 的 test job 另设 NEXTEST_PROFILE=ci。
# 想给覆盖率设下限，在最后一条后面加 --fail-under-lines N（N 是百分比）。
[group('check')]
[doc('跑测试并生成覆盖率报告（lcov.info + 终端汇总）')]
coverage: _generated-only _llvm-tools
    cargo llvm-cov clean --workspace
    cargo llvm-cov --no-report nextest {{ locked }} --all-features
    cargo llvm-cov report --lcov --output-path lcov.info
    cargo llvm-cov report --summary-only

[group('check')]
[doc('生成 HTML 覆盖率报告并在浏览器里打开')]
coverage-html: _generated-only _llvm-tools
    cargo llvm-cov nextest --all-features --html --open

# cargo-llvm-cov 需要的 llvm-tools 组件不在 rust-toolchain.toml 里，由覆盖率配方按需安装
[private]
_llvm-tools:
    rustup component add llvm-tools-preview

[group('check')]
[doc('依赖安全与 License 检查')]
audit: _generated-only
    cargo deny check -A unmatched-bypass

# CI 的 hack job 跑的就是它。--depth 2 限制组合爆炸。
# 不能加 --locked：--no-dev-deps 会临时删掉 [dev-dependencies]，依赖图一变就要改 Cargo.lock。
# 没有 [features] 也没有 optional 依赖时幂集只有一种组合，等于一次 cargo check，直接跳过。
[group('check')]
[doc('遍历 feature 幂集做检查（没有 feature 时跳过；需要 cargo-hack）')]
hack: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    if ! find . -name Cargo.toml -not -path './target/*' \
        -exec grep -qE '^\[features\]|^[^#]*optional *= *true' {} +; then
        echo "没有声明 feature，跳过幂集检查"
        exit 0
    fi
    cargo hack --feature-powerset --depth 2 --no-dev-deps check

# 不放进 `just ci`，两套 CI 里也没有对应的 job：cargo-machete 靠扫源码里的符号判断，
# 只在宏里用到的依赖会被误报。误报时在 Cargo.toml 里加
# [package.metadata.cargo-machete] ignored = [...] 放行。
[group('check')]
[doc('找出声明了却没被用到的依赖（需要 cargo-machete）')]
unused: _generated-only
    cargo machete

# 不放进 `just ci`：没有发过版（没有 v* tag）时无从比较。CI 的 semver job 跑的就是它。
[group('check')]
[doc('以最近的 v* tag 为基线检查公开 API 破坏性变更（仅纯库项目；需要 cargo-semver-checks）')]
semver: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    # bin 项目的 lib target 只服务于自己的 main.rs 与集成测试，不参与 semver 检查；
    # 项目确实要同时发布库和命令行时，把这段判断删掉。
    if [ ! -f src/lib.rs ] || [ -f src/main.rs ]; then
        echo "不是纯库项目，跳过 semver 检查"
        exit 0
    fi
    if ! tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null); then
        echo "还没有 v* tag，跳过 semver 检查"
        exit 0
    fi
    echo "基线版本：$tag"
    cargo semver-checks --baseline-rev "$tag"

# 把直接依赖解析到版本约束允许的最低版本（间接依赖仍取最新）再编译 lib，
# 验证 Cargo.toml 里写的下限真的可用。解析要用 nightly cargo 的 -Zdirect-minimal-versions，
# 结束后恢复原来的 Cargo.lock。CI 的 minimal-versions job 跑的就是它。
[group('check')]
[doc('用依赖声明的最低版本编译 lib（仅纯库项目；需要 nightly 工具链）')]
minimal-versions: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f src/lib.rs ] || [ -f src/main.rs ]; then
        echo "不是纯库项目，跳过 minimal-versions 检查"
        exit 0
    fi
    if [[ "{{ channel }}" == nightly* ]]; then
        nightly="{{ channel }}"
    else
        nightly=nightly
        # 只在没有 nightly 时安装，不顺带升级已有的
        cargo +nightly --version >/dev/null 2>&1 || rustup toolchain install nightly --profile minimal
    fi
    cp Cargo.lock Cargo.lock.bak
    trap 'mv Cargo.lock.bak Cargo.lock' EXIT
    cargo "+$nightly" update -Zdirect-minimal-versions
    CARGO_TARGET_DIR=target/minimal-versions cargo check --lib --all-features

# nightly 项目上 MSRV 检查不适用，自动转去跑 `just nll`。CI 的 msrv job 跑的就是它。
[group('check')]
[doc('验证 Cargo.toml 里声明的 MSRV 真的能编译（nightly 项目改跑 nll）')]
msrv: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    version=$(grep -m1 '^rust-version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [[ "{{ channel }}" == nightly* ]]; then
        echo "工具链是 {{ channel }}：MSRV 检查不适用，改跑 NLL 兜底检查"
        exec just nll
    fi
    if [ -z "$version" ]; then
        echo "Cargo.toml 里没有 rust-version，跳过 MSRV 检查"
        exit 0
    fi
    echo "MSRV = $version"
    rustup toolchain install "$version" --profile minimal
    cargo "+$version" check --locked --all-targets --all-features

# 用同一条 nightly 编译，但把借用检查器从 Polonius 换回 stable 的 NLL，
# 拦下只有 nightly 编得过的代码。不放进 `just ci`（换 RUSTFLAGS 等于一次全量重编），
# CI 的 msrv job 每次都会跑它。
[group('check')]
[doc('用 stable 的借用检查器（NLL）编一遍，拦下只有 nightly 编得过的代码')]
nll: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{ channel }}" != nightly* ]]; then
        echo "工具链是 {{ channel }}，本来用的就是 NLL，无需检查"
        exit 0
    fi
    # 换个 target 目录，避免和平时 `just check` 的产物互相顶掉
    CARGO_TARGET_DIR=target/nll RUSTFLAGS=-Zpolonius=off \
        cargo check --locked --all-targets --all-features

# 从 rustc-ice-*.txt 里摘出三处关键信息：panic 消息、产生它的编译器版本、query stack。
[group('check')]
[doc('解读 rustc-ice-*.txt：哪一版编译器崩的、崩在哪、下一步怎么办')]
ice:
    #!/usr/bin/env bash
    set -uo pipefail
    shopt -s nullglob
    dumps=(rustc-ice-*.txt)
    if [ "${#dumps[@]}" -eq 0 ]; then
        echo "没有找到 rustc-ice-*.txt。"
        echo "（rustc 把转储写在**当前工作目录**而不是 target/ 下；.gitignore 已经挡住它们，"
        echo "  所以 git status 干净不代表没有——用这条配方看，别看 git。）"
        exit 0
    fi
    channel="{{ channel }}"
    echo "发现 ${#dumps[@]} 个 ICE 转储；rust-toolchain.toml 声明的 channel：${channel:-（读不到）}"
    echo ""
    for f in "${dumps[@]}"; do
        echo "── ${f}"
        # 第 1、2 行是 panic 位置与消息
        sed -n '1,2p' "$f" | sed 's/^/     /'
        grep -m1 '^rustc version:' "$f" | sed 's/^/     /'
        # query stack 只取前几层
        sed -n '/^query stack during panic:/,/^end of query stack/p' "$f" \
            | grep -E '^#[0-9]' | head -5 | sed 's/^/     /'
        echo ""
    done
    echo "接下来："
    echo "  1. 先核对上面的 rustc version 和 channel 是不是同一个编译器。"
    echo "     对不上 -> 你的 rust-toolchain.toml 没生效，先跑 just doctor。"
    echo "  2. 对得上 -> 就是这一版编译器在你的代码上崩了。照 query stack 找到那个"
    echo "     函数 / 类型，那里多半有个能换写法绕开的构造。"
    echo "  3. 要立刻恢复工作：把**你这个项目**的 channel 钉到前几天的 nightly ——"
    echo "     rust-toolchain.toml 里写 channel = \"nightly-YYYY-MM-DD\"。"
    echo "     这是项目级的临时措施，修好之后记得改回 \"nightly\" 或往前挪。"
    echo "  4. 值得上报：https://github.com/rust-lang/rust/issues （附完整转储文件）"
    echo ""
    echo "清理：rm -f rustc-ice-*.txt"

# 确认 Cargo.lock 与 Cargo.toml 对得上。
#
# 下面 lint / test 用的命令不带 --locked，依赖对不上时它们会顺手改写 Cargo.lock 再继续，
# 于是本地全绿、推上去 CI 却用提交里那份旧 lock 失败（CI 与 Dockerfile 全程 --locked）。
[private]
_lock-fresh: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    if ! cargo metadata --locked --format-version 1 >/dev/null 2>&1; then
        {
            echo "✗ Cargo.lock 与 Cargo.toml 对不上（或还没生成）。"
            echo "  CI 与 Dockerfile 全程用 --locked，这样推上去会直接失败。"
            echo "  跑 just bootstrap 重新生成，并把 Cargo.lock 一起提交。"
        } >&2
        exit 1
    fi

# 覆盖 CI 里的 lint / test / deny 三个 job。
# 不含 hack / msrv / nll / minimal-versions，它们各自是独立配方，CI 上照常会跑。
[group('check')]
[doc('本地跑一遍 CI 的主要检查（lint / test / audit）')]
ci: _lock-fresh lint test audit

# ---------------------------------------------------------------------------
# 依赖维护
# ---------------------------------------------------------------------------

[group('deps')]
[doc('按 Cargo.toml 的版本约束升级 Cargo.lock')]
update: _generated-only && audit
    cargo update

# 只预演不写 Cargo.lock。约束内能升的显示为 Updating，
# 要改 Cargo.toml 里的约束才能升的在行尾标 (available: vX.Y.Z)。
[group('deps')]
[doc('列出可升级的依赖（不改 Cargo.lock）')]
outdated: _generated-only
    cargo update --dry-run --verbose

# ---------------------------------------------------------------------------
# 发布
# ---------------------------------------------------------------------------

[group('release')]
[doc('生成 / 更新 CHANGELOG.md')]
changelog:
    #!/usr/bin/env bash
    set -euo pipefail
    # --offline: 只用 owner/repo 拼链接，不去调平台 API
    just _cliff --offline -o CHANGELOG.md

# 内部配方：把 CHANGELOG 生成到指定版本，供 release.toml 的 pre-release-hook 调用。
# cargo-release 预演时也会调用它（环境变量 DRY_RUN=true），这时不写文件。
[private]
_changelog-for version:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${DRY_RUN:-false}" = true ]; then
        exit 0
    fi
    just _cliff --offline --tag "v{{ version }}" -o CHANGELOG.md
    # cargo-release 只提交已跟踪的文件，首次发版生成的 CHANGELOG.md 要先纳入跟踪
    git add CHANGELOG.md

# 内部配方：带上正确的平台变量调用 git-cliff，两个 changelog 配方共用
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

# 这条不依赖 `ci`：正常流程是先 `just release` 预演（那一步已经跑过全套检查）。
# 单独用它发版时请自己先跑一次 `just ci`。
[group('release')]
[doc('真正执行发版（跳过预演；请确保刚跑过 just release 或 just ci）')]
release-execute level="patch": _generated-only
    cargo release {{ level }} --execute

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

# 刚 cargo generate 出来之后跑的第一条命令：生成 Cargo.lock（CI 与 Dockerfile
# 全程用 --locked，缺了它第一次推送就会失败）并启用 git 钩子。
[group('setup')]
[doc('首次拉起项目：生成 Cargo.lock、启用 git 钩子')]
bootstrap: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    # cargo fetch 只解析依赖树并下载，不编译
    cargo fetch
    echo "✓ Cargo.lock 已就绪"
    just hooks
    echo ""
    echo "接下来：just doctor 体检工具链，just ci 走一遍完整检查。"

[group('setup')]
[doc('体检：检查工具链组件与配套 cargo 工具是否齐全，并给出补装命令')]
doctor:
    #!/usr/bin/env bash
    # 不加 `set -e`：体检要把所有问题一次列全
    set -uo pipefail
    missing=0

    echo "== 工具链 =="
    if ! command -v rustup >/dev/null 2>&1; then
        echo "  ✗ 未找到 rustup（https://rustup.rs）"
        exit 1
    fi
    echo "  rust-toolchain.toml 声明的 channel: {{ channel }}"
    rustc --version 2>/dev/null | sed 's/^/  /' || {
        echo "  ✗ 工具链 {{ channel }} 尚未安装 -> rustup toolchain install"
        missing=1
    }

    # 校验 rust-toolchain.toml 是否还说了算：rustup 的目录 override 和
    # RUSTUP_TOOLCHAIN 环境变量优先级都比它高，且完全静默。
    # `rustup show active-toolchain` 会把生效原因写在括号里。
    active=$(rustup show active-toolchain 2>/dev/null || true)
    if [ -n "$active" ]; then
        echo "  实际生效的工具链: ${active}"
        case "$active" in
            *"directory override"*)
                echo "  ✗ 存在 rustup 目录 override，rust-toolchain.toml 被架空 -> rustup override unset"
                missing=1 ;;
            *"environment variable RUSTUP_TOOLCHAIN"*)
                echo "  ✗ RUSTUP_TOOLCHAIN 环境变量覆盖了 rust-toolchain.toml -> unset RUSTUP_TOOLCHAIN"
                missing=1 ;;
            *rust-toolchain.toml*)
                echo "  ✓ 由 rust-toolchain.toml 决定" ;;
            *)
                # 多半是 "(default)"：rustup 没读到本项目的 toolchain 文件
                echo "  ✗ 不是由 rust-toolchain.toml 决定的 -> 确认在项目根目录下运行，且该文件还在"
                missing=1 ;;
        esac
    fi

    echo "== 组件 =="
    installed=$(rustup component list --installed 2>/dev/null)
    for c in rustfmt clippy rust-src; do
        if grep -q "^${c}" <<<"$installed"; then
            echo "  ✓ ${c}"
        else
            echo "  ✗ ${c} -> rustup component add ${c}"
            missing=1
        fi
    done

    # 缺了会让 just ci 失败的，计入缺失项
    echo "== 配套工具（just ci 必需）=="
    for t in cargo-nextest cargo-deny typos taplo; do
        if command -v "$t" >/dev/null 2>&1; then
            echo "  ✓ ${t}"
        else
            echo "  ✗ ${t} -> just install-tools"
            missing=1
        fi
    done

    # 只有对应的配方用得到，不计入缺失项
    echo "== 配套工具（按需）=="
    for t in cargo-llvm-cov cargo-release git-cliff cargo-hack cargo-semver-checks \
             cargo-machete bacon; do
        command -v "$t" >/dev/null 2>&1 \
            && echo "  ✓ ${t}" \
            || echo "  - ${t}（未安装 -> just install-tools）"
    done

    # ICE 转储只提示，不计入缺失项
    shopt -s nullglob
    ice_dumps=(rustc-ice-*.txt)
    if [ "${#ice_dumps[@]}" -gt 0 ]; then
        echo "== 编译器崩溃 =="
        echo "  ⚠️ 发现 ${#ice_dumps[@]} 个 rustc-ice-*.txt（编译器内部错误转储）-> just ice"
    fi

    echo "== git 钩子 =="
    if [ "$(git config --get core.hooksPath 2>/dev/null)" = ".githooks" ]; then
        echo "  ✓ .githooks 已启用（commit-msg / pre-push）"
    else
        echo "  - 未启用 -> just hooks"
    fi

    echo "== 可选 =="
    for t in cargo-binstall cargo-generate cargo-flamegraph docker; do
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
        cargo-machete      # 找出没用到的依赖
        cargo-semver-checks # 公开 API 的破坏性变更检查
        typos-cli          # 拼写检查
        taplo-cli          # TOML 格式化与检查
        git-cliff          # 生成 CHANGELOG
        bacon              # 后台实时监控
        cargo-hack         # feature 幂集检查，和 CI 的 hack job 对齐
    )
    # 优先用 cargo-binstall 下预编译二进制，没有预编译包的会自动退回源码编译
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

# 生成本项目的模板地址，fork 了模板的话改成自己的；也可以临时指定：just template-sync ../rust-template
template_source := "https://github.com/shiinazuki/rust-template"

# 按 .config/template-values.toml 里记下的选项，用最新模板原地重新生成，结果直接写进工作区，
# 由 git 挑选要保留的改动。模板删掉的文件不会被同步删除。需要 cargo-generate 0.24+。
[group('setup')]
[doc('按生成时的选项用最新模板原地重新生成，再用 git 挑选要保留的改动')]
template-sync source=template_source: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "$(git status --porcelain)" ]; then
        echo "✗ 工作区有未提交的改动，先提交或 stash：重新生成后要靠 git diff 区分模板带来的改动。" >&2
        exit 1
    fi
    kind=$([ -f src/main.rs ] && echo bin || echo lib)
    if [ -d "{{ source }}" ]; then from=--path; else from=--git; fi
    # 丢掉 stdout：post-script 打印的是新项目的上手步骤，这里用不上
    cargo generate "$from" "{{ source }}" --name "{{ pkg }}" "--$kind" --silent \
        --values-file .config/template-values.toml --init --overwrite >/dev/null
    git status --short
    echo ""
    echo "接下来："
    echo "  git diff               逐个看模板带来的改动"
    echo "  git restore src tests  丢掉对业务代码的覆盖（其它被覆盖的文件同理）"
    echo "  git add -p             挑出要保留的改动，再提交"
    echo "  git restore .          全部放弃"

# 用 core.hooksPath 启用仓库里的 .githooks/，每个 clone 都要跑一次。
[group('setup')]
[doc('启用 git 钩子（commit-msg 校验提交信息 / pre-push 跑 just ci）')]
hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    # cargo-generate 不保证保留可执行位，这里补一次
    chmod +x .githooks/*
    git config core.hooksPath .githooks
    echo "✓ 已启用 .githooks/"
    echo "    pre-commit  按改动跑快速检查（fmt / clippy / taplo / typos / 私钥）"
    echo "    commit-msg  校验 Conventional Commits（CHANGELOG 的分组依赖它）"
    echo "    pre-push    跑一遍 just ci（lint / test / audit）"
    echo "  临时跳过：git commit --no-verify / git push --no-verify"
    echo "  停用：git config --unset core.hooksPath"
