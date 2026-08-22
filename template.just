# 模板仓库**自己的**维护命令。
#
# 这个文件在 cargo-generate.toml 的 ignore 列表里，不会进入生成的项目；
# 根 justfile 用 `import? 'template.just'` 可选加载，生成项目里文件不存在就静默跳过。
#
# ⚠️ 模板仓库根目录跑不了 cargo：rust-toolchain.toml 里的 channel 是 `{{ toolchain }}`，
#    不是合法工具链名，rustup 会在 cargo 启动前就报错。所以下面的配方都不直接调 cargo，
#    smoke.sh 内部会先 cd 到临时目录再动手。

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
    # 模板里十几个 TOML 必须同时是合法 TOML —— 「liquid 标签只能锚在注释行行尾」
    # 那条约定一旦被破坏，这里会立刻发现。
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
    echo "== zizmor（workflow 安全审计）=="
    if command -v zizmor >/dev/null 2>&1; then
        zizmor --min-severity medium --no-progress .github/workflows || fail=1
    else
        echo "  - 未安装 zizmor，跳过（cargo binstall zizmor）"
    fi
    echo "== actionlint（workflow 语法与表达式）=="
    if command -v actionlint >/dev/null 2>&1; then
        actionlint -color || fail=1
    else
        # actionlint 是 Go 写的，crates.io 上没有同名包——`cargo binstall actionlint`
        # 会以「not found」失败，别照着 zizmor 那行的样子写。
        echo "  - 未安装 actionlint，跳过（brew install actionlint，或去 releases 页下二进制）"
    fi
    echo "== shellcheck =="
    if command -v shellcheck >/dev/null 2>&1; then
        # .githooks/ 一并检查：它们会在每个使用者的机器上执行
        shellcheck scripts/*.sh .githooks/* || fail=1
    else
        echo "  - 未安装 shellcheck，跳过（brew install shellcheck）"
    fi
    # README.md + _README.md 加起来七百多行，几乎全是链接。文档死链是最容易
    # 悄悄积累的债：写的时候不报错，等有人点开才发现。
    #
    # 刻意**不**放进 CI：lychee 要真的去访问外网，限流、临时 502、需要登录的站点
    # 都会让它随机变红——一个三天两头误报的 job 很快就没人看了。
    # 放在这里，改完文档手动跑一次即可。
    echo "== lychee（文档链接）=="
    if command -v lychee >/dev/null 2>&1; then
        lychee --no-progress README.md _README.md '*.md' || fail=1
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
    # 用单引号：双引号里的反引号会被 bash 当成命令替换，`# vX.Y.Z` 会整段消失
    echo '想手动来一次的话，对照 .github/workflows/*.yaml 里 `# vX.Y.Z` 注释逐个更新：'
    echo "    gh api repos/<owner>/<repo>/commits/<tag> --jq .sha"
