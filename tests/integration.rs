//! 集成测试：以外部使用者的视角调用 crate 的公开 API。
//!
//! 这里是独立的 crate，只能访问 `pub` 项——正因如此它才能替你回答
//! 「我导出的东西够不够用」这个问题。`cargo nextest run` 会自动带上它。{% if crate_type == "bin" %}
//!
//! 二进制项目同样有这一层：它测的是 `src/lib.rs` 那一侧。`main.rs` 里的东西
//! 在这里根本 `use` 不到——这也是业务逻辑不该留在 `main.rs` 的直接原因。{% endif %}
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
    // 公开错误类型的意义就在这里：调用方能区分错误种类，而不是只能打印。
    let err = greet("").unwrap_err();
    assert!(matches!(err, Error::EmptyName));
}{% else %}
#[test]
fn greet_works_from_outside() {
    let msg = greet("world");
    assert_eq!(msg, "Hello, world!");
}{% endif %}
