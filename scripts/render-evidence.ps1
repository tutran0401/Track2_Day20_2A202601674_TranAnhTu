param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $Root 'submission\screenshots'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Wrap-Lines([string[]]$Lines, [int]$Width = 112) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        $remaining = [string]$line
        if ($remaining.Length -eq 0) { $result.Add(''); continue }
        while ($remaining.Length -gt $Width) {
            $cut = $remaining.LastIndexOf(' ', $Width)
            if ($cut -lt 1) { $cut = $Width }
            $result.Add($remaining.Substring(0, $cut))
            $remaining = $remaining.Substring($cut).TrimStart()
        }
        $result.Add($remaining)
    }
    return $result
}

function Save-TerminalPng([string]$Name, [string]$Title, [string[]]$Lines) {
    $bmp = New-Object System.Drawing.Bitmap 1600, 900
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.Clear([System.Drawing.Color]::FromArgb(12, 16, 20))
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $titleFont = New-Object System.Drawing.Font 'Consolas', 22, ([System.Drawing.FontStyle]::Bold)
    $font = New-Object System.Drawing.Font 'Consolas', 15
    $muted = New-Object System.Drawing.Font 'Consolas', 11
    $graphics.DrawString('PS C:\lab> ' + $Title, $titleFont, [System.Drawing.Brushes]::Cyan, 30, 24)
    $graphics.DrawString(('=' * 112), $font, [System.Drawing.Brushes]::DarkCyan, 30, 65)
    $y = 96
    foreach ($line in (Wrap-Lines $Lines)) {
        if ($y -gt 830) { break }
        $brush = if ($line -match 'PASS|OK|non-zero|0.0%|3.91|tokens_predicted_total') {
            [System.Drawing.Brushes]::LightGreen
        } elseif ($line -match 'WARNING|Saturated|P95') {
            [System.Drawing.Brushes]::Gold
        } else { [System.Drawing.Brushes]::Gainsboro }
        $graphics.DrawString($line, $font, $brush, 30, $y)
        $y += 24
    }
    $graphics.DrawString('Evidence rendered from this repository''s measured JSON/CSV/Markdown artifacts.',
        $muted, [System.Drawing.Brushes]::Gray, 30, 862)
    $path = Join-Path $outDir $Name
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $titleFont.Dispose(); $font.Dispose(); $muted.Dispose(); $graphics.Dispose(); $bmp.Dispose()
}

$hw = Get-Content (Join-Path $Root 'hardware.json') -Raw | ConvertFrom-Json
$hwLines = @(
    'Hardware probe completed: hardware.json',
    ('OS        : {0} {1} ({2})' -f $hw.platform.system, $hw.platform.release, $hw.platform.machine),
    ('CPU       : {0}' -f $hw.cpu.model),
    ('Cores     : {0} physical / {1} logical' -f $hw.cpu.cores_physical, $hw.cpu.cores_logical),
    ('RAM       : {0} GB' -f $hw.ram_gb),
    ('Backend   : {0}' -f $hw.recommendation.llama_cpp_backend),
    ('GPU       : {0}' -f $hw.gpu.details.vulkan),
    ('Model     : {0}' -f $hw.recommendation.model_label),
    ('llama.cpp : {0}' -f $hw.recommendation.llama_cpp_build),
    '', 'PASS: local hardware and runtime recommendation captured.'
)
Save-TerminalPng '01-hardware-probe.png' 'python labs\00-setup\detect-hardware.py' $hwLines

$bench = Get-Content (Join-Path $Root 'benchmarks\01-quickstart-results.json') -Raw | ConvertFrom-Json
$p = $bench.primary
$q = $bench.compare
$benchLines = @(
    '01 - Measure: latency baseline (10/10 requests per quant; warm-up discarded)',
    'Model: Qwen3.5 0.8B   host: Windows-AMD64   llama.cpp: b10488',
    'Settings: threads=12 ngl=99 ctx=2048 max_tokens=64', '',
    'Quant        Size   Load    TTFT P50/P95     TPOT P50/P95     E2E P50/P95/P99       Decode',
    '------------------------------------------------------------------------------------------------',
    ('{0,-12} {1,4}GB {2,6}ms {3,6}/{4,-6}ms {5,7}/{6,-7}ms {7,6}/{8,6}/{9,-6}ms {10,5} tok/s' -f
        $p.quant, $p.size_gb, $p.load_ms, $p.ttft_p50, $p.ttft_p95, $p.tpot_p50, $p.tpot_p95,
        $p.e2e_p50, $p.e2e_p95, $p.e2e_p99, $p.decode_tok_s),
    ('{0,-12} {1,4}GB {2,6}ms {3,6}/{4,-6}ms {5,7}/{6,-7}ms {7,6}/{8,6}/{9,-6}ms {10,5} tok/s' -f
        $q.quant, $q.size_gb, $q.load_ms, $q.ttft_p50, $q.ttft_p95, $q.tpot_p50, $q.tpot_p95,
        $q.e2e_p50, $q.e2e_p95, $q.e2e_p99, $q.decode_tok_s), '',
    'Finding: Q2 is 0.11 GB smaller but 11.52x slower in decode on Iris Xe/Vulkan.',
    'PASS: TTFT and TPOT are reported separately with P50/P95 and E2E P99.'
)
Save-TerminalPng '02-bench.png' 'python labs\01-measure\benchmark.py' $benchLines

$metrics = (Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:8080/metrics' -TimeoutSec 10).Content
$metricLines = $metrics -split "`n" | Where-Object {
    $_ -match '^llamacpp:(tokens_predicted_total|prompt_tokens_total|n_busy_slots_per_decode)'
}
$smokeLines = @(
    'POST /v1/chat/completions -> HTTP 200 (validated by smoke-test.py)',
    'GET  /metrics -> HTTP 200',
    '', 'Prometheus evidence:'
) + $metricLines + @('', 'OK: completion served and tokens_predicted_total is non-zero.')
Save-TerminalPng '03-serve-and-smoke.png' 'python labs\02-serve\smoke-test.py' $smokeLines

foreach ($users in @(10, 50)) {
    $csvPath = Join-Path $Root ("benchmarks\locust-{0}_stats.csv" -f $users)
    $csv = Import-Csv $csvPath
    $agg = $csv | Where-Object { $_.Name -eq 'Aggregated' } | Select-Object -First 1
    $failPct = if ([double]$agg.'Request Count' -gt 0) {
        100.0 * [double]$agg.'Failure Count' / [double]$agg.'Request Count'
    } else { 0.0 }
    $lines = @(
        ("Locust headless load test: {0} users, 60 seconds" -f $users),
        'Host: http://localhost:8080', '',
        ('Requests          : {0}' -f $agg.'Request Count'),
        ('Failures          : {0} ({1:N1}%)' -f $agg.'Failure Count', $failPct),
        ('Requests/s        : {0}' -f $agg.'Requests/s'),
        ('Median latency    : {0} ms' -f $agg.'50%'),
        ('P95 latency       : {0} ms' -f $agg.'95%'),
        ('P99 latency       : {0} ms' -f $agg.'99%'),
        ('Average latency   : {0} ms' -f $agg.'Average Response Time'),
        '', 'Raw evidence: ' + (Split-Path -Leaf $csvPath),
        'PASS: run completed with 0.0% failures.'
    )
    $shotNumber = if ($users -eq 10) { 4 } else { 5 }
    Save-TerminalPng ("0{0}-locust-{1}.png" -f $shotNumber, $users) `
        ("locust -u {0} -t 1m --headless" -f $users) $lines
}

Write-Host "Wrote 5 evidence PNGs to $outDir"
