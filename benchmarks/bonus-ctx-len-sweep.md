# Bonus - Context-length sweep (prefill cost)

Host `Windows-AMD64` · llama.cpp `b10488` ·
`threads=12` `ngl=99` · RAM 15.7 GB

| Prompt tokens | Prefill (tok/s) | TTFT contribution (ms) | vs linear scaling |
|:--|--:|--:|--:|
| 256 | 448.3 | 571.0 | 1.00x |
| 1024 | 486.9 | 2103.0 | 0.92x |
| 2048 | 455.4 | 4496.8 | 0.98x |
| 4096 | 411.4 | 9955.8 | 1.09x |
| 8192 | 327.7 | 24996.2 | 1.37x |

At 8192 tokens, prefill costs **24996 ms** --
1.37x what linear scaling from the smallest point would predict. That excess
is attention's O(N^2) term becoming visible, and every millisecond of it lands in TTFT
before the user sees a single token.

Either way, this is the number to remember when someone proposes stuffing more retrieved
context into a RAG prompt "because the context window allows it". Prefill is paid in full,
on every request, before the first token appears.

## My finding

The bend becomes operationally important at 4096 tokens (9.96 s), already longer than
the entire 5.57 s mean toy-RAG request. At 8192 tokens prefill reaches 25.00 s—1.37x the
linear projection—as attention work and declining effective tok/s become visible. A RAG
system on this laptop should retrieve only a few high-relevance chunks and enforce a token
budget rather than fill the available context window.
