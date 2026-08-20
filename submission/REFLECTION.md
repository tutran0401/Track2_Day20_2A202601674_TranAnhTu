# Reflection — Day 20 Lab (Personal Report)

**Họ tên:** Trần Anh Tú  
**Mã học viên / cohort:** 2A202601674 — Track 2  
**Ngày submit:** 2026-08-20

---

## 1. Hardware & runtime

- **OS:** Windows 10, AMD64
- **CPU:** 12th Gen Intel(R) Core(TM) i5-1240P
- **Cores:** 12 physical / 16 logical
- **CPU extensions/runtime:** llama.cpp Alder Lake CPU backend; Vulkan offload enabled
- **RAM:** 15.7 GB
- **Accelerator:** Intel Iris Xe Graphics via Vulkan (UMA, FP16, integer dot product)
- **llama.cpp asset:** `llama-b10488-bin-win-vulkan-x64.zip`, build b10488
- **Model:** Qwen3.5 0.8B (`LAB_MODEL=qwen35-0.8b`)
- **Quantization:** Q4_K_M primary + UD-Q2_K_XL comparison
- **Chạy ở đâu:** laptop cá nhân, local; không dùng Colab/Kaggle

**Setup story:** Repo nằm trong đường dẫn Windows có ký tự tiếng Việt. PowerShell 5 đọc
script UTF-8 không BOM sai và `llama-bench` b10488 không mở được model qua argv Unicode.
Tôi chạy các entry point Python trực tiếp và sửa helper dùng Windows 8.3 short path, đồng
thời decode output native với replacement. Benchmark logic, flags và model không đổi.

---

## 2. Đo lường

| Quantization | Size (GB) | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode (tok/s) |
|---|--:|--:|--:|--:|--:|--:|
| Q4_K_M | 0.50 | 6571 | 956 / 1329 | 32.2 / 33.4 | 2902 / 3321 / 3321 | 31.1 |
| UD-Q2_K_XL | 0.39 | 10629 | 1478 / 1810 | 374.5 / 407.7 | 25189 / 27293 / 27293 | 2.7 |

**Quan sát:** Q2 nhỏ hơn 22% nhưng decode chậm hơn 11.52× và TTFT P50 cao hơn 1.55×,
nên không đáng dùng trên máy này. Vulkan/Iris Xe có đường Q4 hiệu quả, trong khi unpack và
dequantize UD-Q2 làm kernel bị compute-bound. Q4 cũng giữ quality headroom tốt hơn, vì vậy
tôi chọn Q4 cho serving.

---

## 3. Serving under load

| Users | RPS | P50 (ms) | P95 (ms) | P99 (ms) | Eff. concurrency | Failures |
|--:|--:|--:|--:|--:|--:|--:|
| 10 | 0.47 | 16000 | 32000 | 33000 | 8.6 | 0.0% |
| 50 | 0.78 | 33000 | 54000 | 56000 | 24.9 | 0.0% |

- **Offered load tăng 5×, throughput thực tăng:** 1.67×
- **P95 tăng:** 1.69×
- **Effective concurrency ở 50 users:** 24.9 so với `--parallel=4`
- **Peak `llamacpp:n_busy_slots_per_decode`:** 3.91 / 4 slots (98%)
- **Peak deferred requests:** 46

**Saturation reading:** Server đã queue-limit ở 10 users vì occupancy 8.6 vượt bốn slot;
ở 50 users nó bão hòa rõ rệt: 5× offered load chỉ cho 1.67× RPS, P95 tăng 32s→54s và 46
request bị deferred. Với SLO P95=30s, tôi sẽ admission-control gần bốn concurrent request
trước: knob này cắt queue time; tăng context/thread không tạo thêm decode capacity.

Gauge batch width và Little's Law không mâu thuẫn: 3.91 là số slot thực sự decode trung
bình mỗi step, còn 24.9 gồm cả bốn request đang chạy lẫn request chờ. Chính deferred=46
giải thích khoảng cách đó và chứng minh continuous batching đang hoạt động.

---

## 4. Integration

| Day | Piece | Real hay stub? |
|---|---|---|
| N16 Cloud/IaC | localhost process, không cluster/Compose | stub |
| N17 Data pipeline | in-memory `TOY_DOCS` list | stub |
| N18 Lakehouse | toy Python dictionary, không Delta/Iceberg | stub |
| N19 Vector + features | keyword-overlap retrieval, không vector DB/Feast | stub |
| N20 Serving | OpenAI-compatible `llama-server` | real |

**Latency split, mean của 3 query:**

- embed: 0.0 ms
- retrieve: 0.0 ms (0.1 ms ở query thứ ba, làm tròn mean còn 0.0)
- llm: 5569.1 ms
- total: 5569.2 ms
- **stage chiếm nhiều nhất:** llm (100% sau khi làm tròn)

**Reflection:** Bottleneck là N20 LLM, đúng kỳ vọng vì retrieval hiện chỉ duyệt một toy
list trong RAM. Muốn giảm latency 2×, tôi ưu tiên rút ngắn output và retrieved context,
sau đó chọn quant/backend nhanh có kiểm chứng. Tối ưu sub-millisecond retrieval không thể
bù được 5.57 giây prefill/decode.

---

## 5. The single change that mattered most

**Change:** tăng thread count từ mặc định `-t 12` lên winner `-t 16` với Q4, `ngl=99`.

```text
before:  34.1 tok/s ở -t 12
after:   34.3 tok/s ở -t 16
speedup: 1.01×
```

**Tại sao nó work:** Đây là một cải thiện nhỏ nhưng là kết quả có thể tái lập. Curve gần
như phẳng: 1, 6, 12, 16 và 32 threads đều nằm trong 33.7–34.3 tok/s. Do toàn bộ 99 layer
được offload lên Iris Xe, decode bị chi phối bởi GPU kernel và băng thông bộ nhớ UMA;
thread CPU chủ yếu chuẩn bị/feed work. Vì vậy thêm bốn logical thread chỉ giảm chút thời
gian scheduling/feed, không thể nhân throughput theo số core.

Ở 32 threads, throughput lại giảm còn 33.7 tok/s. Lúc này oversubscription tạo thêm
scheduling, synchronization và contention nhưng không thêm memory bandwidth hay GPU
execution units. Kết quả khác curve CPU-only trong slide, và chính `ngl=99` giải thích vì
sao physical-core count không tạo “knee” rõ trên máy này.

---

## 6. Bonus

**Đã làm:** B1 source-build comparison; B2 context-length sweep; B3 before/after từ B2;
B4 challenge C4 Best-of-N; B5/C8 semantic cache offline threshold sweep.

### B1 — Prebuilt vs source build

Hai binary cùng revision b10488, Q4, 12 threads và `ngl=0`: prebuilt đạt 42.7 tok/s,
source MinGW GCC 14 `-DGGML_NATIVE=ON` chỉ đạt 10.2 tok/s (0.24×; prebuilt nhanh hơn
4.18×). Prebuilt load backend `ggml-cpu-alderlake.dll` build bằng Clang 20 và runtime
dispatch đúng vi kiến trúc; `-march=native` trên MinGW với CPU hybrid P/E-core không bảo
đảm kernel tốt hơn. Vì đã pin CPU-only, Vulkan không thể giải thích chênh lệch này.

### B2/B3 — Giới hạn context như một latency knob

```text
before:  8192 prompt tokens -> 24996.2 ms prefill
after:   4096 prompt tokens ->  9955.8 ms prefill
speedup: 2.51× lower prefill latency
```

256→2048 tokens gần tuyến tính, nhưng 4096 mất 9.96s và 8192 mất 25.00s, tức 1.37×
projection tuyến tính từ điểm 256. Attention O(N²) và throughput prefill giảm 448.3→327.7
tok/s tạo ra bend. Context window là capacity ceiling, không phải target: RAG nên rerank,
lọc chunk và áp token budget thay vì nhồi đủ 8192 token.

### B4/C4 — Best-of-4

Single shot mất 3161.3 ms; bốn sample chạy đồng thời qua bốn slot mất 5128.1 ms, chỉ 1.62×
chứ không phải 4×. Tuy nhiên 0/4 candidate thỏa `FINAL=38`; model lặp lại cùng một lỗi số
học. Finding quan trọng: sampling diversity không đảm bảo correctness. Reranker có contract
phải abstain/retry bằng model mạnh hơn khi cả set fail, không được chọn đáp án “ít tệ nhất”.
Ở tải cao, Best-of-4 còn chiếm hết slot và làm request khác phải chờ.

### B5/C8 — Semantic cache offline

Threshold 0.70–0.95 đều cho 3/8 hit (38%), tiết kiệm khoảng 750 ms decode mô phỏng. Curve
phẳng là artifact của bag-of-words stub chỉ sinh similarity gần 0 hoặc 1, không phải bằng
chứng threshold không quan trọng. Nó false-miss paraphrase thật ở score 0.00; cần encoder
sentence chuyên dụng trước khi đánh giá cache. Production cũng phải partition/salt theo
tenant để tránh leakage và timing side channel.

---

## 7. Điều làm tôi ngạc nhiên nhất

Quant 2-bit nhỏ hơn lại chậm hơn Q4 tới 11.52× trên Iris Xe/Vulkan. “Ít byte hơn” chỉ giúp
khi memory bandwidth là bottleneck và backend có kernel phù hợp; format/kernel support có
thể đảo ngược hoàn toàn trực giác quantization.

---

## 8. Self-check

- [x] `hardware.json` và `models/active.json`
- [x] Hai quant, TTFT/TPOT riêng và thread tuning
- [x] Smoke test có completion và non-zero metrics
- [x] Load 10/50 users, batching metrics chạy chồng load-50
- [x] Saturation report và RAG pipeline đủ 3 query
- [x] Không còn placeholder bắt buộc trong report
- [x] Bonus B2, B3, B4 và B5 có artifact/phân tích
- [x] Năm ảnh bằng chứng trong `submission/screenshots/`
