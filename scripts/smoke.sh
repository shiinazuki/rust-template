#!/usr/bin/env bash
#
# 模板自测：按矩阵生成若干种组合的项目，逐个跑格式化 / clippy / 测试。
#
#   bash scripts/smoke.sh            # 默认矩阵（9 组，覆盖各开关的开与关）
#   bash scripts/smoke.sh --full     # 完整矩阵（bin 的 4 个源码开关全排列 + lib + nightly）
#   bash scripts/smoke.sh --keep     # 跑完保留生成的项目，方便进去手工看
#
#   SMOKE_DOCKER=1 bash scripts/smoke.sh   # 顺便真的构建一次容器镜像（慢，默认关闭）
#
# 失败时会自动保留临时目录（否则连刚提示你去看的日志一起删了），跑通了才清理。
#
# ⚠️ 必须在模板仓库之外执行 cargo：模板根目录的 rust-toolchain.toml 里 channel 是
#    `{{ toolchain }}`，不是合法工具链名，rustup 会在 cargo 启动前就报错。
#    脚本因此先 cd 到临时目录，再用绝对路径指回模板。
set -uo pipefail

template=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workdir=$(mktemp -d "${TMPDIR:-/tmp}/rust-template-smoke.XXXXXX")

full=0
keep=0
for arg in "$@"; do
    case "$arg" in
        --full) full=1 ;;
        --keep) keep=1 ;;
        *) echo "未知参数: $arg" >&2; exit 2 ;;
    esac
done

# Ctrl-C 打断时也要清理：共用的 target 目录动辄几百 MB，
# 中途退出留下的临时目录不会有人记得删（除非 --keep 明确说了要留）。
on_signal() {
    [ "$keep" -eq 1 ] || rm -rf "$workdir"
    exit 130
}
trap on_signal INT TERM

# 所有组合共用一个 target 目录：依赖只编译一次，整体快一个数量级
export CARGO_TARGET_DIR="$workdir/.target"
export CARGO_TERM_COLOR=always

# CI 里会设 RUSTUP_TOOLCHAIN=stable 来绕开模板根目录那个非法的 rust-toolchain.toml。
# 它的优先级高于一切，留着会把生成项目自己声明的 channel 一并盖掉——
# 那样 toolchain=nightly 的组合就等于没测。这里显式解开。
unset RUSTUP_TOOLCHAIN

# 每行一个组合：名字 kind toolchain ci docker async error cli logging open_source
#
# ⚠️ toolchain 那一列不要清一色写 stable：nightly 才是模板的**默认值**，
#    而且 CI 里的 miri job 只在 nightly 下才跑。全测 stable 等于默认路径没人验过——
#    nightly 的 clippy/rustfmt 比 stable 严，生成的代码在它上面挂掉是很常见的事。
matrix=(
    "minimal            bin stable  none   false false false false false false"
    "full               bin stable  github true  true  true  true  true  true"
    "cli-only           bin stable  github false false false true  false false"
    "logging-only       bin stable  github false false false false true  false"
    "async-error        bin stable  gitlab false true  true  false false false"
    # gitlab + 社区文件：这一组专门盯 .gitlab/ 的 issue / MR 模板与根目录 CODEOWNERS
    # 有没有生成。曾经这里是个真 bug——社区文件挂在 .github/ 下，选 gitlab 时被整个删掉。
    "gitlab-oss        bin stable  gitlab false false true  false false true"
    "lib-full           lib stable  github false false true  false false true"
    "lib-minimal        lib stable  none   false false false false false false"
    # 长名字专测组。rustfmt 的 fn_call_width 默认是 60（不是 max_width 的 100），
    # 源码里凡是把 `{{ crate_name }}` 写进宏参数的地方，包名一长就会被 rustfmt 折行，
    # 于是生成出来的项目开箱就过不了 fmt --check。短名字的组合永远测不到这一点。
    # 写模板时的对策：先 `let x = <crate>::foo(...)`，再让断言只碰短变量名。
    "a-deliberately-long-package-name-for-rustfmt bin stable github false true true true true false"
    # 下面两组走 nightly：第一组就是「一路回车」的默认生成结果
    "nightly-default    bin nightly github false false true  false false false"
    "nightly-lib        lib nightly github false false true  false false false"
)
if [ "$full" -eq 1 ]; then
    matrix=()
    for a in false true; do for e in false true; do for c in false true; do for l in false true; do
        matrix+=("bin-a$a-e$e-c$c-l$l bin stable github false $a $e $c $l false")
    done; done; done; done
    for e in false true; do
        matrix+=("lib-e$e lib stable github false false $e false false false")
    done
    # nightly 的全开 / 全关两端，覆盖 stable 上测不到的 lint 差异
    matrix+=("nightly-min  bin nightly github false false false false false false")
    matrix+=("nightly-full bin nightly github true  true  true  true  true  true")
    matrix+=("nightly-lib  lib nightly github false false true  false false false")
    # 社区文件开关只影响生成哪些 md 文件，不影响能不能编译，各测一次就够
    matrix+=("oss-on  bin stable github false false true false false true")
    matrix+=("oss-off bin stable github false false true false false false")
    matrix+=("oss-gitlab bin stable gitlab false false true false false true")
    matrix+=("oss-none   bin stable none   false false true false false true")
fi

# 按生成时的开关断言文件布局。在生成项目的目录里调用。
# 每条不符的都打印出来（不提前 return），一次把问题看全。
assert_layout() {
    local kind=$1 ci=$2 docker=$3 err=$4 cli=$5 logging=$6 open_source=$7
    local bad=0

    have() {
        if [ ! -e "$1" ]; then echo "缺少：$1（$2）"; bad=1; fi
    }
    gone() {
        if [ -e "$1" ]; then echo "多出：$1（$2）"; bad=1; fi
    }

    # --- 与开关无关，永远该在 ---------------------------------------------
    for f in Cargo.toml README.md justfile rust-toolchain.toml rustfmt.toml clippy.toml \
             deny.toml .taplo.toml .typos.toml cliff.toml release.toml bacon.toml \
             .config/nextest.toml .pre-commit-config.yaml .editorconfig .gitattributes \
             .gitignore src/lib.rs tests/integration.rs; do
        have "$f" "所有组合都该生成"
    done

    # --- 只属于模板仓库，永远不该跟到生成项目里 ---------------------------
    for f in _README.md CHANGELOG.md template.just scripts \
             .github/workflows/template-ci.yaml; do
        gone "$f" "在 cargo-generate.toml 的 ignore / post-script 里"
    done

    # --- crate 类型 --------------------------------------------------------
    if [ "$kind" = "bin" ]; then
        have src/main.rs "bin 项目的入口"
    else
        gone src/main.rs "库没有可执行入口"
    fi

    # --- CI 平台 -----------------------------------------------------------
    case "$ci" in
        github)
            have .github/workflows/build.yaml "ci=github"
            have .github/dependabot.yml "ci=github"
            gone .gitlab-ci.yml "ci=github"
            ;;
        gitlab)
            have .gitlab-ci.yml "ci=gitlab"
            gone .github "ci=gitlab 时整个 .github/ 都不该生成"
            ;;
        none)
            gone .github "ci=none"
            gone .gitlab-ci.yml "ci=none"
            ;;
    esac

    # --- Docker（库项目一律没有） -----------------------------------------
    if [ "$docker" = true ] && [ "$kind" = bin ]; then
        have Dockerfile "docker=true"
        have .dockerignore "docker=true"
        have docker.just "docker=true"
    else
        gone Dockerfile "docker=false 或库项目"
        gone .dockerignore "docker=false 或库项目"
        gone docker.just "docker=false 或库项目"
    fi

    # --- 源码骨架开关 ------------------------------------------------------
    if [ "$err" = true ]; then have src/error.rs "error_handling=true"
    else gone src/error.rs "error_handling=false"; fi

    if [ "$cli" = true ] && [ "$kind" = bin ]; then have src/cli.rs "cli=true"
    else gone src/cli.rs "cli=false 或库项目"; fi

    if [ "$logging" = true ] && [ "$kind" = bin ]; then have src/telemetry.rs "logging=true"
    else gone src/telemetry.rs "logging=false 或库项目"; fi

    # --- 开源社区文件 ------------------------------------------------------
    # 这里是曾经出过 bug 的地方：CODEOWNERS 一度放在 .github/ 下，
    # 选 gitlab 时被 [conditional.'ci != "github"'] 连坐删掉。
    if [ "$open_source" = true ]; then
        have SECURITY.md "open_source=true"
        have CODE_OF_CONDUCT.md "open_source=true"
        have CONTRIBUTING.md "open_source=true"
        have CODEOWNERS "open_source=true；放根目录才能被 GitHub 和 GitLab 同时读到"
        case "$ci" in
            github)
                have .github/PULL_REQUEST_TEMPLATE.md "open_source=true + ci=github"
                have .github/ISSUE_TEMPLATE/bug_report.yml "open_source=true + ci=github"
                ;;
            gitlab)
                have .gitlab/issue_templates/Bug.md "open_source=true + ci=gitlab"
                have .gitlab/merge_request_templates/Default.md "open_source=true + ci=gitlab"
                ;;
        esac
    else
        gone SECURITY.md "open_source=false"
        gone CODE_OF_CONDUCT.md "open_source=false"
        gone CONTRIBUTING.md "open_source=false"
        gone CODEOWNERS "open_source=false"
        gone .gitlab "open_source=false"
        gone .github/PULL_REQUEST_TEMPLATE.md "open_source=false"
        gone .github/ISSUE_TEMPLATE "open_source=false"
    fi

    # --- License：单协议时改名成 LICENSE，双协议时两个都留着 --------------
    # 矩阵里目前统一用 MIT，所以这里只断言单协议的那条路径。
    have LICENSE "license=MIT 时 post-script 会把 LICENSE-MIT 改名成 LICENSE"
    gone LICENSE-MIT "已改名成 LICENSE"
    gone LICENSE-APACHE "选了 MIT，Apache 那份该删掉"

    return "$bad"
}

pass=0
fail=0
failed_names=()

for row in "${matrix[@]}"; do
    # shellcheck disable=SC2086
    set -- $row
    name=$1 kind=$2 toolchain=$3 ci=$4 docker=$5 async=$6 err=$7 cli=$8 logging=$9
    shift 9
    open_source=$1
    proj="smoke-$name"

    printf '\n\033[1m== %s ==\033[0m (%s / %s / ci=%s docker=%s async=%s error=%s cli=%s logging=%s oss=%s)\n' \
        "$name" "$kind" "$toolchain" "$ci" "$docker" "$async" "$err" "$cli" "$logging" "$open_source"

    (
        cd "$workdir" || exit 1
        cargo generate --path "$template" --name "$proj" "--$kind" --silent \
            --define description="smoke test $name" \
            --define repo-owner=example \
            --define toolchain="$toolchain" \
            --define license=MIT \
            --define ci="$ci" \
            --define docker="$docker" \
            --define async_runtime="$async" \
            --define error_handling="$err" \
            --define cli="$cli" \
            --define logging="$logging" \
            --define open_source="$open_source" \
            >"$workdir/$proj.gen.log" 2>&1
    ) || { echo "  ✗ 生成失败，日志见 $workdir/$proj.gen.log"; fail=$((fail + 1)); failed_names+=("$name(generate)"); continue; }

    ok=1
    cd "$workdir/$proj" || exit 1

    # 1. 生成出来的代码必须本来就是 rustfmt 干净的：模板里排版错一个空行，
    #    使用者第一次跑 CI 就会挂在 fmt --check 上。
    if ! cargo +nightly fmt --all -- --check >"$workdir/$proj.fmt.log" 2>&1; then
        echo "  ✗ fmt --check 不通过（$workdir/$proj.fmt.log）"; ok=0
    fi
    # 2. clippy 用和 CI 一样的严格度
    if ! cargo clippy --all-targets --all-features -- -D warnings >"$workdir/$proj.clippy.log" 2>&1; then
        echo "  ✗ clippy 不通过（$workdir/$proj.clippy.log）"; ok=0
    fi
    # 3. 测试（有 nextest 就用 nextest，没有就退回 cargo test）
    if command -v cargo-nextest >/dev/null 2>&1; then
        test_cmd=(cargo nextest run --all-targets --all-features)
    else
        test_cmd=(cargo test --all-features)
    fi
    if ! "${test_cmd[@]}" >"$workdir/$proj.test.log" 2>&1; then
        echo "  ✗ 测试不通过（$workdir/$proj.test.log）"; ok=0
    fi
    # 4. 有 lib target 就补一次 doctest（nextest 不跑 doctest；bin 项目也有 src/lib.rs）
    if [ -f src/lib.rs ] && ! cargo test --doc --all-features >"$workdir/$proj.doc.log" 2>&1; then
        echo "  ✗ doctest 不通过（$workdir/$proj.doc.log）"; ok=0
    fi
    # 5. 依赖审计：某个开关引入的新依赖可能带着不在 deny.toml allow 列表里的协议，
    #    那会让使用者第一次跑 CI 就失败，而且报错信息离「你选了哪个开关」很远。
    if command -v cargo-deny >/dev/null 2>&1 \
        && ! cargo deny check >"$workdir/$proj.deny.log" 2>&1; then
        echo "  ✗ cargo deny 不通过（$workdir/$proj.deny.log）"; ok=0
    fi
    # 6. 留下来的 Cargo.lock 必须和 Cargo.toml 对得上。模板自带的 lock 只锁了根 crate，
    #    某个开关加了依赖却没在 post-script 里删掉它的话，使用者第一次跑 CI（--locked）
    #    就会挂，而本地不带 --locked 的构建完全看不出来。
    if [ -f Cargo.lock ] && ! cargo metadata --locked --format-version 1 >"$workdir/$proj.lock.log" 2>&1; then
        echo "  ✗ Cargo.lock 与 Cargo.toml 不一致（$workdir/$proj.lock.log）"; ok=0
    fi
    # 7. justfile 至少要能被 just 解析
    if command -v just >/dev/null 2>&1 && ! just --list >"$workdir/$proj.just.log" 2>&1; then
        echo "  ✗ justfile 解析失败（$workdir/$proj.just.log）"; ok=0
    fi
    # 8. Markdown 表格中间不能出现空行——那会让表格直接断掉。
    #    这是 liquid 条件块最容易踩的坑：标签一旦独占一行，被裁掉的分支就会留下空行。
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 - README.md >"$workdir/$proj.md.log" 2>&1 <<'PY'
import sys

for path in sys.argv[1:]:
    lines = open(path).read().split("\n")
    for i in range(1, len(lines) - 1):
        prev, cur, nxt = lines[i - 1], lines[i], lines[i + 1]
        if cur.strip() == "" and prev.startswith("|") and nxt.startswith("|"):
            print(f"{path}:{i + 1} 表格中间有空行，Markdown 表格会在这里断开")
            sys.exit(1)
PY
        then
            echo "  ✗ README 的 Markdown 表格被空行截断（$workdir/$proj.md.log）"; ok=0
        fi
    fi
    # 9. 生成项目里的 TOML 必须是合法 TOML（模板里的 liquid 标签有没有漏掉锚定）
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 - <<'PY' >"$workdir/$proj.toml.log" 2>&1
import glob, sys, tomllib
bad = []
for f in ["Cargo.toml", "clippy.toml", "deny.toml", "rustfmt.toml", "release.toml",
          "bacon.toml", "rust-toolchain.toml", ".typos.toml", ".config/nextest.toml"]:
    try:
        with open(f, "rb") as fh:
            tomllib.load(fh)
    except FileNotFoundError:
        pass
    except Exception as exc:
        bad.append(f"{f}: {exc}")
if bad:
    print("\n".join(bad)); sys.exit(1)
PY
        then
            echo "  ✗ 生成项目里有非法 TOML（$workdir/$proj.toml.log）"; ok=0
        fi
    fi
    # 10. TOML 排版：生成项目的 CI 里有 `taplo fmt --check`，模板里的 TOML 一旦
    #     排版不合规，使用者第一次跑 CI 就会红在一个跟他毫无关系的地方。
    if command -v taplo >/dev/null 2>&1 \
        && ! taplo fmt --check >"$workdir/$proj.taplo.log" 2>&1; then
        echo "  ✗ taplo fmt --check 不通过（$workdir/$proj.taplo.log）"; ok=0
    fi
    # 11. 生成项目里不该残留没被渲染的 liquid 占位符。
    #     这是最廉价也最有效的一条：变量改名漏了一处、`{% raw %}` 忘了配对，
    #     症状都是文件里明晃晃留着 `{{ ... }}`——而编译 / clippy / 测试统统发现不了，
    #     因为它们多半藏在注释和文档里。
    #
    #     排除的这几个文件正是 cargo-generate.toml 里 `exclude` 的那几个：
    #     它们本来就不做 liquid 替换，花括号属于 just / Tera / Actions 自己的语法。
    #     改动 exclude 列表时记得同步这里。
    if grep -rIn -e '{{' -e '{%' . \
        --exclude-dir=target --exclude-dir=.git --exclude-dir=workflows \
        --exclude=justfile --exclude=docker.just --exclude=release.toml \
        --exclude=cliff.toml --exclude=.pre-commit-config.yaml --exclude=.gitlab-ci.yml \
        >"$workdir/$proj.liquid.log" 2>&1; then
        echo "  ✗ 生成项目里残留未渲染的 liquid 占位符（$workdir/$proj.liquid.log）"; ok=0
    fi
    # 12. 按开关断言「该有的文件在、不该有的文件不在」。
    #     前面所有检查都只看「编不编得过」，而 conditional / ignore 写错的典型症状是
    #     **少了一个文件**：代码照样编过，问题要等使用者去用那个功能时才暴露。
    if ! assert_layout "$kind" "$ci" "$docker" "$err" "$cli" "$logging" "$open_source" \
        >"$workdir/$proj.layout.log" 2>&1; then
        echo "  ✗ 生成的文件清单和开关对不上（$workdir/$proj.layout.log）"; ok=0
    fi
    # 13. 真正构建一次容器镜像。默认**关闭**（SMOKE_DOCKER=1 打开）：容器里是从零编译，
    #     一组就要好几分钟，挂在每次 PR 上不划算。模板 CI 里只有每周的完整矩阵会打开它。
    #     不测的话，Dockerfile 坏掉要等到某个使用者生成完项目、推上去跑 CI 才发现。
    if [ "${SMOKE_DOCKER:-0}" = "1" ] && [ -f Dockerfile ] && command -v docker >/dev/null 2>&1; then
        if ! DOCKER_BUILDKIT=1 docker build -t "smoke-$proj:test" . \
            >"$workdir/$proj.docker.log" 2>&1; then
            echo "  ✗ docker build 失败（$workdir/$proj.docker.log）"; ok=0
        else
            docker rmi -f "smoke-$proj:test" >/dev/null 2>&1 || true
        fi
    fi
    cd "$workdir" || exit 1

    if [ "$ok" -eq 1 ]; then
        echo "  ✓ 通过"
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failed_names+=("$name")
    fi
done

echo ""
echo "========================================"
echo "通过 $pass 组，失败 $fail 组"
if [ "$fail" -gt 0 ]; then
    printf '失败的组合：%s\n' "${failed_names[*]}"
fi
# 有失败就必须保留：上面每条 ✗ 都指向 $workdir 里的一个日志文件，
# 无条件 rm -rf 会把刚让你去看的东西一起删掉。跑通了才清理。
if [ "$keep" -eq 1 ]; then
    echo "生成的项目保留在 $workdir"
elif [ "$fail" -gt 0 ]; then
    echo "生成的项目与日志保留在 $workdir"
    echo "（排查完直接 rm -rf 掉即可）"
else
    rm -rf "$workdir"
fi
[ "$fail" -eq 0 ]
