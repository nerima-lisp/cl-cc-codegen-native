# Changelog

## Unreleased

### Target code generation controls

The target packages now export these CLI control variables:

- `cl-cc/codegen-native/targets/x86-64` exports `*x86-64-omit-frame-pointer*`.
- `cl-cc/codegen-native/targets/aarch64` exports `*a64-omit-frame-pointer*`.
- `cl-cc/codegen-native/targets/wasm` exports:
  - `*wasm-call-stack-inspection-enabled*`
  - `*wasm-dwarf-debug-info-enabled*`
  - `*wasm-extended-names-enabled*`
  - `*wasm-hot-code-reload-enabled*`
  - `*wasm-js-bigint-i64-enabled*`
  - `*wasm-memory-profiler-enabled*`
  - `*wasm-memory64-enabled*`
  - `*wasm-repl-incremental-compilation-enabled*`
  - `*wasm-source-map-enabled*`
  - `*wasm-source-map-url*`
  - `*wasm-table64-enabled*`
  - `*wasm-type-reflection-js-api-enabled*`

The `cl-cc/codegen` facade imports these controls internally, so its exported API remains unchanged.
