//! 日志与追踪的初始化。
//!
//! 生产环境的几个要点，这里都按默认值配好了：
//!
//! 1. **过滤规则可在运行时调整**——用 `RUST_LOG` 就能改，不必重新编译、重新发版；
//! 2. **日志走 stderr**，stdout 留给程序真正的输出，管道和重定向才不会串味；
//! 3. **`RUST_LOG` 没设、设成空串、或写成非法指令时退回 `default_level`**，
//!    而不是得到一个「进程正常启动、却一条日志都不打」的空 filter；
//! 4. **`RUST_LOG` 把级别名拼错时会给一句提示**——这一类 `EnvFilter` 拦不住，见下面。

use tracing_subscriber::{EnvFilter, filter::LevelFilter};

/// 安装全局 subscriber。请在 `main` 的最开头调用一次。
///
/// 过滤规则的优先级：环境变量 `RUST_LOG` > 传入的 `default_level`。
pub(crate) fn init(default_level: &str) {
    // 兜底：解析不了就退回 info——日志初始化不该因为一个字符串把进程弄哑。
    //
    // 当前两条调用路径其实都保证了它不会失败（选了命令行骨架时由 clap 的
    // `value_parser` 锁死取值，否则 `main.rs` 传的是字面量），所以这里是给
    // 「以后改成从配置文件 / 远端配置读级别」留的余地。
    let default = default_level.parse().unwrap_or_else(|_| {
        eprintln!("无法解析日志级别 `{default_level}`，退回 info");
        tracing::Level::INFO.into()
    });

    warn_if_env_looks_like_a_typo();

    // 这里刻意不写成「自己读 RUST_LOG 再 parse_lossy」：那样在 RUST_LOG 被设成
    // 空串（`docker run -e RUST_LOG=`、`RUST_LOG=$未定义的变量` 都会产生它）
    // 或写成非法指令时，会得到一个什么都不匹配的空 filter——进程照常起来，
    // 但一条日志都不打，比直接失败更难查。默认指令保证了「最差也还是 default_level」。
    let filter = EnvFilter::builder()
        .with_default_directive(default)
        .with_env_var(EnvFilter::DEFAULT_ENV)
        .from_env_lossy();

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .with_target(true)
        .init();
}

/// 提醒一种上面那层默认指令**兜不住**的写法：把级别名拼错。
///
/// `EnvFilter` 的语法里，裸词是**目标名**：`RUST_LOG=inof` 会被理解成
/// 「target `inof` 开到 TRACE」——它解析**成功**，于是默认指令不再生效，
/// 本包的日志一条都不打，而且 `from_env_lossy` 不会有任何抱怨
/// （它只在指令连语法都不合法时才出声，比如 `foo=bar`）。
///
/// 「拼错的级别名」和「真的只想看某个 crate」在语法上是同一样东西，分不开，
/// 所以这里只打印一行说明、**不改变过滤行为**：写对的人多看一行，
/// 写错的人少查半小时。
fn warn_if_env_looks_like_a_typo() {
    let Ok(raw) = std::env::var(EnvFilter::DEFAULT_ENV) else {
        return;
    };
    let raw = raw.trim();

    // 只管「整个值就是一个裸词」这种最常见的写法；带 `=` 或 `,` 的复杂表达式
    // 是刻意在按模块细分，交给 EnvFilter 自己判断。
    if raw.is_empty() || raw.contains('=') || raw.contains(',') {
        return;
    }
    // 能解析成级别就是正常用法（名字、`off`、0-5 的数字都算）。
    if raw.parse::<LevelFilter>().is_ok() {
        return;
    }

    eprintln!("提示：RUST_LOG=`{raw}` 不是日志级别，按 EnvFilter 的语法它是一个「目标名」，");
    eprintln!("      即只放行名为 {raw} 的模块。想调级别请写 error / warn / info / debug / trace");
}

// 上线到需要日志采集的环境时，把上面的 fmt 换成机器可读的 JSON：
//     tracing_subscriber::fmt().json().flatten_event(true)...
// 需要在 Cargo.toml 里给 tracing-subscriber 打开 "json" feature。
//
// 接 OpenTelemetry / Jaeger 则再叠一层 layer，用 registry + with() 组合：
//     tracing_subscriber::registry().with(filter).with(fmt_layer).with(otel_layer).init();
