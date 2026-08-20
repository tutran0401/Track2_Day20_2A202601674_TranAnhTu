# 01 - Measure: latency baseline

Model `Qwen3.5 0.8B` · host `Windows-AMD64` · llama.cpp `b10488`
Settings: `threads=12` `ngl=99` `ctx=2048`
`max_tokens=64` · warm-up discarded
Completed requests: `Q4_K_M` 10/10 · `UD-Q2_K_XL` 10/10

| Quantization | Size (GB) | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode (tok/s) |
|:--|--:|--:|--:|--:|--:|--:|
| Q4_K_M | 0.50 | 6571 | 956 / 1329 | 32.2 / 33.4 | 2902 / 3321 / 3321 | 31.1 |
| UD-Q2_K_XL | 0.39 | 10629 | 1478 / 1810 | 374.5 / 407.7 | 25189 / 27293 / 27293 | 2.7 |

- **TTFT** = prefill. Short prompts keep it small; long-context RAG is where it explodes.
- **TPOT** = per-output-token decode cost, bounded by memory bandwidth. `decode tok/s = 1000 / TPOT_p50`.
- `UD-Q2_K_XL` decodes **11.52x SLOWER** than `Q4_K_M` here, despite being 0.11 GB smaller. That is a real result, not a mistake: fewer bits only buys speed when decode is limited by memory bandwidth. On a machine that is compute-limited instead — few cores, no GPU offload — the extra dequantization work of a heavily-quantized format can cost more than the bytes it saves. Say which case yours is.

## My observation

Q2 saves only 0.11 GB (22%) but is 11.52x slower in decode and has 1.55x higher
median TTFT, so it is not worth deploying on this machine. This is a backend-specific
counterexample to “fewer bits is faster”: Iris Xe/Vulkan handles Q4 efficiently, while
UD-Q2 pays enough unpacking/dequantization overhead to become compute/kernel limited.
I therefore keep Q4 for both quality headroom and latency.
