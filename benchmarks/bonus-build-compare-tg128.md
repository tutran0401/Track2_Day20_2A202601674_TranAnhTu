# Bonus B1 - Prebuilt vs source build

Host `Windows-AMD64` · CPU `12th Gen Intel(R) Core(TM) i5-1240P`
Vector extensions detected: none
llama.cpp `b10488` both sides · `threads=12` ·
**both pinned to `ngl=0`** so this isolates the compiler ·
metric `tg128`, 3 repetitions

> **Backend mismatch, handled.** The prebuilt binary sees
> `['Vulkan0: Intel(R) Iris(R) Xe Graphics (8026 MiB, 7368 MiB free)']` and your source build sees `(no devices)`.
> Left at `-ngl 99` this comparison would have measured the accelerator and printed
> it under a compiler headline, so both sides were pinned to `-ngl 0`.

| Binary | Built for | tg128 (tok/s) | Relative |
|:--|--:|--:|--:|
| prebuilt release | runtime CPU dispatch | 42.7 | 1.00x |
| your source build | this CPU (`-DGGML_NATIVE=ON`) | 10.2 | 0.24x |

On this machine, the prebuilt binary is **4.18x faster**.

before: 42.7 tok/s (prebuilt release)
after:  10.2 tok/s (source build, -DGGML_NATIVE=ON)
speedup: 0.24x

Same source revision, same model, same backend, same `-ngl` -- the only difference
is what the compiler was allowed to assume about the CPU.



## My explanation

The source build losing is plausible because `-DGGML_NATIVE=ON` is permission, not a
guarantee of better code. The prebuilt release loaded its dedicated
`ggml-cpu-alderlake.dll`, built upstream with Clang 20 and runtime dispatch for this CPU.
My source binary used MinGW GCC 14 with `-march=native`; on the i5-1240P hybrid P/E-core
topology that toolchain/path produced far weaker Q4 decode kernels. Both tests used the same
revision, model, 12 threads and `ngl=0`, so Vulkan cannot explain the 4.18x gap. The result
means the production choice here is the prebuilt dispatched CPU backend, not the locally
compiled binary; “native” must always be benchmarked with the actual compiler and silicon.
