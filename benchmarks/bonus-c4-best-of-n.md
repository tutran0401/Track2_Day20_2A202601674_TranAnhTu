# Bonus C4 - Best-of-N with a lightweight reranker

Model `Qwen3.5 0.8B` on `Windows-AMD64`; server uses
`--parallel 4`. All candidates used the same prompt,
temperature 0.9, 64-token cap, and distinct seeds. Expected answer: `38`.

| mode | seed | wall/latency (ms) | correct | heuristic score |
|:--|--:|--:|--:|--:|
| single | 0 | 3161.3 | False | -3.21 |
| best-of-4 candidate | 1 | 5124.7 | False | -3.21 |
| best-of-4 candidate | 2 | 4249.3 | False | -2.95 |
| best-of-4 candidate | 3 | 4429.4 | False | -1.45 |
| best-of-4 candidate | 4 | 4535.4 | False | -1.41 |

Single-shot wall time: **3161.3 ms**. Best-of-4 wall time: **5128.1 ms**
(1.62x latency, not 4x, because four slots decode concurrently).
The best diagnostic score was seed **4**; **0/4** candidates passed
the machine-checkable `FINAL=38` contract, so the reranker **rejected the entire set**.

## Analysis

Best-of-N converts spare batch throughput into a chance at higher per-request quality, but
it is not a guarantee: all four samples repeated the same arithmetic error, so diversity did
not rescue correctness. The machine-checkable constraint prevented a wrong answer from being
returned; a production system would retry with a stronger model or abstain. The cost was a
1.62x latency multiplier. Under multi-user load these four candidates
also consume every decode slot, so this is defensible only for difficult, high-value requests.

### Highest-scoring rejected response

This shop sells 15 books total initially (6 shelves × 7 books) and then adds 5 more, resulting in a combined inventory of 20 books.

FINAL=20
