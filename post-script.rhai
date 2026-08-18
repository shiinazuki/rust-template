// cargo-generate 生成后钩子。
// 运行时机：模板展开完成之后、文件被移动到目标目录之前，工作目录是临时的模板副本。

// --- 1. 按用户选择的 License 收拾 LICENSE 文件 -----------------------------
//
// 模板里同时放着 LICENSE-MIT 和 LICENSE-APACHE：
//   - 选单一 License   -> 删掉另一个，剩下的那个改名成 LICENSE（GitHub / crates.io 的惯例）
//   - 选 MIT OR Apache -> 两个都留着，Rust 生态双协议项目的标准做法

let license = variable::get("license");

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

// --- 3. 打印下一步该做什么 --------------------------------------------------

let name = variable::get("project-name");
let toolchain = variable::get("toolchain");

print("");
print("项目 " + name + " 已生成（工具链：" + toolchain + "，协议：" + license + "）");
print("");
print("接下来：");
print("    cd " + name);
print("    just install-tools   # 安装配套 cargo 工具（首次，建议先装 cargo-binstall 提速）");
print("    just hooks           # 安装 git 钩子（首次，需要先装 pre-commit）");
print("    just ci              # 跑一遍完整检查，确认环境就绪");
print("");
print("`just` 可以列出全部命令；各配置文件的说明见 README.md。");
print("");
