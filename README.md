# Aether

Aether is a low-latency LAN video transmission project written primarily in Rust.

The goal is to provide a lightweight pipeline for:

- screen and window capture;
- hardware video encoding;
- low-latency network transmission;
- hardware video decoding;
- GPU-native rendering;
- low CPU, GPU, RAM and bandwidth overhead.

Aether is not intended to be a complete compositor like OBS.

## Architecture

The workspace is divided into reusable crates and executable applications.

### Applications

- `aether-host`: sender CLI.
- `aether-client`: receiver CLI.

### Crates

- `aether-core`: sessions, configuration, states and shared domain types.
- `aether-capture`: screen and window capture.
- `aether-codec`: hardware encoding and decoding.
- `aether-net`: network transport, connections and reconnection.
- `aether-protocol`: wire protocol, framing and versioning.
- `aether-render`: GPU-native video presentation.
- `aether-ui`: future graphical interface integration.

## Development approach

Aether is CLI-first.

Features should normally follow this flow:

1. isolated implementation;
2. probe/example;
3. validation;
4. reusable public API;
5. core integration;
6. CLI integration;
7. tests and performance validation;
8. stabilization;
9. UI integration.

Complex native integrations should first be validated through small examples under:

```text
crates/<crate>/examples/
