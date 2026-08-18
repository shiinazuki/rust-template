//! 集成测试：以外部使用者的视角调用 crate 的公开 API。
//!
//! 这里是独立的 crate，只能访问 `pub` 项；`cargo nextest run` 会自动带上。

use {{ crate_name }}::add;

#[test]
fn add_works_from_outside() {
    assert_eq!(add(40, 2), 42);
}
