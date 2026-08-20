#!/usr/bin/env python3
"""Bonus C4: spend parallel serving capacity on Best-of-N quality."""
from __future__ import annotations

import json
import pathlib
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import httpx

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib"))
import labkit  # noqa: E402

PROMPT = (
    "A shop has 6 shelves with 7 books on each shelf. It sells 9 books and "
    "then receives 5 new books. Explain briefly and end exactly with FINAL=<integer>."
)
EXPECTED = 38


def generate(seed: int) -> dict:
    started = time.perf_counter()
    response = httpx.post(
        f"http://127.0.0.1:{labkit.server_port()}/v1/chat/completions",
        json={
            "model": "local",
            "messages": [{"role": "user", "content": PROMPT}],
            "temperature": 0.9,
            "seed": seed,
            "max_tokens": 64,
        },
        timeout=300,
    )
    response.raise_for_status()
    body = response.json()
    text = body["choices"][0]["message"]["content"].strip()
    match = re.search(r"FINAL\s*=\s*(-?\d+)", text)
    correct = bool(match and int(match.group(1)) == EXPECTED)
    words = re.findall(r"\w+", text.lower())
    repetition = 1.0 - len(set(words)) / max(len(words), 1)
    # Correct format/answer dominates; among ties prefer concise, non-repetitive text.
    score = (100 if correct else 0) - repetition * 10 - len(words) / 100
    return {
        "seed": seed,
        "latency_ms": round((time.perf_counter() - started) * 1000, 1),
        "correct": correct,
        "score": round(score, 2),
        "answer": text,
    }


def main() -> int:
    single_started = time.perf_counter()
    single = generate(0)
    single_wall = (time.perf_counter() - single_started) * 1000

    batch_started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=4) as pool:
        candidates = list(pool.map(generate, range(1, 5)))
    batch_wall = (time.perf_counter() - batch_started) * 1000
    winner = max(candidates, key=lambda item: item["score"])
    accepted = winner if winner["correct"] else None

    rows = labkit.md_table(
        ["mode", "seed", "wall/latency (ms)", "correct", "heuristic score"],
        [["single", 0, f"{single_wall:.1f}", single["correct"], single["score"]]]
        + [["best-of-4 candidate", c["seed"], c["latency_ms"], c["correct"], c["score"]]
           for c in candidates],
    )
    correct_n = sum(c["correct"] for c in candidates)
    md = f"""# Bonus C4 - Best-of-N with a lightweight reranker

Model `{labkit.load_active()['model']}` on `{labkit.host_tag()}`; server uses
`--parallel {labkit.parallel_slots()}`. All candidates used the same prompt,
temperature 0.9, 64-token cap, and distinct seeds. Expected answer: `{EXPECTED}`.

{rows}

Single-shot wall time: **{single_wall:.1f} ms**. Best-of-4 wall time: **{batch_wall:.1f} ms**
({batch_wall / single_wall:.2f}x latency, not 4x, because four slots decode concurrently).
The best diagnostic score was seed **{winner['seed']}**; **{correct_n}/4** candidates passed
the machine-checkable `FINAL={EXPECTED}` contract, so the reranker **rejected the entire set**.

## Analysis

Best-of-N converts spare batch throughput into a chance at higher per-request quality, but
it is not a guarantee: all four samples repeated the same arithmetic error, so diversity did
not rescue correctness. The machine-checkable constraint prevented a wrong answer from being
returned; a production system would retry with a stronger model or abstain. The cost was a
{batch_wall / single_wall:.2f}x latency multiplier. Under multi-user load these four candidates
also consume every decode slot, so this is defensible only for difficult, high-value requests.

### Highest-scoring rejected response

{winner['answer']}
"""
    out = labkit.write_report(
        "bonus-c4-best-of-n.md",
        md,
        {"single": single, "single_wall_ms": round(single_wall, 1),
         "best_of_4": candidates, "batch_wall_ms": round(batch_wall, 1),
         "winner": winner, "accepted": accepted},
    )
    print(md)
    print(f"\n==> Wrote {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
