//! {{ description }}
//!
//! 可执行入口，只负责收口：初始化日志、把错误汇总、把结果写到 stdout。
//! 业务逻辑一律放在 `src/lib.rs` 那一侧——`main.rs` 里的东西集成测试
//! （`tests/`）、benchmark 和 doctest 都够不着，留在这里就只能靠手工跑程序验证。
//!
//! 所以这个文件保持「薄」是有意的：它长起来了，就说明有东西该往库里挪了。
//!
//! 要解析命令行参数的话：`cargo add clap --features derive,env`，
//! 参数定义单独放进 `src/cli.rs`（derive 一个 `Cli` 结构体，测试里可以直接构造），
//! 这里只留 `let args = Cli::parse();` 一行。

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
{% if error_handling %}    // 库返回的是具体的 Error（可以 match），到了这里才转成 anyhow::Error
    // 并补上下文——两层错误的分界线就在这两行之间。
    let greeting = {{ crate_name }}::greet(&name);
    let message = greeting.context("生成问候语失败")?;
{% else %}    let message = {{ crate_name }}::greet(&name);
{% endif %}{% if logging %}    // 日志走 stderr（给运维看），程序真正的输出走 stdout——见 telemetry.rs
    tracing::info!(name = %name, "已生成问候语");
{% endif %}    print_line(&message){% if error_handling %}.context("写入 stdout 失败"){% endif %}?;

    Ok(())
}

/// 把一行结果写到 stdout。
///
/// 刻意不用 `println!`：**下游管道提前关闭**时它会直接 panic。Rust 在启动时把
/// `SIGPIPE` 设成 ignore，于是 `prog | head -1` 这种再常见不过的用法下，写失败
/// 变成一个 `BrokenPipe` 错误，而 `println!` 内部把它 unwrap 掉了——用户看到的是
/// 一句莫名其妙的 `failed printing to stdout`，退出码还是 101。输出量越大越容易
/// 撞上，`ripgrep` / `fd` / `bat` 这些工具都专门处理过这件事。
///
/// 这里的策略与它们一致：`BrokenPipe` 视为正常结束，其余写失败照常上报。
fn print_line(line: &str) -> io::Result<()> {
    let mut out = io::stdout().lock();
    // stdout 是行缓冲的，写完带换行的一行其实已经推出去了。显式 flush 是为了让
    // 「写失败」在这里就被发现——否则它会拖到进程退出时的隐式 flush，那一次的
    // 错误是被静默丢弃的。
    match writeln!(out, "{line}").and_then(|()| out.flush()) {
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        other => other,
    }
}
