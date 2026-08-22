//! 集成测试：以外部使用者的视角调用 crate 的公开 API。
//!
//! 这里是独立的 crate，只能访问 `pub` 项——正因如此它才能替你回答
//! 「我导出的东西够不够用」这个问题。`cargo nextest run` 会自动带上它。{% if crate_type == "bin" %}
//!
//! 二进制项目同样有这一层：它测的是 `src/lib.rs` 那一侧。`main.rs` 里的东西
//! 在这里根本 `use` 不到——这也是业务逻辑不该留在 `main.rs` 的直接原因。{% endif %}
//!
//! ⚠️ 下面 `use` 的 `add` / `greet` 是 `src/lib.rs` 里的**骨架函数**，写你自己的
//!    代码时一定会被删掉。删了之后这个文件就编译不过了，而且失败的时机很不直观：
//!    `cargo build` / `cargo run` 照常通过（集成测试不参与普通构建），
//!    只有 `cargo test` / `cargo nextest run` / `just ci` 才会炸。
//!    所以换掉 lib.rs 的同时把这里一起改成对你真实公开 API 的调用——
//!    这一层的价值就在于它是从**外部**看你的 crate，而不是从内部。
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
