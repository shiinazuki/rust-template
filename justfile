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

# 格式化该用哪条工具链。
#
# rustfmt.toml 里用了 imports_granularity / group_imports / wrap_comments 等 unstable
# 选项，只有 nightly 的 rustfmt 认，stable 会**静默忽略**——不报错，但也不生效。
# 所以格式化命令必须显式点名工具链。
#
# ⚠️ 但不能写死 `+nightly`：channel 一旦钉成日期版本（nightly-2026-08-18），
#    `+nightly` 指的是**另一条**「最新 nightly」工具链——多半根本没装；就算装了，
#    两个 rustfmt 版本对同一份代码的排版也可能不一样，于是「本地 check 过、CI 挂」，
#    而这种失败看起来毫无道理。rust-toolchain.toml 末尾预告的正是这个例外。
#
# 因此按 rust-toolchain.toml 的 channel 推导（和 msrv / nll 两条配方同一个手法）：
#   nightly / nightly-YYYY-MM-DD  -> 就用它自己（等价于不加 +，但写出来更清楚，
#                                     也顺带挡住 rustup 目录 override 的干扰）
#   stable / 1.85.0 之类          -> 退回 nightly，需要额外装一份 nightly 的 rustfmt
#                                     （just install-tools 会装，just doctor 会查）
#
# 读不到 rust-toolchain.toml 时（比如有人把它删了）落到 nightly，行为和从前一致。
fmt_toolchain := ```
    channel=$(grep -m1 '^channel' rust-toolchain.toml 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
    case "$channel" in
        nightly*) echo "$channel" ;;
        *)        echo nightly ;;
    esac
```

# 列出所有可用命令
default:
    @just --list --unsorted

# 「你在模板仓库里，这里跑不了 cargo」的统一闸门。
#
# 模板仓库根目录的 Cargo.toml 还是 liquid 占位符，rust-toolchain.toml 的 channel
# 也不是合法工具链名，任何 cargo 命令都会失败——问题在于失败得**很难看懂**：
#
#   - 一般情况是 rustup 先拦下：`custom toolchain '{{{{ toolchain }}' is not installed`
#   - 但 `cargo +nightly fmt` 里的 +nightly 会显式覆盖 rust-toolchain.toml，绕过 rustup
#     往前多走一步，死在 `cargo metadata` 上，再吐一整屏 rustfmt 的 usage
#
# 两种报错都不会告诉你「该去跑 just smoke」。下面几个最常被顺手敲的配方因此先撞这道闸。
#
# 判断依据是 Cargo.toml 里有没有 liquid 标签。用 `{%` 而不是 `{{`：后者是 just 自己的
# 插值语法，写在 justfile 里会被 just 抢先解释掉。
# （生成出来的项目里占位符已全部替换，这条 grep 永远不匹配，配方照常执行。）
#
# ⚠️ 写法上有个坑：just 的配方体**每一行都必须缩进**，顶格的行会被当成新的语法项。
#    所以这里用 echo 而不是 heredoc —— heredoc 的内容和结束符都得顶格，
#    just 会在解析阶段就报 `unknown start of token`。
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
[doc('格式化代码与 TOML（rustfmt.toml 用到 unstable 选项，必须走 nightly 的 rustfmt）')]
fmt: _generated-only
    cargo +{{ fmt_toolchain }} fmt --all
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
doc: _generated-only
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
lint: _generated-only
    cargo +{{ fmt_toolchain }} fmt --all -- --check
    taplo fmt --check
    cargo clippy --all-targets --all-features -- -D warnings
    typos
    RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --all-features --document-private-items

[group('check')]
[doc('运行测试（含 doctest）')]
test: _generated-only
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
audit: _generated-only
    cargo deny check -A unmatched-bypass

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

# 编译器内部错误（ICE）的转储怎么读。
#
# ⚠️ 先分清两件同时成立的事：
#      - ICE 是**编译器自己崩了**，不是你的代码有语法或类型错误；
#      - 但触发它的几乎总是你代码里某个具体构造，换个写法通常就绕过去了。
#    所以「这是 rustc 的 bug」和「和我的代码有关」并不矛盾，别用前者当结论就停下。
#
# 转储文件动辄几百行栈回溯，真正有用的只有三处，这条配方就是把它们摘出来：
#   1. 开头的 panic 消息  —— 崩在编译器哪个环节
#   2. `rustc version:`   —— **哪一版编译器**产生的。这一行最容易被跳过，却最关键：
#                            它和 rust-toolchain.toml 的 channel 对不上，就说明你的
#                            工具链配置压根没生效（多半是 rustup 目录 override），
#                            那才是要先解决的问题。`just doctor` 会直接告诉你。
#   3. `query stack`      —— 崩的时候在编译哪个东西，据此能定位回自己代码里的位置。
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
    channel=$(grep -m1 '^channel' rust-toolchain.toml 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
    echo "发现 ${#dumps[@]} 个 ICE 转储；rust-toolchain.toml 声明的 channel：${channel:-（读不到）}"
    echo ""
    for f in "${dumps[@]}"; do
        echo "── ${f}"
        # 第 1、2 行就是 panic 位置与消息
        sed -n '1,2p' "$f" | sed 's/^/     /'
        grep -m1 '^rustc version:' "$f" | sed 's/^/     /'
        # query stack 只取前几层，再往下是编译器内部细节，对定位自己的代码没帮助
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
    cargo deny check -A unmatched-bypass

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
[doc('首次拉起项目：生成 Cargo.lock、启用 git 钩子')]
bootstrap: _generated-only
    #!/usr/bin/env bash
    set -euo pipefail
    # cargo fetch 只解析依赖树并下载，不编译，是生成 Cargo.lock 最快的方式
    cargo fetch
    echo "✓ Cargo.lock 已就绪"
    just hooks
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

    # 并排打印版本号是看不出问题的——真正的坑在于 rust-toolchain.toml **是否还说了算**。
    # rustup 的目录 override 和 RUSTUP_TOOLCHAIN 环境变量优先级都比它高，而且完全静默：
    # 没有警告、没有提示，只有编译行为悄悄换了一套。所以这里做硬校验，不做肉眼比对。
    #
    # `rustup show active-toolchain` 会把生效原因一并写在括号里，三种取值：
    #   overridden by '<...>/rust-toolchain.toml'        正常，本项目期望的状态
    #   directory override for '<dir>'                   有人跑过 rustup override set
    #   overridden by environment variable RUSTUP_TOOLCHAIN
    # 工具链没装时这条命令会失败，上面那格已经报过了，这里静默跳过。
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
                # 剩下的多半是 "(default)"：rustup 压根没读到本项目的 toolchain 文件，
                # 通常是没在项目根目录下跑，或者 rust-toolchain.toml 被误删了。
                echo "  ✗ 不是由 rust-toolchain.toml 决定的 -> 确认在项目根目录下运行，且该文件还在"
                missing=1 ;;
        esac
    fi

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
    # 查的是 just fmt / just lint 真正会用的那条工具链（见文件开头的 fmt_toolchain），
    # 而不是写死的 nightly——channel 钉成日期版本时这两者不是一回事。
    if rustup component list --toolchain '{{ fmt_toolchain }}' --installed 2>/dev/null | grep -q '^rustfmt'; then
        echo "  ✓ rustfmt ({{ fmt_toolchain }})"
    else
        echo "  ✗ rustfmt ({{ fmt_toolchain }}) -> just install-tools"
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

    # ICE 转储：存在就说明这台机器上的编译器在这个项目上崩过。
    # 不算「缺失项」（可能是早就修好的旧转储），所以不置 missing，只提示去看。
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
    for t in cargo-binstall cargo-flamegraph docker; do
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
    # 只有 channel 不是 nightly 时才需要**额外**装一份 nightly 的 rustfmt。
    # channel 本身就是 nightly（含 nightly-YYYY-MM-DD）时，rust-toolchain.toml 的
    # components 里已经带了 rustfmt，再装一条滚动 nightly 反而会引入第二个 rustfmt
    # 版本——排版结果可能和项目工具链不一致，正是 fmt_toolchain 要避开的那个坑。
    channel=$(grep -m1 '^channel' rust-toolchain.toml 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
    if [ "${channel#nightly}" = "$channel" ]; then
        # --allow-downgrade：某天的 nightly 偶尔会缺 rustfmt 组件，加上它 rustup 会自动
        # 退回到最近一个组件齐全的 nightly，而不是直接拒绝安装。
        rustup toolchain install nightly --allow-downgrade --profile minimal --component rustfmt
    fi

# 启用仓库里的 .githooks/，而不是往 .git/hooks/ 拷贝一份。
#
# 用 core.hooksPath 的好处是钩子内容跟着版本库走：改了能 review、能 diff，
# 也不会出现「你机器上的钩子和我机器上的不一样」。代价是每个 clone 都要跑一次
# 这条命令——git 不会自动信任仓库里的钩子（那是设计如此，否则 clone 一个仓库
# 就等于同意执行里面的任意代码）。
[group('setup')]
[doc('启用 git 钩子（commit-msg 校验提交信息 / pre-push 跑 just ci）')]
hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    # 清理早期版本用 pre-commit 装进 .git/hooks/ 的脚本。
    #
    # 为什么非清不可：那些脚本写死了 `--config=.pre-commit-config.yaml`，而本模板已经
    # 不再有那个文件，于是每次 git commit 都会得到一句
    #   "No .pre-commit-config.yaml file was found"
    # ——它既不说是谁在报错，也不说该怎么办。设了 core.hooksPath 之后 git 确实不再看
    # .git/hooks/，但只要有人哪天 `git config --unset core.hooksPath`，它就又回来了。
    #
    # 只删自报家门的那些（文件头有 pre-commit 的生成标记），手写的钩子不动。
    for h in pre-commit commit-msg pre-push post-commit post-checkout post-merge; do
        f=".git/hooks/$h"
        if [ -f "$f" ] && grep -q "File generated by pre-commit" "$f" 2>/dev/null; then
            rm -f "$f"
            echo "  已清理遗留的 pre-commit 钩子：$f"
            # pre-commit 安装时会把原有的同名钩子改名备份成 .legacy
            if [ -f "$f.legacy" ]; then
                echo "  ⚠️ 发现 $f.legacy（pre-commit 当初备份的旧钩子），保留着，需要的话自己看一眼"
            fi
        fi
    done
    # cargo-generate 不保证保留可执行位，这里补一次，省得钩子被静默忽略
    chmod +x .githooks/*
    git config core.hooksPath .githooks
    echo "✓ 已启用 .githooks/"
    echo "    pre-commit  按改动跑快速检查（fmt / clippy / taplo / typos / 私钥）"
    echo "    commit-msg  校验 Conventional Commits（CHANGELOG 与版本推导依赖它）"
    echo "    pre-push    跑一遍 just ci（lint / test / audit）"
    echo "  临时跳过：git commit --no-verify / git push --no-verify"
    echo "  停用：git config --unset core.hooksPath"
