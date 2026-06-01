from __future__ import annotations


def build_histogram(diameters: list[float], mode: str) -> tuple[list[dict], str]:
    if mode != "calibrated":
        return [], "需要硬幣校正後才顯示 0-1000um 曲線"

    min_value = 0.0
    max_value = 1000.0
    bins_count = 40
    step = (max_value - min_value) / bins_count
    buckets = [0] * bins_count
    underflow = 0
    overflow = 0

    for d in diameters:
        if d < min_value:
            underflow += 1
        elif d > max_value:
            overflow += 1
        else:
            idx = min(bins_count - 1, max(0, int((d - min_value) / step)))
            buckets[idx] += 1

    bins = [
        {"start": min_value + i * step, "end": min_value + (i + 1) * step, "count": buckets[i]}
        for i in range(bins_count)
    ]
    min_d = min(diameters) if diameters else 0.0
    max_d = max(diameters) if diameters else 0.0
    meta = (
        f"顆粒總數 {len(diameters)} | 範圍外: <0um {underflow}, >1000um {overflow} | "
        f"本次最小/最大: {min_d:.1f} / {max_d:.1f} um"
    )
    return bins, meta
