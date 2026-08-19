//! {{ description }}
//!
//! 可执行入口。业务逻辑一旦超过几十行就该往子模块（或 `lib.rs`）里挪——
//! `main.rs` 里的东西没法被集成测试和 benchmark 直接调用。
{% if cli or error_handling or logging %}
{% if cli %}mod cli;
{% endif %}{% if error_handling %}mod error;
{% endif %}{% if logging %}mod telemetry;
{% endif %}{% endif %}{% if cli or error_handling %}
{% if error_handling %}use anyhow::Context as _;
{% endif %}{% if cli %}use clap::Parser as _;
{% endif %}{% endif %}
{% if async_runtime %}#[tokio::main]
async {% endif %}fn main(){% if error_handling %} -> anyhow::Result<()>{% endif %} {
{% if cli %}    let args = cli::Cli::parse();
{% endif %}{% if logging %}    telemetry::init({% if cli %}&args.log_level{% else %}"info"{% endif %});
{% endif %}{% if cli or error_handling %}{% if cli %}    let name = args.name;
{% else %}    let name = String::from("world");
{% endif %}{% if error_handling %}    let message = greet(&name).context("生成问候语失败")?;
{% else %}    let message = format!("Hello, {name}!");
{% endif %}{% if logging %}    tracing::info!("{message}");
{% else %}    println!("{message}");
{% endif %}{% else %}{% if logging %}    tracing::info!("Hello, world!");
{% else %}    println!("Hello, world!");
{% endif %}{% endif %}{% if error_handling %}
    Ok(())
{% endif %}}
{% if error_handling %}
/// 示例业务函数：失败时返回**具体**的领域错误，交给调用方决定怎么处理。
///
/// 注意这里的分层——函数本身用 [`error::Error`]（可以 `match`），
/// `main` 收口时才转成 `anyhow::Error` 并补上下文。
fn greet(name: &str) -> Result<String, error::Error> {
    if name.trim().is_empty() {
        return Err(error::Error::EmptyName);
    }
    Ok(format!("Hello, {name}!"))
}
{% endif %}
#[cfg(test)]
mod tests {
{% if error_handling %}    use super::greet;

    #[test]
    fn greet_formats_message() {
        assert_eq!(greet("world").unwrap(), "Hello, world!");
    }

    #[test]
    fn greet_rejects_blank_name() {
        assert!(greet("   ").is_err());
    }
{% else %}    #[test]
    fn it_works() {
        assert_eq!(1 + 1, 2);
    }
{% endif %}{% if async_runtime %}
    /// 异步测试用 `#[tokio::test]`，它会自动起一个 runtime，不需要手写 `block_on`。
    #[tokio::test]
    async fn async_test_works() {
        assert_eq!(1 + 1, 2);
    }
{% endif %}}
