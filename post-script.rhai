// cargo-generate 生成后钩子（cargo-generate.toml 的 [hooks] post）。
//
// 运行时机：模板展开完成之后、文件被移动到目标目录之前，工作目录是临时的模板副本。
// 这个顺序是有意为之——脚本报错时不会在用户的目标目录里留下一半成品。
//
// ⚠️ 因此这里**不做** `git init`：此刻还在临时目录里，初始化的仓库不会跟到目标位置。
//    cargo-generate 会在最终目录 `git init`，但**不会**替你提交——生成完之后
//    所有文件都还是 untracked 状态。首次提交要自己来，下面的提示里列了命令。
// ⚠️ 这里也**不跑** `cargo fmt`：模板里的源码本来就是 rustfmt 干净的，而在临时目录
//    触发 cargo 会顺带把 rust-toolchain.toml 声明的整条工具链拉下来（几百 MB，
//    还可能因离线而失败）。真要格式化，生成后跑 `just fmt` 即可。
// ⚠️ 这里同样**不调用 rustup 检查组件**，尽管那是很自然的想法。原因是 Rhai 的
//    `system::command` 受 cargo-generate 的命令确认机制管辖：
//      - 交互式生成时，每执行一条外部命令都会弹一次 y/n 确认；
//      - `--silent`（脚本 / CI 里生成）时直接报错中止：
//          Cannot prompt for system command confirmation in silent mode.
//          Use --allow-commands if you want to allow the template to run system commands
//    也就是说，钩子里只要出现一条 system::command，所有非交互生成都必须额外带上
//    `--allow-commands`，否则就得给模板包一层 try/catch 把检查悄悄跳过——两者都不划算。
//    组件检查因此挪到了 `just doctor`：在真正的项目目录里跑，随时可重跑，
//    不受生成期的限制，也能顺带把 cargo 工具一起查了。

let license = variable::get("license");
let toolchain = variable::get("toolchain");
let name = variable::get("project-name");
let ci = variable::get("ci");
let docker = variable::get("docker");
let async_runtime = variable::get("async_runtime");
let error_handling = variable::get("error_handling");
let cli = variable::get("cli");
let logging = variable::get("logging");
let open_source = variable::get("open_source");
let crate_type = variable::get("crate_type");
let is_bin = crate_type == "bin";

// cli / logging 是应用层的事：解析命令行、安装全局 subscriber 都不该由库来做。
// 库项目选了这两项也不会生成对应文件，这里明说一声，免得用户以为是 bug。
let ignored_for_lib = !is_bin && (cli || logging);

// docker 同理：库没有可执行入口，Dockerfile / .dockerignore / docker.just 由
// cargo-generate.toml 的 [conditional.'crate_type == "lib"'] 一并 ignore 掉了。
// 下面所有和 Docker 有关的提示都必须看这个变量，不能只看用户选了什么——
// 否则会出现「提示你去跑 just docker-build，但那个配方根本不存在」。
let docker_generated = docker && is_bin;
let docker_ignored_for_lib = docker && !is_bin;

// 开源社区文件里，.github/ 下的那三份（CODEOWNERS / PR 模板 / issue 模板）
// 受 [conditional.'ci != "github"'] 管辖：CI 选了 gitlab 或 none 时整个 .github/
// 都不会生成，于是六份社区文件只出来三份。这不是 bug，但必须说一声。
let oss_partial = open_source && ci != "github";

// --- 1. 按用户选择的 License 收拾 LICENSE 文件 -----------------------------
//
// 模板里同时放着 LICENSE-MIT 和 LICENSE-APACHE：
//   - 选单一 License   -> 删掉另一个，剩下的那个改名成 LICENSE（GitHub / crates.io 的惯例）
//   - 选 MIT OR Apache -> 两个都留着，Rust 生态双协议项目的标准做法

if license == "MIT" {
    file::delete("LICENSE-APACHE");
    file::rename("LICENSE-MIT", "LICENSE");
} else if license == "Apache-2.0" {
    file::delete("LICENSE-MIT");
    file::rename("LICENSE-APACHE", "LICENSE");
}

// --- 2. 换上生成项目自己的 README ------------------------------------------
//
// 仓库根目录的 README.md 是「怎么用这个模板」的说明，对生成出来的项目没有意义；
// 真正要给项目用的是 _README.md（做过变量替换）。详见 cargo-generate.toml 里的注释。

file::delete("README.md");
file::rename("_README.md", "README.md");

// --- 3. 依赖有变动时丢弃模板自带的 Cargo.lock ------------------------------
//
// 模板里的 Cargo.lock 只锁了根 crate 一个包。一旦某个开关往 Cargo.toml 里加了依赖，
// 这份 lock 就对不上了——而 CI 全程用 `--locked`，会直接失败。
// 与其留一个必然过期的文件，不如删掉，让 cargo 首次构建时重新解析。
let adds_dependencies = async_runtime
    || error_handling
    || (is_bin && cli)
    || (is_bin && logging);

let lock_regenerated = false;
if adds_dependencies {
    file::delete("Cargo.lock");
    lock_regenerated = true;
}

// --- 3.5 清掉被 ignore 掏空的空目录 ----------------------------------------
//
// bin 项目会 ignore 掉 tests/integration.rs，但承载它的 tests/ 目录仍会留下来，
// 生成出一个空文件夹。git 不跟踪空目录，所以不影响仓库，只是本地看着碍眼。

if variable::get("crate_type") == "bin" {
    file::delete("tests");
}

// --- 4. 打印下一步该做什么 --------------------------------------------------

print("");
print("项目 " + name + " 已生成");
print("  类型    " + crate_type);
print("  工具链  " + toolchain);
print("  协议    " + license);
print("  CI      " + ci);
print("  Docker  " + if docker_generated { "是" } else { "否" });
print("  异步    " + if async_runtime { "tokio" } else { "无" });
print("  错误    " + if error_handling { if is_bin { "thiserror + anyhow" } else { "thiserror" } } else { "无" });
if is_bin {
    print("  命令行  " + if cli { "clap" } else { "无" });
    print("  日志    " + if logging { "tracing" } else { "无" });
}
print("  社区文件 " + if open_source { "已生成" } else { "无（个人 / 私有项目不需要）" });
print("");

if ignored_for_lib {
    print("说明：cli / logging 只对 bin 项目生效——解析命令行、安装全局 subscriber");
    print("      都是应用的职责，库替调用方做这些决定是越界。本次已跳过。");
    print("      库里想发日志的话，只加 tracing 依赖、用它的宏即可，不要装 subscriber。");
    print("");
}

if docker_ignored_for_lib {
    print("说明：Docker 只对 bin 项目生效——库没有可执行入口，装进容器里也没东西可跑。");
    print("      Dockerfile / .dockerignore / docker.just 本次已跳过。");
    print("      要给库做个演示容器的话，先加一个 examples/ 或 bin target 再自己写 Dockerfile。");
    print("");
}

if oss_partial {
    print("说明：CI 平台选的是 " + ci + "，整个 .github/ 目录不会生成，因此社区文件里");
    print("      CODEOWNERS / PULL_REQUEST_TEMPLATE.md / ISSUE_TEMPLATE/ 这三份本次已跳过，");
    print("      只生成了 SECURITY.md / CODE_OF_CONDUCT.md / CONTRIBUTING.md。");
    if ci == "gitlab" {
        print("      GitLab 的对应物是 .gitlab/issue_templates/ 与 .gitlab/merge_request_templates/，");
        print("      需要的话按 GitLab 文档自己补一份。");
    }
    print("");
}

if lock_regenerated {
    print("提示：因为加了依赖，模板自带的 Cargo.lock 已删除（它只锁了根 crate 一个包）。");
    print("      先跑一次 `cargo check` 重新生成，再连同代码一起提交——");
    print("      CI 全程用 --locked，没有 lock 会直接失败。");
    if docker_generated {
        print("      `just docker-build` 同理：容器里的构建也是 --locked。");
    }
    print("");
}

print("接下来：");
print("    cd " + name);
print("");
print("    # cargo-generate 只做了 git init，首次提交要自己来");
print("    git add -A");
print("    git commit -m \"chore: 从模板初始化项目\"");
print("");
print("    just doctor          # 体检：工具链组件与配套 cargo 工具是否齐全");
print("    just install-tools   # 安装配套 cargo 工具（首次，建议先装 cargo-binstall 提速）");
print("    just hooks           # 安装 git 钩子（首次，需要先装 pre-commit）");
print("    just ci              # 跑一遍完整检查，确认环境就绪");
if docker_generated {
    print("    just docker-build    # 构建容器镜像");
}
print("");
print("`just` 可以列出全部命令；各配置文件的说明见 README.md。");
print("");
