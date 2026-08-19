//! {{ description }}
{% if error_handling %}
mod error;

pub use crate::error::{Error, Result};
{% endif %}
/// 把两个数相加。
///
/// # Examples
///
/// ```
/// assert_eq!({{ crate_name }}::add(1, 2), 3);
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
/// assert_eq!({{ crate_name }}::greet("world")?, "Hello, world!");
/// assert!({{ crate_name }}::greet("  ").is_err());
/// # Ok(())
/// # }
/// ```
pub fn greet(name: &str) -> Result<String> {
    if name.trim().is_empty() {
        return Err(Error::EmptyName);
    }
    Ok(format!("Hello, {name}!"))
}
{% endif %}
#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn it_works() {
        assert_eq!(add(2, 2), 4);
    }
{% if error_handling %}
    #[test]
    fn greet_rejects_blank_name() {
        assert!(super::greet("   ").is_err());
    }
{% endif %}}
