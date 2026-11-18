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
        let tries = min(n, n <= 40 ? n : 12)
        let seeds = s.indices.sorted { s[$0] < s[$1] }.prefix(tries)
        var best: [Int] = []
        var bestCost = Double.infinity
        for seed in seeds {
            var order = twoOpt(nearestNeighbor(d, s, first: seed), d, s, ret)
            order = orOpt(order, d, s, ret)
            order = twoOpt(order, d, s, ret)
            let c = cost(order, d, s, ret)
            if c < bestCost { bestCost = c; best = order }
        }
        return best
    }

    /// Or-opt：把长度 1–3 的一小段挪到别的位置，能缩短就挪
    static func orOpt(_ initial: [Int], _ d: [[Double]], _ s: [Double], _ ret: Bool) -> [Int] {
        var order = initial
        var best = cost(order, d, s, ret)
        var improved = true
        while improved {
            improved = false
            for len in 1...3 where len < order.count {
                for i in 0...(order.count - len) {
                    let segment = Array(order[i..<(i + len)])
                    var rest = order
                    rest.removeSubrange(i..<(i + len))
                    for j in 0...rest.count where j != i {
                        var candidate = rest
                        candidate.insert(contentsOf: segment, at: j)
                        let c = cost(candidate, d, s, ret)
                        if c + 1e-9 < best {
                            order = candidate
                            best = c
                            improved = true
                            break
                        }
                    }
                    if improved { break }
                }
                if improved { break }
            }
        }
        return order
    }

    static func nearestNeighbor(_ d: [[Double]], _ s: [Double], first: Int? = nil) -> [Int] {
        let n = d.count
        var visited = Set<Int>()
        var current = first ?? s.indices.min(by: { s[$0] < s[$1] })!
        var order = [current]
        visited.insert(current)
        while order.count < n {
            let next = (0..<n).filter { !visited.contains($0) }.min(by: { d[current][$0] < d[current][$1] })!
            order.append(next)
            visited.insert(next)
            current = next
        }
        return order
    }

    static func twoOpt(_ initial: [Int], _ d: [[Double]], _ s: [Double], _ ret: Bool) -> [Int] {
        var order = initial
        var best = cost(order, d, s, ret)
        var improved = true
        while improved {
            improved = false
            for i in 0..<(order.count - 1) {
                for k in (i + 1)..<order.count {
                    var candidate = order
                    candidate[i...k].reverse()
                    let c = cost(candidate, d, s, ret)
                    if c + 1e-9 < best {
                        order = candidate
                        best = c
                        improved = true
                    }
                }
            }
        }
        return order
    }
}
