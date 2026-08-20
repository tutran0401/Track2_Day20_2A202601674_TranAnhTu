# Bonus C8 - Semantic cache threshold sweep (offline)

This run used the repository's explicit offline bag-of-words embedder, not a production
sentence encoder. It replayed eight prompts at thresholds 0.70, 0.80, 0.85, 0.90, and
0.95. Every threshold produced 3/8 hits (38%), saving three simulated 250 ms LLM calls.

| Threshold | Hits | Hit rate | Simulated decode saved |
|--:|--:|--:|--:|
| 0.70 | 3/8 | 38% | ~750 ms |
| 0.80 | 3/8 | 38% | ~750 ms |
| 0.85 | 3/8 | 38% | ~750 ms |
| 0.90 | 3/8 | 38% | ~750 ms |
| 0.95 | 3/8 | 38% | ~750 ms |

## Diagnosis

The flat curve is an artifact, not evidence that threshold choice is irrelevant. The stub
produces almost only 0.0 or 1.0 similarities, so no threshold in the tested interval can
move a borderline example. It also false-misses real paraphrases such as “Explain TTFT and
TPOT” versus “What does time to first token mean” (similarity 0.00). A next-token decoder or
bag-of-words stub is not trained to place sentence meaning into a calibrated metric space;
a dedicated encoder such as BGE-M3 or Qwen3-Embedding is required before interpreting hit
rate. In production I would also partition/salt cache keys per tenant to prevent cross-tenant
answer leakage and timing side channels.
