package com.grindscale.android.analysis

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

internal fun connectedComponents(
    mask: ByteArray,
    width: Int,
    height: Int,
    minArea: Int,
    maxArea: Int
): List<List<Int>> {
    val visited = BooleanArray(mask.size)
    val neighbors = listOf(
        Pair(-1, -1), Pair(-1, 0), Pair(-1, 1),
        Pair(0, -1), Pair(0, 1),
        Pair(1, -1), Pair(1, 0), Pair(1, 1)
    )
    val components = ArrayList<List<Int>>()
    fun isOn(idx: Int) = mask[idx] != 0.toByte()

    for (index in mask.indices) {
        if (visited[index] || !isOn(index)) continue
        visited[index] = true
        val queue = ArrayDeque<Int>()
        queue.add(index)
        val component = ArrayList<Int>(128)

        while (queue.isNotEmpty()) {
            val current = queue.removeFirst()
            component.add(current)
            val y = current / width
            val x = current % width
            for ((dy, dx) in neighbors) {
                val ny = y + dy
                val nx = x + dx
                if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue
                val ni = ny * width + nx
                if (visited[ni] || !isOn(ni)) continue
                visited[ni] = true
                queue.add(ni)
            }
        }
        val n = component.size
        if (n in minArea..maxArea) components.add(component)
    }
    return components
}

internal fun splitTouchingComponents(
    componentsIn: List<List<Int>>,
    width: Int,
    height: Int
): List<List<Int>> {
    val output = ArrayList<List<Int>>(componentsIn.size)
    for (component in componentsIn) {
        val circScore = circularity(component, width, height)
        val ratioScore = aspectRatioScore(component, width)
        val fillRatio = boundingBoxFillRatio(component, width)
        if (component.size < 28) {
            output.add(component)
            continue
        }
        if (component.size < 240) {
            if (circScore >= 0.44 && fillRatio >= 0.33) {
                output.add(component)
                continue
            }
        }
        if (component.size in 901 until 4500 &&
            circScore > 0.68 && ratioScore > 0.74 && fillRatio > 0.43
        ) {
            output.add(component)
            continue
        }

        val first = component.first()
        var minX = first % width
        var maxX = minX
        var minY = first / width
        var maxY = minY
        for (idx in component) {
            val x = idx % width
            val y = idx / width
            if (x < minX) minX = x
            if (x > maxX) maxX = x
            if (y < minY) minY = y
            if (y > maxY) maxY = y
        }
        val bw = maxX - minX + 1
        val bh = maxY - minY + 1
        if (bw < 6 || bh < 6) {
            output.add(component)
            continue
        }

        val localCount = bw * bh
        val localMask = ByteArray(localCount)
        for (idx in component) {
            val x = idx % width
            val y = idx / width
            val lx = x - minX
            val ly = y - minY
            localMask[ly * bw + lx] = 1
        }

        var dist = distanceTransform(localMask, bw, bh)
        dist = smoothDistanceMap(dist, localMask, bw, bh)
        val seeds = distanceSeeds(dist, localMask, bw, bh)
        if (seeds.size <= 1) {
            val fallbackGroups = splitLargeConnectedComponent(component, width, height)
            if (fallbackGroups.size > 1) {
                output.addAll(recursivelySplitLargeGroups(fallbackGroups, width, height, depth = 1))
                continue
            }
            output.add(component)
            continue
        }

        val groups = assignPixelsToSeeds(
            localMask, bw, bh, seeds, minX, minY, width
        )
        if (groups.size <= 1) {
            output.add(component)
            continue
        }
        output.addAll(recursivelySplitLargeGroups(groups, width, height, depth = 1))
    }
    return output
}

internal fun distanceTransform(mask: ByteArray, width: Int, height: Int): DoubleArray {
    val inf = 1_000_000.0
    val dist = DoubleArray(mask.size) { inf }
    for (i in mask.indices) {
        if (mask[i] == 0.toByte()) dist[i] = 0.0
    }
    val diag = sqrt(2.0)
    for (y in 0 until height) {
        for (x in 0 until width) {
            val idx = y * width + x
            if (mask[idx] == 0.toByte()) continue
            var best = dist[idx]
            if (x > 0) best = min(best, dist[idx - 1] + 1.0)
            if (y > 0) best = min(best, dist[idx - width] + 1.0)
            if (x > 0 && y > 0) best = min(best, dist[idx - width - 1] + diag)
            if (x + 1 < width && y > 0) best = min(best, dist[idx - width + 1] + diag)
            dist[idx] = best
        }
    }
    for (y in height - 1 downTo 0) {
        for (x in width - 1 downTo 0) {
            val idx = y * width + x
            if (mask[idx] == 0.toByte()) continue
            var best = dist[idx]
            if (x + 1 < width) best = min(best, dist[idx + 1] + 1.0)
            if (y + 1 < height) best = min(best, dist[idx + width] + 1.0)
            if (x + 1 < width && y + 1 < height) best = min(best, dist[idx + width + 1] + diag)
            if (x > 0 && y + 1 < height) best = min(best, dist[idx + width - 1] + diag)
            dist[idx] = best
        }
    }
    return dist
}

internal fun smoothDistanceMap(d: DoubleArray, mask: ByteArray, width: Int, height: Int): DoubleArray {
    val out = d.copyOf()
    for (y in 0 until height) {
        for (x in 0 until width) {
            val idx = y * width + x
            if (mask[idx] == 0.toByte()) continue
            var sum = 0.0
            var count = 0.0
            for (dy in -1..1) {
                for (dx in -1..1) {
                    val ny = y + dy
                    val nx = x + dx
                    if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue
                    val ni = ny * width + nx
                    if (mask[ni] == 0.toByte()) continue
                    sum += d[ni]
                    count += 1.0
                }
            }
            out[idx] = if (count > 0) sum / count else d[idx]
        }
    }
    return out
}

internal data class Seed(val x: Int, val y: Int, val score: Double)

internal fun distanceSeeds(dist: DoubleArray, mask: ByteArray, width: Int, height: Int): List<Pair<Int, Int>> {
    var maxDistance = 0.0
    for (i in dist.indices) {
        if (mask[i] != 0.toByte() && dist[i] > maxDistance) maxDistance = dist[i]
    }
    if (maxDistance < 0.95) return emptyList()

    val minPeakValue = max(0.52, maxDistance * 0.11)
    val minSpacing = max(2, (maxDistance * 0.26).toInt())
    val candidates = ArrayList<Seed>()

    for (y in 1 until height - 1) {
        for (x in 1 until width - 1) {
            val idx = y * width + x
            if (mask[idx] == 0.toByte()) continue
            val center = dist[idx]
            if (center < minPeakValue) continue
            var isPeak = true
            for (dy in -1..1) {
                for (dx in -1..1) {
                    if (dx == 0 && dy == 0) continue
                    val nidx = (y + dy) * width + (x + dx)
                    if (dist[nidx] > center) {
                        isPeak = false
                        break
                    }
                }
                if (!isPeak) break
            }
            if (isPeak) candidates.add(Seed(x, y, center))
        }
    }
    if (candidates.isEmpty()) return emptyList()
    candidates.sortByDescending { it.score }
    val seeds = ArrayList<Pair<Int, Int>>()
    val minSpacingSq = minSpacing * minSpacing
    for (c in candidates) {
        var tooClose = false
        for (seed in seeds) {
            val dx = seed.first - c.x
            val dy = seed.second - c.y
            if (dx * dx + dy * dy < minSpacingSq) {
                tooClose = true
                break
            }
        }
        if (!tooClose) seeds.add(Pair(c.x, c.y))
        if (seeds.size >= 36) break
    }
    return seeds
}

internal fun splitLargeConnectedComponent(component: List<Int>, width: Int, height: Int): List<List<Int>> {
    if (component.size < 380) return emptyList()

    val circ = circularity(component, width, height)
    val ratio = aspectRatioScore(component, width)
    if (ratio > 0.82 && circ > 0.56) return emptyList()

    var minX = Int.MAX_VALUE
    var maxX = Int.MIN_VALUE
    var minY = Int.MAX_VALUE
    var maxY = Int.MIN_VALUE
    for (idx in component) {
        val x = idx % width
        val y = idx / width
        if (x < minX) minX = x
        if (x > maxX) maxX = x
        if (y < minY) minY = y
        if (y > maxY) maxY = y
    }
    val bw = max(1, maxX - minX + 1)
    val bh = max(1, maxY - minY + 1)
    val longOverShort = max(bw, bh).toDouble() / min(bw, bh).toDouble()
    val fill = boundingBoxFillRatio(component, width)
    if (longOverShort < 1.18) {
        if (!(fill < 0.37 && circ < 0.36 && component.size >= 700)) return emptyList()
    }
    if (longOverShort < 1.28 && circ > 0.34) return emptyList()

    val splitByX = bw >= bh
    var c1 = if (splitByX) minX.toDouble() else minY.toDouble()
    var c2 = if (splitByX) maxX.toDouble() else maxY.toDouble()
    if (abs(c2 - c1) < 8) return emptyList()

    repeat(8) {
        var sum1 = 0.0
        var cnt1 = 0
        var sum2 = 0.0
        var cnt2 = 0
        for (idx in component) {
            val axis = if (splitByX) (idx % width).toDouble() else (idx / width).toDouble()
            if (abs(axis - c1) <= abs(axis - c2)) {
                sum1 += axis
                cnt1++
            } else {
                sum2 += axis
                cnt2++
            }
        }
        if (cnt1 == 0 || cnt2 == 0) return emptyList()
        c1 = sum1 / cnt1.toDouble()
        c2 = sum2 / cnt2.toDouble()
    }

    if (abs(c2 - c1) < 6) return emptyList()

    val g1 = ArrayList<Int>(component.size / 2)
    val g2 = ArrayList<Int>(component.size / 2)
    for (idx in component) {
        val axis = if (splitByX) (idx % width).toDouble() else (idx / width).toDouble()
        if (abs(axis - c1) <= abs(axis - c2)) g1.add(idx) else g2.add(idx)
    }
    val minArea = AnalyzerConstants.MIN_AREA
    if (g1.size < minArea || g2.size < minArea) return emptyList()
    return listOf(g1, g2)
}

internal fun recursivelySplitLargeGroups(
    groups: List<List<Int>>,
    width: Int,
    height: Int,
    depth: Int
): List<List<Int>> {
    if (depth >= 2) return groups
    val result = ArrayList<List<Int>>()
    for (group in groups) {
        val extra = splitLargeConnectedComponentMulti(group, width, height)
        if (extra.size > 1) {
            result.addAll(recursivelySplitLargeGroups(extra, width, height, depth + 1))
        } else {
            result.add(group)
        }
    }
    return result
}

internal fun splitLargeConnectedComponentMulti(component: List<Int>, width: Int, height: Int): List<List<Int>> {
    if (component.size < 650) return emptyList()
    val circ = circularity(component, width, height)
    val ratio = aspectRatioScore(component, width)
    val fill = boundingBoxFillRatio(component, width)

    val likelyMerged =
        circ < 0.22 ||
            fill < 0.26 ||
            (ratio < 0.58 && fill < 0.46) ||
            (circ < 0.38 && fill < 0.34) ||
            component.size > 9000
    if (!likelyMerged) return emptyList()

    var k = kotlin.math.round(component.size.toDouble() / 2200.0).toInt()
    k = max(2, min(6, k))

    val points = ArrayList<Pair<Double, Double>>(component.size)
    for (idx in component) {
        points.add(Pair((idx % width).toDouble(), (idx / width).toDouble()))
    }
    if (points.size < k) return emptyList()

    val centers = ArrayList<Pair<Double, Double>>(k)
    centers.add(points[0])
    while (centers.size < k) {
        var bestPoint = points[0]
        var bestDist = -1.0
        for (p in points) {
            var nearest = Double.POSITIVE_INFINITY
            for (c in centers) {
                val dx = p.first - c.first
                val dy = p.second - c.second
                val d2 = dx * dx + dy * dy
                if (d2 < nearest) nearest = d2
            }
            if (nearest > bestDist) {
                bestDist = nearest
                bestPoint = p
            }
        }
        centers.add(bestPoint)
    }

    val assignments = IntArray(points.size)
    repeat(10) {
        val sumX = DoubleArray(k)
        val sumY = DoubleArray(k)
        val cnt = IntArray(k)
        for (i in points.indices) {
            val p = points[i]
            var bestIdx = 0
            var bestD = Double.POSITIVE_INFINITY
            for (ci in 0 until k) {
                val dx = p.first - centers[ci].first
                val dy = p.second - centers[ci].second
                val d2 = dx * dx + dy * dy
                if (d2 < bestD) {
                    bestD = d2
                    bestIdx = ci
                }
            }
            assignments[i] = bestIdx
            sumX[bestIdx] += p.first
            sumY[bestIdx] += p.second
            cnt[bestIdx]++
        }
        var changed = false
        for (ci in 0 until k) {
            if (cnt[ci] <= 0) continue
            val nx = sumX[ci] / cnt[ci].toDouble()
            val ny = sumY[ci] / cnt[ci].toDouble()
            val dx = nx - centers[ci].first
            val dy = ny - centers[ci].second
            if (dx * dx + dy * dy > 0.25) changed = true
            centers[ci] = Pair(nx, ny)
        }
        if (!changed) break
    }

    val groups = Array(k) { ArrayList<Int>() }
    for (i in component.indices) {
        groups[assignments[i]].add(component[i])
    }
    val valid = groups.filter { it.size >= AnalyzerConstants.MIN_AREA }
    if (valid.size < 2) return emptyList()
    val largest = valid.maxOfOrNull { it.size } ?: component.size
    if (largest.toDouble() / component.size.toDouble() > 0.90) return emptyList()
    return valid
}

internal fun assignPixelsToSeeds(
    mask: ByteArray,
    bw: Int,
    bh: Int,
    seeds: List<Pair<Int, Int>>,
    minX: Int,
    minY: Int,
    imageWidth: Int
): List<List<Int>> {
    val groups = Array(seeds.size) { ArrayList<Int>() }
    for (y in 0 until bh) {
        for (x in 0 until bw) {
            val idx = y * bw + x
            if (mask[idx] == 0.toByte()) continue
            var bestSeed = 0
            var bestScore = Int.MAX_VALUE
            for (i in seeds.indices) {
                val dx = x - seeds[i].first
                val dy = y - seeds[i].second
                val score = dx * dx + dy * dy
                if (score < bestScore) {
                    bestScore = score
                    bestSeed = i
                }
            }
            val globalX = minX + x
            val globalY = minY + y
            groups[bestSeed].add(globalY * imageWidth + globalX)
        }
    }
    val filtered = groups.filter { it.size >= AnalyzerConstants.MIN_AREA }
    return filtered
}
