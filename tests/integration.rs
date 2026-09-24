//! 集成测试：以外部使用者的视角调用 `src/lib.rs` 导出的 `pub` 项。
//!
//! `add` / `greet` 是 `src/lib.rs` 的骨架函数，改写 lib.rs 时一并替换。
{% if error_handling %}
use {{ crate_name }}::{Error, add, greet};
{% else %}
use {{ crate_name }}::{add, greet};
{% endif %}
#[test]
fn add_works_from_outside() {
    assert_eq!(add(40, 2), 42);
}
{% if error_handling %}
#[test]
fn greet_error_is_public_and_matchable() {
    // 断言错误类型是公开且可 match 的
    let err = greet("").unwrap_err();
    assert!(matches!(err, Error::EmptyName));
}{% else %}
#[test]
fn greet_works_from_outside() {
    let msg = greet("world");
    assert_eq!(msg, "Hello, world!");
}{% endif %}
