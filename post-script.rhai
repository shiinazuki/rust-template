// cargo-generate 生成后钩子（cargo-generate.toml 的 [hooks] post）。
//
// 运行时机：模板展开完成之后、文件被移动到目标目录之前，工作目录是临时的模板副本。
// 这个顺序是有意为之——脚本报错时不会在用户的目标目录里留下一半成品。
//
// ⚠️ 因此这里**不做** `git init`：此刻还在临时目录里，初始化的仓库不会跟到目标位置。
//    cargo-generate 本身就会在最终目录建好 git 仓库并完成首次提交，无需重复。
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
// 模板里的 Cargo.lock 只锁了根 crate 一个包。选了 async_runtime 之后 Cargo.toml
// 多出 tokio，这份 lock 就对不上了——而 CI 全程用 `--locked`，会直接失败。
// 与其留一个必然过期的文件，不如删掉让 cargo 首次构建时重新解析。

let lock_regenerated = false;
if async_runtime {
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
print("  工具链  " + toolchain);
print("  协议    " + license);
print("  CI      " + ci);
print("  Docker  " + if docker { "是" } else { "否" });
print("  异步    " + if async_runtime { "tokio" } else { "无" });
print("");

if lock_regenerated {
    print("提示：因为加入了 tokio，模板自带的 Cargo.lock 已删除。");
    print("      首次 `cargo check` 会重新生成，记得把它一起提交——CI 全程用 --locked。");
    print("");
}

print("接下来：");
print("    cd " + name);
print("    just doctor          # 体检：工具链组件与配套 cargo 工具是否齐全");
print("    just install-tools   # 安装配套 cargo 工具（首次，建议先装 cargo-binstall 提速）");
print("    just hooks           # 安装 git 钩子（首次，需要先装 pre-commit）");
print("    just ci              # 跑一遍完整检查，确认环境就绪");
if docker {
    print("    just docker-build    # 构建容器镜像");
}
print("");
print("`just` 可以列出全部命令；各配置文件的说明见 README.md。");
print("");
