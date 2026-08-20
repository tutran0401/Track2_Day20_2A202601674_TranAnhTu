# 01 - Tune: thread-count sweep

Model `Qwen3.5-0.8B-Q4_K_M.gguf` · host `Windows-AMD64` · llama.cpp `b10488`
CPU: **12 physical · 16 logical** cores · `ngl=99` · metric `tg128`

| threads (-t) | tg128 (tok/s) | vs best |
|:--|--:|--:|
| 1 | 34.0 | 99% |
| 6 | 33.8 | 99% |
| 12 | 34.1 | 99% |
| 16 | 34.3 | 100% |
| 32 | 33.7 | 98% |

**Best**: `-t 16` at 34.3 tok/s
**Slowest tested**: `-t 32` at 33.7 tok/s (1.02x spread)
**Against the physical-core default** (`-t 12`, 34.1 tok/s): 1.01x

Use this in your run:

```bash
LAB_N_THREADS=16 make bench
```

## My explanation

There is no strong CPU-thread knee: all five points lie within 1.7%, and `-t 16`
wins narrowly at 34.3 tok/s versus 34.1 tok/s for `-t 12`. All 99 layers are offloaded
to Iris Xe (`ngl=99`), so GPU execution and shared-memory bandwidth dominate decode;
CPU threads mostly feed the device. At 32 threads scheduling/coordination overhead
slightly exceeds any feeding benefit, reducing throughput to 33.7 tok/s.
