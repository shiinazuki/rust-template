{% if crate_type == "lib" %}//! 本 crate 的公开错误类型。
//!
//! 库和应用的错误处理分工，是 Rust 生态里少数值得从第一天就守住的约定：
//!
//! - **库**用 [`thiserror`] 定义**具体、可穷举**的错误，调用方能 `match` 之后
//!   分别处理（重试？降级？直接失败？）；
//! - **应用**才用 `anyhow` 那种「一把抓 + 附加上下文」的类型。
//!
//! 反过来做——库直接抛 `anyhow::Error`——调用方除了把它打印出来别无选择。

/// 本 crate 所有可恢复错误的统一入口。
///
/// 标了 `#[non_exhaustive]`：以后新增变体不构成破坏性变更（调用方的 `match`
/// 必须保留 `_` 分支），发版时不用为了加一个错误码就抬 major。
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum Error {
    /// 传入的名字为空，或者只有空白字符。
    #[error("名字不能为空")]
    EmptyName,

    /// 底层 IO 失败。`#[from]` 让 `?` 能把 [`std::io::Error`] 直接转过来。
    #[error("IO 操作失败")]
    Io(#[from] std::io::Error),
}

/// 带默认错误类型的 `Result` 别名。
///
/// 公开 API 一律写 `Result<T>`，调用方 `use {{ crate_name }}::Result;` 之后，
/// 代码里就不必到处重复 `, {{ crate_name }}::Error>`。
pub type Result<T, E = Error> = core::result::Result<T, E>;{% else %}//! 领域错误类型。
//!
//! 分工是这样的：
//!
//! - 这里用 [`thiserror`] 定义**具体**的错误，调用方能 `match` 之后分别处理；
//! - `main` 用 `anyhow::Result` 收口，配合 `.context()` 补上下文后统一上报。
//!
//! 一个只有 `anyhow` 的项目，在需要「区分错误类型来决定要不要重试」时会非常难受；
//! 而全都手写 `enum` 又太啰嗦。两者搭配才是应用层的常见解法。

/// 业务逻辑里可能出现的错误。
#[derive(Debug, thiserror::Error)]
pub(crate) enum Error {
    /// 传入的名字为空，或者只有空白字符。
    #[error("名字不能为空")]
    EmptyName,
}{% endif %}
