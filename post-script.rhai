// cargo-generate 生成后钩子（cargo-generate.toml 的 [hooks] post）。
//
// 运行时机：模板展开完成之后、文件被移动到目标目录之前，工作目录是临时的模板副本。
//
// 这里不做 `git init`（此刻还在临时目录）、不跑 `cargo fmt`（会顺带拉整条工具链）、
// 也不调 rustup 检查组件（Rhai 的 system::command 会让所有非交互生成都必须带
// `--allow-commands`）。组件检查改由 `just doctor` 负责。

let license = variable::get("license");
let toolchain = variable::get("toolchain");
let name = variable::get("project-name");
let ci = variable::get("ci");
let docker = variable::get("docker");
let async_runtime = variable::get("async_runtime");
let error_handling = variable::get("error_handling");
let logging = variable::get("logging");
let crate_type = variable::get("crate_type");
let is_bin = crate_type == "bin";

// 库项目选了 logging 也不会生成 telemetry.rs，下面据此给出说明
let ignored_for_lib = !is_bin && logging;

// 库项目的 Dockerfile / .dockerignore / docker.just 由 cargo-generate.toml 的
// [conditional.'crate_type == "lib"'] 一并 ignore 掉了，
// 下面所有 Docker 相关的提示都以这两个变量为准。
let docker_generated = docker && is_bin;
let docker_ignored_for_lib = docker && !is_bin;

// 检测「repo-owner 用了 GitLab 的 group/subgroup 写法，但 CI 平台不是 gitlab」，
// 这种组合拼出的 repository 地址在 GitHub 上是 404。
let owner = variable::get("repo-owner");
let owner_path_on_github = owner.contains("/") && ci != "gitlab";

// --- 1. 按用户选择的 License 收拾 LICENSE 文件 -----------------------------
//
// 选单一 License 时删掉另一个并改名成 LICENSE；选 MIT OR Apache 时两个都留着。

if license == "MIT" {
    file::delete("LICENSE-APACHE");
    file::rename("LICENSE-MIT", "LICENSE");
} else if license == "Apache-2.0" {
    file::delete("LICENSE-MIT");
    file::rename("LICENSE-APACHE", "LICENSE");
}

// --- 2. 换上生成项目自己的 README ------------------------------------------
//
// README.md 是模板自己的说明，删掉；_README.md 是给项目用的，改名顶上。

file::delete("README.md");
file::rename("_README.md", "README.md");

// --- 3. 依赖有变动时丢弃模板自带的 Cargo.lock ------------------------------
//
// 模板自带的 lock 只锁了根 crate 一个包，开关加了依赖就对不上，删掉让 cargo 重新解析。

let adds_dependencies = async_runtime || error_handling || (is_bin && logging);

let lock_regenerated = false;
if adds_dependencies {
    file::delete("Cargo.lock");
    lock_regenerated = true;
}

// --- 4. 打印下一步该做什么 --------------------------------------------------

print("");
print("项目 " + name + " 已生成");
print("  类型    " + crate_type + if is_bin { "（src/lib.rs 放逻辑，src/main.rs 只做收口）" } else { "" });
print("  工具链  " + toolchain);
print("  协议    " + license);
print("  CI      " + ci);
print("  Docker  " + if docker_generated { "是" } else { "否" });
print("  异步    " + if async_runtime { "tokio" } else { "无" });
print("  错误    " + if error_handling { if is_bin { "thiserror + anyhow" } else { "thiserror" } } else { "无" });
if is_bin {
    print("  日志    " + if logging { "tracing" } else { "无" });
}
print("");

if ignored_for_lib {
    print("说明：logging 只对 bin 项目生效——安装全局 subscriber 是应用的职责，");
    print("      库替调用方决定日志往哪儿写、按什么格式写是越界。本次已跳过。");
    print("      库里想发日志的话，只加 tracing 依赖、用它的宏即可，不要装 subscriber。");
    print("");
}

if docker_ignored_for_lib {
    print("说明：Docker 只对 bin 项目生效——库没有可执行入口，装进容器里也没东西可跑。");
    print("      Dockerfile / .dockerignore / docker.just 本次已跳过。");
    print("      要给库做个演示容器的话，先加一个 examples/ 或 bin target 再自己写 Dockerfile。");
    print("");
}

if owner_path_on_github {
    print("注意：仓库所有者填的是 `" + owner + "`（含 /），而 CI 平台不是 gitlab，");
    print("      于是 Cargo.toml 的 repository 被拼成了");
    print("        https://github.com/" + owner + "/" + name);
    print("      GitHub 没有子组，这个地址是 404，而该字段会随 cargo publish 进 crates.io。");
    print("      托管在 GitLab 的话把 ci 选成 gitlab 重新生成；否则请手工改掉 repository。");
    print("");
}

if lock_regenerated {
    print("提示：因为加了依赖，模板自带的 Cargo.lock 已删除（它只锁了根 crate 一个包）。");
    print("      先跑一次 `just bootstrap`（等价于 cargo fetch）重新生成，再连同代码一起提交——");
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
print("    just bootstrap       # 生成 Cargo.lock + 安装 git 钩子（首次）");
print("    just ci              # 跑一遍完整检查，确认环境就绪");
if docker_generated {
    print("    just docker-build    # 构建容器镜像");
}
print("");
print("`just` 可以列出全部命令；各配置文件的说明见 README.md。");
print("");
