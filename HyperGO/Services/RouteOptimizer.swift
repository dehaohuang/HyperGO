import Foundation
import CoreLocation

/// 求经过所有选中地点的最短顺序（旅行商问题）。
/// - 12 个点以内：Held-Karp 动态规划，保证最优
/// - 更多点：多个起点的最近邻 + 2-opt + Or-opt 局部优化，取最好的一条（近似最优）
enum RouteOptimizer {
    struct Result {
        /// points 的下标，按访问顺序
        let order: [Int]
        /// 直线距离总长（米），包含从起点出发和（可选）返回起点
        let totalMeters: Double
    }

    static func optimize(points: [CLLocationCoordinate2D],
                         start: CLLocationCoordinate2D?,
                         returnToStart: Bool) -> Result {
        let locs = points.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let startLoc = start.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let n = locs.count
        var d = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in 0..<n where i != j {
                d[i][j] = locs[i].distance(from: locs[j])
            }
        }
        let s = locs.map { startLoc?.distance(from: $0) ?? 0 }
        return TSPSolver.solve(distances: d, fromStart: s, returnToStart: returnToStart && startLoc != nil)
    }
}

/// 纯算法部分，不依赖任何框架，方便测试。
enum TSPSolver {
    /// - distances: 地点间距离矩阵 d[i][j]
    /// - fromStart: 起点到每个地点的距离；没有固定起点时全为 0（即可以从任意地点开始）
    /// - returnToStart: 是否需要回到起点
    static func solve(distances d: [[Double]], fromStart s: [Double], returnToStart: Bool) -> RouteOptimizer.Result {
        let n = d.count
        guard n > 0 else { return .init(order: [], totalMeters: 0) }
        let order = n <= 12
            ? heldKarp(d, s, returnToStart)
            : bestOfStarts(d, s, returnToStart)
        return .init(order: order, totalMeters: cost(order, d, s, returnToStart))
    }

    static func cost(_ order: [Int], _ d: [[Double]], _ s: [Double], _ ret: Bool) -> Double {
        guard let first = order.first, let last = order.last else { return 0 }
        var total = s[first]
        for k in order.indices.dropFirst() {
            total += d[order[k - 1]][order[k]]
        }
        if ret { total += s[last] }
        return total
    }

    static func heldKarp(_ d: [[Double]], _ s: [Double], _ ret: Bool) -> [Int] {
        let n = d.count
        let full = 1 << n
        var dp = [Double](repeating: .infinity, count: full * n)
        var parent = [Int](repeating: -1, count: full * n)
        for j in 0..<n { dp[(1 << j) * n + j] = s[j] }

        for mask in 1..<full {
            for j in 0..<n where mask & (1 << j) != 0 {
                let cur = dp[mask * n + j]
                if cur == .infinity { continue }
                for k in 0..<n where mask & (1 << k) == 0 {
                    let next = mask | (1 << k)
                    let c = cur + d[j][k]
                    if c < dp[next * n + k] {
                        dp[next * n + k] = c
                        parent[next * n + k] = j
                    }
                }
            }
        }

        var best = Double.infinity
        var last = 0
        for j in 0..<n {
            let c = dp[(full - 1) * n + j] + (ret ? s[j] : 0)
            if c < best { best = c; last = j }
        }

        var order: [Int] = []
        var mask = full - 1
        var j = last
        while j != -1 {
            order.append(j)
            let p = parent[mask * n + j]
            mask &= ~(1 << j)
            j = p
        }
        return order.reversed()
    }

    /// 从最有希望的若干个地点分别出发做最近邻，再局部优化，取总长最短的
    static func bestOfStarts(_ d: [[Double]], _ s: [Double], _ ret: Bool) -> [Int] {
        let n = d.count
        let tries = n <= 80 ? n : (n <= 300 ? 40 : (n <= 600 ? 10 : 3))
        let seeds = s.indices.sorted { s[$0] < s[$1] }.prefix(tries)
        var best: [Int] = []
        var bestCost = Double.infinity
        for seed in seeds {
            let order = improve(nearestNeighbor(d, s, first: seed), d, s, ret)
            let c = cost(order, d, s, ret)
            if c < bestCost { bestCost = c; best = order }
        }
        return best
    }

    /// 轮流做 2-opt 和 Or-opt，直到两者都改不动
    static func improve(_ initial: [Int], _ d: [[Double]], _ s: [Double], _ ret: Bool) -> [Int] {
        var order = initial
        while true {
            let a = twoOptPass(&order, d, s, ret)
            let b = orOptPass(&order, d, s, ret)
            if !a && !b { return order }
        }
    }

    /// 两点之间的距离；-1 表示路线的起点/终点（起点到地点用 s，终点只有「回到起点」时才计距离）
    @inline(__always)
    private static func edge(_ a: Int, _ b: Int, _ d: [[Double]], _ s: [Double], _ ret: Bool) -> Double {
        if a < 0 { return b < 0 ? 0 : s[b] }
        if b < 0 { return ret ? s[a] : 0 }
        return d[a][b]
    }

    /// 2-opt：把一段路线倒过来走，能缩短就倒。只算两头变化的边，不重算整条路线
    @discardableResult
    static func twoOptPass(_ order: inout [Int], _ d: [[Double]], _ s: [Double], _ ret: Bool) -> Bool {
        let n = order.count
        guard n >= 3 else { return false }
        var any = false
        var improved = true
        while improved {
            improved = false
            for i in 0..<(n - 1) {
                let p = i == 0 ? -1 : order[i - 1]
                let a = order[i]
                let removedP = edge(p, a, d, s, ret)
                for k in (i + 1)..<n {
                    let b = order[k]
                    let q = k == n - 1 ? -1 : order[k + 1]
                    let delta = edge(p, b, d, s, ret) + edge(a, q, d, s, ret) - removedP - edge(b, q, d, s, ret)
                    if delta < -1e-7 {
                        order[i...k].reverse()
                        improved = true
                        any = true
                        break
                    }
                }
            }
        }
        return any
    }

    /// Or-opt：把 1–3 个连续地点挪到别处（也试倒序放），能缩短就挪。同样只算变化的边
    @discardableResult
    static func orOptPass(_ order: inout [Int], _ d: [[Double]], _ s: [Double], _ ret: Bool) -> Bool {
        let n = order.count
        guard n >= 3 else { return false }
        var any = false
        var improved = true
        while improved {
            improved = false
            outer: for len in 1...3 where len < n {
                for i in 0...(n - len) {
                    let p = i == 0 ? -1 : order[i - 1]
                    let a = order[i], b = order[i + len - 1]
                    let q = i + len == n ? -1 : order[i + len]
                    let gain = edge(p, a, d, s, ret) + edge(b, q, d, s, ret) - edge(p, q, d, s, ret)
                    // 插到原来的 order[g-1] 和 order[g] 之间（g = 0 是最前面，g = n 是最后面）
                    for g in 0...n where g < i || g > i + len {
                        let u = g == 0 ? -1 : order[g - 1]
                        let v = g == n ? -1 : order[g]
                        let base = edge(u, v, d, s, ret)
                        let forward = edge(u, a, d, s, ret) + edge(b, v, d, s, ret) - base
                        let backward = edge(u, b, d, s, ret) + edge(a, v, d, s, ret) - base
                        let add = min(forward, backward)
                        if add - gain < -1e-7 {
                            var seg = Array(order[i..<(i + len)])
                            if backward < forward { seg.reverse() }
                            order.removeSubrange(i..<(i + len))
                            order.insert(contentsOf: seg, at: g < i ? g : g - len)
                            improved = true
                            any = true
                            break outer
                        }
                    }
                }
            }
        }
        return any
    }

    static func nearestNeighbor(_ d: [[Double]], _ s: [Double], first: Int? = nil) -> [Int] {
        let n = d.count
        var visited = [Bool](repeating: false, count: n)
        var current = first ?? s.indices.min(by: { s[$0] < s[$1] })!
        var order = [current]
        order.reserveCapacity(n)
        visited[current] = true
        while order.count < n {
            var next = -1
            var bestD = Double.infinity
            for j in 0..<n where !visited[j] && d[current][j] < bestD {
                bestD = d[current][j]
                next = j
            }
            order.append(next)
            visited[next] = true
            current = next
        }
        return order
    }
}
