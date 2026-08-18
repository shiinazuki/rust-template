// cargo-generate 生成后钩子：按用户选择的 License 收拾 LICENSE 文件。
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
