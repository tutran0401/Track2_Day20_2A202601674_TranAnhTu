# 03 - Integrate: RAG pipeline run

Host `Windows-AMD64` · llama.cpp `b10488` ·
retrieval backend: **keyword overlap** · 3 queries

| Query | Contexts retrieved | embed (ms) | retrieve (ms) | llm (ms) | total (ms) |
|:--|--:|--:|--:|--:|--:|
| Why is goodput more useful than raw throughp... | goodput, paged, radix | 0.0 | 0.0 | 5928.1 | 5928.1 |
| What problem does PagedAttention actually so... | paged, radix, disagg | 0.0 | 0.0 | 5256.2 | 5256.3 |
| When does splitting prefill and decode help?... | disagg, radix, batching | 0.0 | 0.1 | 5523.0 | 5523.1 |

Mean per stage (ms): embed **0.0** · retrieve **0.0** ·
llm **5569.1** · total **5569.2**
Dominant stage: **llm** (100% of total)

## Answers returned

**Why is goodput more useful than raw throughput?**

> Based on the context, **goodput** is more useful than raw throughput because it explicitly accounts for **SLOs** (Service Level Objectives) and **TPOT** (Throughput at Saturation).

While raw throughput ignores SLOs, goodput counts only requests per second that met the targets. This makes it a more accurate metric for evaluating performance relative to the specific SLAs defined in the system.

**What problem does PagedAttention actually solve?**

> PagedAttention solves the problem of **internal fragmentation** in GPU memory by storing the Key-Value (KV) cache in non-contiguous pages. This design allows the GPU to utilize unused memory more effectively, as it avoids the fragmentation that would occur if all KV data were packed into a single contiguous block.

**When does splitting prefill and decode help?**

> Splitting prefill and decode helps when **prefill is compute-bound and decode is memory-bandwidth-bound**.

This is because the context states that prefill is compute-bound (requiring significant CPU/GPU time) and decode is memory-bandwidth-bound (requiring significant memory bandwidth). By splitting these operations, the system can use a shared prefix in RadixAttention to skip the expensive prefi


## Which N16-N19 pieces are real

N16 is localhost-only; N17 is an in-memory list; N18 is a toy dictionary; N19 uses
keyword-overlap retrieval with no embedding call. All four are declared stubs. Only N20
is real: every answer comes from the OpenAI-compatible llama-server. Mean LLM latency is
5569.1 ms and rounds to 100% of total, so to halve latency I would attack N20 first by
shortening output/context or using a faster supported quant/backend—not optimize toy retrieval.
