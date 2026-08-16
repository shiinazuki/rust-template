// 测试里用 unwrap 是常态，避免和 Cargo.toml 中的 clippy::unwrap_used 打架。
// 注意：这条只覆盖单元测试；tests/ 下的集成测试是独立 crate，需要各自声明。
#![cfg_attr(test, allow(clippy::unwrap_used))]

fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(1 + 1, 2);
    }
}
