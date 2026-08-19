//! 命令行参数定义（clap derive）。
//!
//! 这里只负责「解析与校验输入」，不放业务逻辑。好处是 `Cli` 可以在测试里直接构造，
//! 不必真的起一个进程去传参数。
//!
//! ⚠️ 二进制 crate 里一律用 `pub(crate)` 而不是 `pub`：bin 没有外部使用者，
//!    `pub` 项会被 `unreachable_pub` lint 拦下来（CI 是 `-D warnings`）。

use clap::Parser;

/// {{ description }}
#[derive(Debug, Parser)]
#[command(version, about, long_about = None)]
pub(crate) struct Cli {
    /// 要问候的名字
    #[arg(default_value = "world")]
    pub(crate) name: String,
{% if logging %}
    /// 日志级别：error / warn / info / debug / trace
    ///
    /// 也可以用 `RUST_LOG` 环境变量覆盖，且优先级更高——它支持按模块细分，
    /// 例如 `RUST_LOG=warn,{{ crate_name }}=debug`。
    #[arg(long, short, default_value = "info", env = "LOG_LEVEL")]
    pub(crate) log_level: String,
{% endif %}}

#[cfg(test)]
mod tests {
    use clap::{CommandFactory as _, Parser as _};

    use super::Cli;

    /// clap 官方推荐的自检：把 derive 出来的定义跑一遍内部断言。
    /// 「两个参数用了同一个 short」这类问题原本只在运行时暴露，这里能在测试期就拦住。
    #[test]
    fn cli_definition_is_valid() {
        Cli::command().debug_assert();
    }

    #[test]
    fn name_defaults_to_world() {
        let cli = Cli::parse_from(["{{ project-name }}"]);
        assert_eq!(cli.name, "world");
    }
}
