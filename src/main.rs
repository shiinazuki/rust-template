//! {{ description }}
//!
//! 可执行入口：初始化日志、收口错误、把结果写到 stdout，业务逻辑在 `src/lib.rs`。

use std::io::{self, Write as _};
{% if logging %}
mod telemetry;
{% endif %}{% if error_handling %}
use anyhow::Context as _;
{% endif %}
{% if async_runtime %}#[tokio::main]
async {% endif %}fn main() -> {% if error_handling %}anyhow::Result<()>{% else %}io::Result<()>{% endif %} {
{% if logging %}    telemetry::init("info");
{% endif %}    let name = String::from("world");
{% if error_handling %}    // 把库返回的具体错误转成 anyhow::Error 并附加上下文
    let greeting = {{ crate_name }}::greet(&name);
    let message = greeting.context("生成问候语失败")?;
{% else %}    let message = {{ crate_name }}::greet(&name);
{% endif %}{% if logging %}    // 日志写到 stderr，业务输出走 stdout
    tracing::info!(name = %name, "已生成问候语");
{% endif %}    print_line(&message){% if error_handling %}.context("写入 stdout 失败"){% endif %}?;

    Ok(())
}

/// 把一行结果写到 stdout。
///
/// 下游管道提前关闭（`BrokenPipe`）时视为正常结束，其余写失败照常返回错误。
fn print_line(line: &str) -> io::Result<()> {
    let mut out = io::stdout().lock();
    // 写入后立即 flush，让写失败在这里就返回
    match writeln!(out, "{line}").and_then(|()| out.flush()) {
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        other => other,
    }
}
