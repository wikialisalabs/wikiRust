# wikiRust — Wikialisalabs EVM Stack

> Bộ 8 repositories Rust/EVM mã nguồn mở — **Wikialisalabs Foundation** · workspace: `wikiRust`

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Rust](https://img.shields.io/badge/rust-stable-orange.svg)](https://www.rust-lang.org/)

---

## Kiến trúc Phân tầng

```
┌─────────────────────────────────────────────────────────────────┐
│  TẦNG 0 — Meta-crate (Entry Point cho Developer)                │
│  alloy  (re-export + compose toàn bộ stack)                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │ depends on
┌──────────────────────────▼──────────────────────────────────────┐
│  TẦNG 3 — Ecosystem Extensions                                  │
│  op-alloy · svm-rs · eips                                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │ depends on
┌──────────────────────────▼──────────────────────────────────────┐
│  TẦNG 2 — EVM Runtime & Data Structures                         │
│  evm · evm2 · trie                                              │
└──────────────────────────┬──────────────────────────────────────┘
                           │ depends on
┌──────────────────────────▼──────────────────────────────────────┐
│  TẦNG 1 — Core Primitives (zero external deps)                  │
│  core  (alloy-primitives · alloy-rlp · alloy-sol-types)         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Repositories

| Crate | Tầng | Giấy phép | Mô tả |
|-------|------|-----------|-------|
| [`alloy`](alloy/) | 0 — Meta | Apache-2.0 | Entry point, Tower middleware, prelude |
| [`core`](core/) | 1 — Primitives | Apache-2.0 | `no_std` Address/B256/U256, RLP, ABI |
| [`evm`](evm/) | 2 — Runtime | Apache-2.0 | EVM interpreter + Inspector hook API |
| [`evm2`](evm2/) | 2 — Experimental | Apache-2.0 | Block-STM parallel + ZK-IR output |
| [`trie`](trie/) | 2 — Data Structures | Apache-2.0 | Rayon-parallel Merkle Patricia Trie |
| [`eips`](eips/) | 3 — Extensions | Apache-2.0 | Prague-ready hardfork activation |
| [`op-alloy`](op-alloy/) | 3 — Extensions | MIT | OP Stack types (SEQUENTICHAIN) |
| [`svm-rs`](svm-rs/) | 3 — Extensions | MIT | solc version manager + VRQ scanner |

---

## Bắt đầu nhanh

### Yêu cầu

- Rust stable ≥ 1.78 (`rustup update stable`)
- Cargo (đi kèm Rust)

### Build toàn bộ workspace

```bash
git clone https://github.com/wikialisalabs/wikiRust.git
cd wikiRust
cargo build --workspace
```

### Chạy tất cả tests

```bash
cargo test --workspace
```

### Chạy tests với tất cả features

```bash
cargo test --workspace --all-features
```

---

## Lộ trình (Phased Roadmap)

| Pha | Thời gian | Mục tiêu |
|-----|-----------|----------|
| **Pha 1** | Tháng 1–3 | `core` + `eips` + `trie` — 100% test coverage |
| **Pha 2** | Tháng 3–6 | `evm` v1 ≥ 95% ethereum/tests + `svm-rs` |
| **Pha 3** | Tháng 6–9 | `alloy` meta-crate + `op-alloy` + hardforks |
| **Pha 4** | Tháng 8–12 | `evm2` Block-STM + mdBook full documentation site |

---

## Đóng góp

Mỗi repository có file `CONTRIBUTING.md` riêng với hướng dẫn chi tiết:

| Repository | Hướng dẫn |
|------------|-----------|
| `alloy` | [alloy/CONTRIBUTING.md](alloy/CONTRIBUTING.md) |
| `core` | [core/CONTRIBUTING.md](core/CONTRIBUTING.md) |
| `evm` | [evm/CONTRIBUTING.md](evm/CONTRIBUTING.md) |
| `evm2` | [evm2/CONTRIBUTING.md](evm2/CONTRIBUTING.md) |
| `trie` | [trie/CONTRIBUTING.md](trie/CONTRIBUTING.md) |
| `eips` | [eips/CONTRIBUTING.md](eips/CONTRIBUTING.md) |
| `op-alloy` | [op-alloy/CONTRIBUTING.md](op-alloy/CONTRIBUTING.md) |
| `svm-rs` | [svm-rs/CONTRIBUTING.md](svm-rs/CONTRIBUTING.md) |

### Quy tắc chung cho toàn bộ monorepo

1. **Không `unsafe`** trừ khi được maintainer approve với justification rõ ràng.
2. **Không `unwrap()`** trong production code.
3. **Tất cả public API** phải có doc comment (`///`).
4. **Conventional Commits** — xem [conventionalcommits.org](https://www.conventionalcommits.org/).
5. **`cargo fmt` + `cargo clippy -D warnings`** phải pass trước mọi commit.
6. **100% test coverage** cho Tầng 1 (`core`); ≥ 95% cho Tầng 2.

---

## Liên hệ

- **Email:** root@wikialisalabs.axvn.vn
- **GitHub Org:** https://github.com/wikialisalabs
- **Issues:** https://github.com/wikialisalabs/wikialisalabs/issues

---

*Wikialisalabs Foundation — Xây dựng nền móng EVM nguồn mở cho thế hệ tiếp theo* 🦀
