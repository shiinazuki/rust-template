# 模板仓库自己的维护命令，不进入生成的项目。
# 模板根目录跑不了 cargo，需要编译的检查由 smoke.sh 在临时目录里生成项目后执行。

[group('template')]
[doc('自测：按矩阵生成项目并逐个跑检查（10 组，含 2 组 nightly、3 种协议）')]
smoke:
    bash scripts/smoke.sh

[group('template')]
[doc('自测完整矩阵：bin 全排列 + lib + nightly + CI 平台 + 协议（19 组，较慢）')]
smoke-full:
    bash scripts/smoke.sh --full

[group('template')]
[doc('自测并保留生成的项目，方便进去手工检查')]
smoke-keep:
    bash scripts/smoke.sh --keep

[group('template')]
[doc('检查模板仓库自身：TOML + 拼写 + workflow 审计 + shell 脚本 + 文档链接')]
template-lint:
    #!/usr/bin/env bash
    set -uo pipefail
    fail=0
    # 同时校验 liquid 标签没有破坏 TOML 语法
    echo "== taplo（TOML 排版与语法）=="
    if command -v taplo >/dev/null 2>&1; then
        taplo fmt --check || fail=1
    else
        echo "  - 未安装 taplo，跳过（cargo binstall taplo-cli）"
    fi
    echo "== typos（拼写）=="
    if command -v typos >/dev/null 2>&1; then
        typos || fail=1
    else
        echo "  - 未安装 typos，跳过（cargo binstall typos-cli）"
    fi
    echo "== zizmor（workflow 与 dependabot 安全审计）=="
    if command -v zizmor >/dev/null 2>&1; then
        zizmor --min-severity medium --no-progress .github || fail=1
    else
        echo "  - 未安装 zizmor，跳过（cargo binstall zizmor）"
    fi
    echo "== actionlint（workflow 语法与表达式）=="
    if command -v actionlint >/dev/null 2>&1; then
        actionlint -color || fail=1
    else
        # actionlint 是 Go 写的，crates.io 上没有同名包，不能用 cargo binstall 装
        echo "  - 未安装 actionlint，跳过（brew install actionlint，或去 releases 页下二进制）"
    fi
    echo "== shellcheck =="
    if command -v shellcheck >/dev/null 2>&1; then
        # .githooks/ 一并检查
        shellcheck scripts/*.sh .githooks/* || fail=1
    else
        echo "  - 未安装 shellcheck，跳过（brew install shellcheck）"
    fi
    # 文档死链检查，需要访问外网，只在本地跑
    echo "== lychee（文档链接）=="
    if command -v lychee >/dev/null 2>&1; then
        lychee --no-progress README.md _README.md '*.md' 'docs/*.md' || fail=1
    else
        echo "  - 未安装 lychee，跳过（cargo binstall lychee）"
    fi
    exit "$fail"

[group('template')]
[doc('提示 workflow 里钉死的 action hash 该怎么更新')]
template-update:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "workflow 里的 action 是用 commit hash 钉死的，由 dependabot 每周自动升级。"
    # 用单引号：双引号里的反引号会被 bash 当成命令替换
    echo '想手动来一次的话，对照 .github/workflows/*.yaml 里 `# vX.Y.Z` 注释逐个更新：'
    echo "    gh api repos/<owner>/<repo>/commits/<tag> --jq .sha"
