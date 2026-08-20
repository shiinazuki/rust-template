//! {{ description }}
//!
//! 可执行入口，只负责两件事：初始化日志、把错误收口。
//! 业务逻辑一律放在 `src/lib.rs` 那一侧——`main.rs` 里的东西集成测试
//! （`tests/`）、benchmark 和 doctest 都够不着，留在这里就只能靠手工跑程序验证。
//!
//! 所以这个文件保持「薄」是有意的：它长起来了，就说明有东西该往库里挪了。
//!
//! 要解析命令行参数的话：`cargo add clap --features derive,env`，
//! 参数定义单独放进 `src/cli.rs`（derive 一个 `Cli` 结构体，测试里可以直接构造），
//! 这里只留 `let args = Cli::parse();` 一行。
{% if logging %}
mod telemetry;
{% endif %}{% if error_handling %}
use anyhow::Context as _;
{% endif %}
{% if async_runtime %}#[tokio::main]
async {% endif %}fn main(){% if error_handling %} -> anyhow::Result<()>{% endif %} {
{% if logging %}    telemetry::init("info");
{% endif %}    let name = String::from("world");
{% if error_handling %}    // 库返回的是具体的 Error（可以 match），到了这里才转成 anyhow::Error
    // 并补上下文——两层错误的分界线就在这两行之间。
    let greeting = {{ crate_name }}::greet(&name);
    let message = greeting.context("生成问候语失败")?;
{% else %}    let message = {{ crate_name }}::greet(&name);
{% endif %}{% if logging %}    // 日志走 stderr（给运维看），程序真正的输出走 stdout——见 telemetry.rs
    tracing::info!(name = %name, "已生成问候语");
{% endif %}    println!("{message}");
{% if error_handling %}
    Ok(())
{% endif %}}
