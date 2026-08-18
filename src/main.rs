{% if async_runtime -%}
#[tokio::main]
async fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod tests {
    #[tokio::test]
    async fn it_works() {
        assert_eq!(1 + 1, 2);
    }
}
{%- else -%}
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
{%- endif %}
