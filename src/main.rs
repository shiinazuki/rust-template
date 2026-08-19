//! {{ description }}
//!
//! 可执行入口，只负责三件事：解析参数、初始化日志、把错误收口。
//! 业务逻辑一律放在 `src/lib.rs` 那一侧——`main.rs` 里的东西集成测试
//! （`tests/`）、benchmark 和 doctest 都够不着，留在这里就只能靠手工跑程序验证。
//!
//! 所以这个文件保持「薄」是有意的：它长起来了，就说明有东西该往库里挪了。
{% if cli or logging %}
{% if cli %}mod cli;
{% endif %}{% if logging %}mod telemetry;
{% endif %}{% endif %}{% if cli or error_handling %}
{% if error_handling %}use anyhow::Context as _;
{% endif %}{% if cli %}use clap::Parser as _;
{% endif %}{% endif %}
{% if async_runtime %}#[tokio::main]
async {% endif %}fn main(){% if error_handling %} -> anyhow::Result<()>{% endif %} {
{% if cli %}    let args = cli::Cli::parse();
{% endif %}{% if logging %}    telemetry::init({% if cli %}&args.log_level{% else %}"info"{% endif %});
{% endif %}{% if cli %}    let name = args.name;
{% else %}    let name = String::from("world");
{% endif %}{% if error_handling %}    // 库返回的是具体的 Error（可以 match），到了这里才转成 anyhow::Error
    // 并补上下文——两层错误的分界线就在这两行之间。
    let greeting = {{ crate_name }}::greet(&name);
    let message = greeting.context("生成问候语失败")?;
{% else %}    let message = {{ crate_name }}::greet(&name);
{% endif %}{% if logging %}    tracing::info!("{message}");
{% else %}    println!("{message}");
{% endif %}{% if error_handling %}
    Ok(())
{% endif %}}
