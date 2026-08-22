# CLAUDE.md

Project conventions for AI coding agents (Claude Code, Cursor, Codex, etc.) and human developers.

This project enforces several **counter-intuitive** rules. Default Rust habits will directly break CI. Read this document before making changes.

> Unrendered template variables? You are in the **template repository**, not a generated project.
> `cargo` commands cannot run directly from the template root. See `README.md` for template modification rules.

## Primary Entry Point: Always Use `just`

```bash
just            # List all available recipes
just check      # Fast compilation check (cargo check)
just test       # Run full test suite (cargo-nextest + doctests)
just lint       # Run formatting, TOML, clippy, typos, and doc checks (equivalent to CI lint job)
just ci         # Run pre-commit checks: lint + test + audit
```

**Run `just lint` at least once after modifying code.** Do not rely solely on `cargo build`—CI gates strictly on clippy and rustdoc warnings, not just compilation success.

## 5 Critical Gotchas (Do Not Violate)

### 1. Formatting MUST use nightly via `just fmt`

```bash
just fmt        # NEVER run raw `cargo fmt` or `cargo +nightly fmt` directly
```

`rustfmt.toml` relies on **unstable options** (such as `imports_granularity`, `group_imports`, `wrap_comments`). Stable `rustfmt` **silently ignores** these options without raising errors—leading to false-positive local successes that fail CI immediately.

Do not run hardcoded `cargo +nightly fmt`: if `rust-toolchain.toml` pins a specific channel (e.g., `nightly-2026-08-18`), generic `+nightly` resolves to a **different** toolchain version and may format differently. `just fmt` dynamically resolves the exact matching toolchain (via `fmt_toolchain` in `justfile`).

### 2. Zero Warnings Policy in CI

CI enforces `-D warnings` across both `cargo clippy` and `rustdoc` (`RUSTDOCFLAGS="-D warnings"`). Any warning (including dead documentation links or missing `# Errors` sections on fallible public functions) will fail the build.

### 3. Never Suppress Lints to Bypass CI

When encountering clippy errors, **fix the underlying code**. Do not add `#[allow(...)]`. When suppression is strictly necessary:

```rust
#[expect(clippy::needless_pass_by_value, reason = "required by trait signature")]
```

- Always use `#[expect]` instead of `#[allow]`. `clippy::allow_attributes` triggers a warning (which fails CI). `#[expect]` ensures the attribute is flagged for removal once the lint no longer triggers.
- **`reason = "..."` is mandatory**.
- `unsafe_code = "forbid"` is enforced workspace-wide; `forbid` cannot be overridden by `#[allow]`. If unsafe code is truly required, consult human maintainers to downgrade to `deny`.

{% if toolchain == "stable" %}### 4. Compiler Version is Pinned by `rust-toolchain.toml`

Do not override the toolchain using `rustup override set` or the `RUSTUP_TOOLCHAIN` environment variable. Both take silent precedence over `rust-toolchain.toml`, causing phantom toolchain mismatches. `just doctor` actively verifies this.

If the compiler crashes (`error: internal compiler error` leaving `rustc-ice-*.txt`), run `just ice` to diagnose the exact compiler build and trace information before modifying code.
{% else %}### 4. Nightly Toolchain & Borrow Checker Differences

This project targets nightly Rust. Nightly uses the Polonius borrow checker by default, which accepts more programs than stable NLL without warning. Code compiling under nightly may fail under stable.

After modifying lifetimes or borrowing logic, verify compatibility:

```bash
just nll        # Test against the same nightly toolchain using stable NLL semantics
```

Nightly toolchains update frequently; upstream ICEs or newly introduced clippy lints can occasionally break CI. If an ICE occurs (`rustc-ice-*.txt`), run `just ice` before altering your code.
{% endif %}
### 5. Never Use `println!` for Standard Output

Use the project helper `print_line()` in `src/main.rs`. Standard `println!` panics on broken downstream pipes (e.g., `app | head -n 1`). Route diagnostic logs to `stderr` and business output to `stdout`—never mix them.

## Code Organization & Visibility

- **Keep all business logic in `src/lib.rs` and modules.** `src/main.rs` is strictly reserved for CLI argument parsing, logging initialization, and top-level error exit handling (<100 lines).
- Main application code in `main.rs` is inaccessible to integration tests (`tests/`), benchmarks, and doctests.
- Exposing items with `pub` represents a public contract. Internal workspace/crate utilities must use `pub(crate)` (`unreachable_pub` is enforced).
{% if error_handling %}
## Error Handling Strategy

- **Library crate (`src/error.rs`)**: Define domain-specific, matchable error enums using `thiserror`.
- **Application binary (`src/main.rs`)**: Use `anyhow::Result` with `.context()` for human-readable error stacks.
- **Never expose `anyhow::Error` in public library APIs**—it prevents downstream callers from matching and handling specific error variants.
- New library error variants can be added freely (the error enum is marked `#[non_exhaustive]`).
- Public functions returning `Result` must document failure cases under an `# Errors` doc section.
{% endif %}{% if async_runtime %}
## Async Rules: Zero Blocking I/O

`clippy.toml` enforces `disallowed-types` and `disallowed-methods` against blocking calls like `std::fs::*` and `std::process::Command` to prevent worker thread starvation. Always use `tokio::fs::*` and `tokio::process::Command`.

If synchronous execution is strictly required during startup (e.g., loading config before starting the runtime):
```rust
#[expect(clippy::disallowed_methods, reason = "one-time startup config read before runtime launch")]
```
{% endif %}
## Dependency Management

- Declare workspace dependencies in root `Cargo.toml` under `[workspace.dependencies]`. Crate manifests should only declare `dep_name = { workspace = true }`.
- **Run `just audit` (`cargo-deny`) after modifying dependencies.** It verifies licenses, unauthorized crates, advisories, and wildcards.
- Never edit `Cargo.lock` manually. CI and Docker builds run with `--locked`.
- Check if standard library features exist before adding external dependencies (e.g., `[bans.std-replacements]` bans crates like `lazy_static` in favor of `std::sync::OnceLock`).

## Testing & Context Control

- Run targeted tests during active debugging to avoid noisy outputs:
  ```bash
  cargo nextest run <test_filter>
  ```
- Run `just test` before submitting changes (executes both `cargo-nextest` and doc tests).
- `cargo-nextest` runs tests in parallel processes by default. For tests sharing resources (ports, DBs, files), configure serialization groups in `.config/nextest.toml` under `[test-groups]` instead of inserting `Mutex` guards inside test code.
- Integration tests (`tests/`) can only access `pub` APIs.
- `unwrap()`, `expect()`, and `panic!()` are explicitly allowed inside test modules via `clippy.toml`.

## Git & Commit Workflow

Run `just hooks` to configure pre-commit validation. **Never bypass hooks using `--no-verify`**:

| Hook | Executed Tasks |
| --- | --- |
| `pre-commit` | Fast checks (<2s): `rustfmt`, `clippy`, `taplo`, `cargo-deny`, `typos`, and secret detection |
| `commit-msg` | Validates Conventional Commits format |
| `pre-push` | Executes full `just ci` pipeline |

Commit messages must follow Conventional Commits:

```text
feat(cli): add --json output support
fix: prevent panic when stdout pipe closes early
refactor!: change greet return type to Result      # ! denotes breaking change
```

Allowed types: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`.
CHANGELOG and `cargo-release` version bumps are generated directly from these types via `cliff.toml`.

## Prohibited Actions

- Do NOT create unnecessary configuration files.
- Do NOT weaken lints in `Cargo.toml` (`[workspace.lints]`), `clippy.toml`, `rustfmt.toml`, or `deny.toml` to make CI pass.
- Do NOT place domain logic in `src/main.rs`.
- Do NOT delete CI jobs to resolve pipeline duration issues.
- When uncertain, ask for clarification instead of guessing or modifying configurations.