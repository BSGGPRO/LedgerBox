# Third-party notices

LedgerBox bundles the following local runtime and model in 0.10.0.

## Qwen2.5-0.5B-Instruct

- Upstream: https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct
- GGUF conversion: https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF
- File: `qwen2.5-0.5b-instruct-q4_k_m.gguf`
- Size: 491,400,032 bytes
- SHA-256: `74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB`
- License: Apache License 2.0
- Copyright: Alibaba Cloud / Qwen team

The model is used only as a local language rewriter. It does not calculate
amounts, percentages, dates, or balances. Deterministic `Decimal` code remains
the sole source of financial arithmetic.

## llama.cpp

- Upstream: https://github.com/ggml-org/llama.cpp
- Release: `b11796`
- Artifact: `llama-b11796-xcframework.zip`
- iOS slice: `ios-arm64/llama.framework`\n- Framework binary SHA-256: `B86990922D559C80FC863836C784887DDBAE871C9A1D726015E96936C3EDB3EC`
- SHA-256 of the downloaded ZIP: `07460786882E91BD41C2C7F55BA3E163B7F28DF55148B59700F1AB52780A055F`
- License: MIT

The framework is embedded under `LedgerBox.app/Frameworks/llama.framework` and
loaded with `dlopen` only on physical iOS devices. Simulator builds do not load
or link it.
