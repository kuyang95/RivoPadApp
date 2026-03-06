import SwiftUI

final class OCRSpatialIndex {

    private let screenSize: CGSize
    private let cellSize: CGFloat = 80

    private let cols: Int
    private let rows: Int

    private var grid: [[Int]]

    init(screenSize: CGSize) {

        self.screenSize = screenSize

        cols = Int(ceil(screenSize.width / cellSize))
        rows = Int(ceil(screenSize.height / cellSize))

        grid = Array(repeating: [], count: cols * rows)
    }

    private func cellIndex(x: Int, y: Int) -> Int {
        y * cols + x
    }

    func insert(box rect: CGRect, index: Int) {

        let minX = Int(rect.minX / cellSize)
        let maxX = Int(rect.maxX / cellSize)

        let minY = Int(rect.minY / cellSize)
        let maxY = Int(rect.maxY / cellSize)

        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            for x in minX...maxX {

                guard x >= 0, y >= 0, x < cols, y < rows else { continue }

                grid[cellIndex(x: x, y: y)].append(index)
            }
        }
    }

    // 🔥 이게 지금 missing
    func query(point: CGPoint) -> [Int] {

        let x = Int(point.x / cellSize)
        let y = Int(point.y / cellSize)

        guard x >= 0, y >= 0, x < cols, y < rows else { return [] }

        return grid[cellIndex(x: x, y: y)]
    }
}
