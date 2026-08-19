//! 日志与追踪的初始化。
//!
//! 生产环境的几个要点，这里都按默认值配好了：
//!
//! 1. **过滤规则可在运行时调整**——用 `RUST_LOG` 就能改，不必重新编译、重新发版；
//! 2. **日志走 stderr**，stdout 留给程序真正的输出，管道和重定向才不会串味；
//! 3. **初始化失败不 panic**——`parse_lossy` 会忽略写错的 filter 指令并给出警告，
//!    不至于因为一个环境变量拼错就让服务起不来。

use tracing_subscriber::EnvFilter;

/// 安装全局 subscriber。请在 `main` 的最开头调用一次。
///
/// 过滤规则的优先级：环境变量 `RUST_LOG` > 传入的 `default_level`。
pub(crate) fn init(default_level: &str) {
    let directives =
        std::env::var(EnvFilter::DEFAULT_ENV).unwrap_or_else(|_| default_level.to_owned());
    let filter = EnvFilter::builder().parse_lossy(directives);

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .with_target(true)
        .init();
}

// 上线到需要日志采集的环境时，把上面的 fmt 换成机器可读的 JSON：
//     tracing_subscriber::fmt().json().flatten_event(true)...
// 需要在 Cargo.toml 里给 tracing-subscriber 打开 "json" feature。
//
// 接 OpenTelemetry / Jaeger 则再叠一层 layer，用 registry + with() 组合：
//     tracing_subscriber::registry().with(filter).with(fmt_layer).with(otel_layer).init();
