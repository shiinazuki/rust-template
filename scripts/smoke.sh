#!/usr/bin/env bash
#
# 模板自测：按矩阵生成项目，逐个跑与 CI 相同的检查。
#
#   bash scripts/smoke.sh                  # 默认矩阵（10 组）
#   bash scripts/smoke.sh --full           # 完整矩阵（19 组）
#   bash scripts/smoke.sh --keep           # 跑完保留生成的项目
#   SMOKE_DOCKER=1 bash scripts/smoke.sh   # 另外构建容器镜像（慢）
#
# 失败时保留临时目录与各步骤的日志。
set -uo pipefail

template=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workdir=$(mktemp -d "${TMPDIR:-/tmp}/rust-template-smoke.XXXXXX")

full=0
keep=0
for arg in "$@"; do
    case "$arg" in
        # 忽略空参数
        "") ;;
        --full) full=1 ;;
        --keep) keep=1 ;;
        *) echo "未知参数: $arg" >&2; exit 2 ;;
    esac
done

# Ctrl-C 打断时也清理临时目录（--keep 时保留）
on_signal() {
    [ "$keep" -eq 1 ] || rm -rf "$workdir"
    exit 130
}
trap on_signal INT TERM

# 所有组合共用一个 target 目录
export CARGO_TARGET_DIR="$workdir/.target"
export CARGO_TERM_COLOR=always

# 让生成项目的 rust-toolchain.toml 生效（template-ci 设了 RUSTUP_TOOLCHAIN）
unset RUSTUP_TOOLCHAIN

# 每行一个组合：名字 kind toolchain ci docker async error logging license
# 行按空格拆分，license 列用 dual 代表 MIT OR Apache-2.0
matrix=(
    "minimal            bin stable  none   false false false false MIT"
    # 全开组兼测双协议
    "full               bin stable  github true  true  true  true  dual"
    "logging-only       bin stable  github false false false true  MIT"
    # gitlab 组：生成 .gitlab-ci.yml、不生成 .github/
    "async-error        bin stable  gitlab false true  true  false MIT"
    "lib-full           lib stable  github false false true  false Apache-2.0"
    "lib-minimal        lib stable  none   false false false false MIT"
    # lib + async：tokio 落在 [dev-dependencies]
    "lib-async          lib stable  github false true  true  false MIT"
    # 长包名：源码模板里的调用不能被 rustfmt 折行
    "a-deliberately-long-package-name-for-rustfmt bin stable github false true true true MIT"
    # nightly 工具链
    "nightly-bin        bin nightly github false false true  false MIT"
    "nightly-lib        lib nightly github false false true  false MIT"
)
if [ "$full" -eq 1 ]; then
    matrix=()
    for a in false true; do for e in false true; do for l in false true; do
        matrix+=("bin-a$a-e$e-l$l bin stable github false $a $e $l MIT")
    done; done; done
    for a in false true; do for e in false true; do
        matrix+=("lib-a$a-e$e lib stable github false $a $e false MIT")
    done; done
    # nightly 的全开 / 全关两端
    matrix+=("nightly-min  bin nightly github false false false false MIT")
    matrix+=("nightly-full bin nightly github true  true  true  true  MIT")
    matrix+=("nightly-lib  lib nightly github false false true  false MIT")
    # CI 平台的另外两种取值
    matrix+=("ci-gitlab  bin stable gitlab false false true true MIT")
    matrix+=("ci-none    bin stable none   false false true true MIT")
    # 协议名含 `-` 时的徽章转义
    matrix+=("lic-apache bin stable github false false true false Apache-2.0")
    matrix+=("lic-dual   bin stable github false false true false dual")
fi

# 按生成时的开关断言文件布局，在生成项目的目录里调用，列出全部不符项
assert_layout() {
    local kind=$1 ci=$2 docker=$3 err=$4 logging=$5 license=$6
    local bad=0

    have() {
        if [ ! -e "$1" ]; then echo "缺少：$1（$2）"; bad=1; fi
    }
    gone() {
        if [ -e "$1" ]; then echo "多出：$1（$2）"; bad=1; fi
    }

    # --- 与开关无关，永远该在 ---------------------------------------------
    for f in Cargo.toml README.md CLAUDE.md justfile rust-toolchain.toml rustfmt.toml clippy.toml \
             deny.toml .taplo.toml .typos.toml cliff.toml release.toml bacon.toml \
             .config/nextest.toml .config/template-values.toml .cargo/config.toml \
             docs/development.md .githooks/pre-commit .githooks/commit-msg .githooks/pre-push \
             .editorconfig .gitattributes .gitignore src/lib.rs tests/integration.rs; do
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
            have .github/workflows/workflows.yaml "ci=github"
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

    # --- dependabot 的 docker ecosystem 跟着 Dockerfile 走 -------------------
    if [ "$ci" = github ]; then
        if grep -q 'package-ecosystem: docker' .github/dependabot.yml; then
            if [ "$docker" != true ] || [ "$kind" != bin ]; then
                echo "多出：.github/dependabot.yml 里的 docker ecosystem（这个项目没有 Dockerfile）"
                bad=1
            fi
        elif [ "$docker" = true ] && [ "$kind" = bin ]; then
            echo "缺少：.github/dependabot.yml 里的 docker ecosystem（docker=true）"
            bad=1
        fi
    fi

    # --- 源码骨架开关 ------------------------------------------------------
    if [ "$err" = true ]; then have src/error.rs "error_handling=true"
    else gone src/error.rs "error_handling=false"; fi

    if [ "$logging" = true ] && [ "$kind" = bin ]; then have src/telemetry.rs "logging=true"
    else gone src/telemetry.rs "logging=false 或库项目"; fi

    # --- 开源社区文件：模板不再生成，任何组合下都不该冒出来 ----------------
    for f in SECURITY.md CODE_OF_CONDUCT.md CONTRIBUTING.md CODEOWNERS \
             .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE .gitlab; do
        gone "$f" "社区文件已从模板移除"
    done

    # --- License：单协议时改名成 LICENSE，双协议时两个都留着 --------------
    if [ "$license" = "MIT OR Apache-2.0" ]; then
        have LICENSE-MIT "双协议：两份都留着，这是 Rust 生态的标准做法"
        have LICENSE-APACHE "双协议：两份都留着"
        gone LICENSE "双协议不改名"
    else
        have LICENSE "单协议时 post-script 会把选中的那份改名成 LICENSE"
        gone LICENSE-MIT "已改名成 LICENSE，或不是选中的那个协议"
        gone LICENSE-APACHE "已改名成 LICENSE，或不是选中的那个协议"
    fi

    # README 的 license 徽章：`-` 转义成 `--`，空格转成 %20
    local badge expected
    badge=$(grep -o 'img\.shields\.io/badge/license-[^)]*' README.md)
    expected="img.shields.io/badge/license-$(printf '%s' "$license" |
        sed -e 's/-/--/g' -e 's/ /%20/g')-blue"
    if [ "$badge" != "$expected" ]; then
        echo "license 徽章 URL 不对：$badge"
        echo "                 期望：$expected"
        bad=1
    fi

    return "$bad"
}

# 缺少任何一个工具就退出
missing_tools=""
for t in cargo-generate cargo-nextest cargo-deny just taplo typos python3; do
    command -v "$t" >/dev/null 2>&1 || missing_tools="$missing_tools $t"
done
if [ -n "$missing_tools" ]; then
    printf '\033[31m缺少工具：%s\033[0m\n' "$missing_tools" >&2
    exit 2
fi

pass=0
fail=0
failed_names=()

for row in "${matrix[@]}"; do
    # shellcheck disable=SC2086
    set -- $row
    name=$1 kind=$2 toolchain=$3 ci=$4 docker=$5 async=$6 err=$7 logging=$8 license=$9
    case "$license" in
        dual) license="MIT OR Apache-2.0" ;;
    esac
    proj="smoke-$name"

    printf '\n\033[1m== %s ==\033[0m (%s / %s / ci=%s docker=%s async=%s error=%s logging=%s license=%s)\n' \
        "$name" "$kind" "$toolchain" "$ci" "$docker" "$async" "$err" "$logging" "$license"

    (
        cd "$workdir" || exit 1
        cargo generate --path "$template" --name "$proj" "--$kind" --silent \
            --define description="smoke test $name" \
            --define repo-owner=example \
            --define toolchain="$toolchain" \
            --define license="$license" \
            --define ci="$ci" \
            --define docker="$docker" \
            --define async_runtime="$async" \
            --define error_handling="$err" \
            --define logging="$logging" \
            >"$workdir/$proj.gen.log" 2>&1
    ) || { echo "  ✗ 生成失败，日志见 $workdir/$proj.gen.log"; fail=$((fail + 1)); failed_names+=("$name(generate)"); continue; }

    ok=1
    cd "$workdir/$proj" || exit 1

    # 1. 按 .config/template-values.toml 原地重新生成，结果必须与刚生成的一致
    git add -A && git -c user.name=smoke -c user.email=smoke@example.com commit -qm init
    if ! cargo generate --path "$template" --name "$proj" "--$kind" --silent \
            --values-file .config/template-values.toml --init --overwrite \
            >"$workdir/$proj.sync.log" 2>&1 \
        || [ -n "$(git status --porcelain)" ]; then
        git status --short >>"$workdir/$proj.sync.log"
        echo "  ✗ 按 .config/template-values.toml 原地重新生成后有差异（$workdir/$proj.sync.log）"; ok=0
    fi
    # 2. 留下来的 Cargo.lock 必须和 Cargo.toml 对得上（CI 全程用 --locked）
    if [ -f Cargo.lock ] && ! cargo metadata --locked --format-version 1 >"$workdir/$proj.lock.log" 2>&1; then
        echo "  ✗ Cargo.lock 与 Cargo.toml 不一致（$workdir/$proj.lock.log）"; ok=0
    fi
    # 3. 与 CI 相同的检查，先生成 Cargo.lock
    cargo fetch >"$workdir/$proj.fetch.log" 2>&1
    # minimal-versions 只在纯库项目上执行
    for recipe in lint test audit minimal-versions; do
        if ! just "$recipe" >"$workdir/$proj.$recipe.log" 2>&1; then
            echo "  ✗ just $recipe 不通过（$workdir/$proj.$recipe.log）"; ok=0
        fi
    done
    # 4. Markdown 表格中间没有空行（独占一行的 liquid 标签被裁掉后会留下空行）
    if ! python3 - README.md docs/development.md >"$workdir/$proj.md.log" 2>&1 <<'PY'
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
        echo "  ✗ Markdown 表格被空行截断（$workdir/$proj.md.log）"; ok=0
    fi
    # 5. 生成项目里的 TOML 都合法
    if ! python3 - <<'PY' >"$workdir/$proj.toml.log" 2>&1
import sys, tomllib
bad = []
for f in ["Cargo.toml", "clippy.toml", "deny.toml", "rustfmt.toml", "release.toml",
          "bacon.toml", "rust-toolchain.toml", ".typos.toml", ".config/nextest.toml",
          ".cargo/config.toml", ".config/template-values.toml"]:
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
    # 6. 没有残留未渲染的 liquid 占位符，排除的文件与 cargo-generate.toml 的 exclude 保持一致
    if grep -rIn -e '{{' -e '{%' . \
        --exclude-dir=target --exclude-dir=.git --exclude-dir=workflows \
        --exclude=justfile --exclude=docker.just --exclude=release.toml \
        --exclude=cliff.toml --exclude-dir=.githooks --exclude=.gitlab-ci.yml \
        >"$workdir/$proj.liquid.log" 2>&1; then
        echo "  ✗ 生成项目里残留未渲染的 liquid 占位符（$workdir/$proj.liquid.log）"; ok=0
    fi
    # 7. 文件布局与开关一致
    if ! assert_layout "$kind" "$ci" "$docker" "$err" "$logging" "$license" \
        >"$workdir/$proj.layout.log" 2>&1; then
        echo "  ✗ 生成的文件清单和开关对不上（$workdir/$proj.layout.log）"; ok=0
    fi
    # 8. SMOKE_DOCKER=1 时构建容器镜像
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
# 有失败时保留日志
if [ "$keep" -eq 1 ]; then
    echo "生成的项目保留在 $workdir"
elif [ "$fail" -gt 0 ]; then
    echo "生成的项目与日志保留在 $workdir"
    echo "（排查完直接 rm -rf 掉即可）"
else
    rm -rf "$workdir"
fi
[ "$fail" -eq 0 ]
