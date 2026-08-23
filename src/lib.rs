//! {{ description }}
//!{% if crate_type == "bin" %}
//! 库目标：存放业务逻辑，供 `src/main.rs` 与 `tests/` 调用。{% else %}
//! 标了 `pub` 的项构成对外公开的 API，`tests/integration.rs` 从外部视角调用它们。{% endif %}
{% if error_handling %}
mod error;

pub use crate::error::{Error, Result};
{% endif %}
/// 把两个数相加。
///
/// # Examples
///
/// ```
/// let sum = {{ crate_name }}::add(1, 2);
/// assert_eq!(sum, 3);
/// ```
#[must_use]
pub fn add(left: u64, right: u64) -> u64 {
    left + right
}
{% if error_handling %}
/// 生成问候语。
///
/// # Errors
///
/// `name` 去掉首尾空白后为空时返回 [`Error::EmptyName`]。
///
/// # Examples
///
/// ```
/// # fn main() -> {{ crate_name }}::Result<()> {
/// let msg = {{ crate_name }}::greet("world")?;
/// assert_eq!(msg, "Hello, world!");
///
/// let blank = {{ crate_name }}::greet("  ");
/// assert!(blank.is_err());
/// # Ok(())
/// # }
/// ```
pub fn greet(name: &str) -> Result<String> {
    if name.trim().is_empty() {
        return Err(Error::EmptyName);
    }
    Ok(format!("Hello, {name}!"))
}
{% else %}
/// 生成问候语。
///
/// # Examples
///
/// ```
/// let msg = {{ crate_name }}::greet("world");
/// assert_eq!(msg, "Hello, world!");
/// ```
#[must_use]
pub fn greet(name: &str) -> String {
    format!("Hello, {name}!")
}
{% endif %}
#[cfg(test)]
mod tests {
    use super::{add, greet};

    #[test]
    fn it_works() {
        assert_eq!(add(2, 2), 4);
    }
{% if error_handling %}
    #[test]
    fn greet_formats_message() {
        assert_eq!(greet("world").unwrap(), "Hello, world!");
    }

    #[test]
    fn greet_rejects_blank_name() {
        assert!(greet("   ").is_err());
    }
{% else %}
    #[test]
    fn greet_formats_message() {
        assert_eq!(greet("world"), "Hello, world!");
    }
{% endif %}{% if async_runtime %}
    /// 异步测试示例。
    #[tokio::test]
    async fn async_test_works() {
        assert_eq!(add(1, 1), 2);
    }
{% endif %}}
