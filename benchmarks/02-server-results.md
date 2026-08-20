# 02 - Serve: load test + saturation reading

Host `Windows-AMD64` · llama.cpp `b10488` ·
`--parallel 4` · `ctx=2048` · `threads=16` ·
`ngl=99`

| Users | Reqs | RPS | P50 (ms) | P95 (ms) | P99 (ms) | Eff. concurrency | Failures |
|:--|--:|--:|--:|--:|--:|--:|--:|
| 10 | 27 | 0.47 | 16000 | 32000 | 33000 | 8.6 | 0.0% |
| 50 | 45 | 0.78 | 33000 | 54000 | 56000 | 24.9 | 0.0% |

*Effective concurrency = RPS x average latency (Little's Law) -- how many requests were
really in flight, regardless of how many users locust simulated. It counts queued requests
too, so the occupancy/slot ratio can legitimately exceed 1.0; it is occupancy, not
utilisation. For true slot utilisation use the server's own gauges (`make metrics`).*

## What these two runs say

| Going from 10 to 50 users | |
|:--|--:|
| Offered load | 5x |
| Throughput actually delivered | **1.67x** (33% of linear) |
| P95 latency | **1.69x** |
| Effective concurrency at 50 users | 24.9 vs `--parallel 4` slots (occupancy/slot ratio 6.24) |

**Saturated.** Throughput delivered only 1.67x for 5x the offered load, and effective concurrency (24.9) is at or above all 4 decode slots. Saturation sets in somewhere at or below 50 users; the load you added beyond that point became queue time rather than throughput.

Throughput moved 1.67x while P95 moved 1.69x. That gap is the goodput argument: past saturation you buy throughput by spending latency, and if your SLO is a P95 target then the requests you added are no longer being served within it. (This lab does not fix an SLO number for you -- pick one in your write-up and state how much goodput you keep at it.)

## My reading

The server is already queue-limited by 10 users (effective concurrency 8.6 exceeds four
slots) and is deeply saturated at 50: occupancy reaches 24.9, metrics show 46 deferred
requests, and a 5x load increase yields only 1.67x RPS while P95 rises from 32s to 54s.
For a 30s P95 SLO I would first cap admission/concurrency near four slots; this removes
queue time immediately, whereas adding context or CPU threads does not add decode capacity.
