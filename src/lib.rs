//! {{ description }}

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

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn it_works() {
        assert_eq!(add(2, 2), 4);
    }
}
