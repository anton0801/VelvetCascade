import XCTest
@testable import VelvetDomain

final class GeometryTests: XCTestCase {
    func testFourRotationsAreIdentity() {
        for n in [6, 7, 8] {
            for y in 0..<n {
                for x in 0..<n {
                    let c = Coord(x, y)
                    XCTAssertEqual(BoardTransform.toScreen(c, q: 4, n: n), c)
                    var r = c
                    for _ in 0..<4 { r = BoardTransform.rotateOnce(r, n: n) }
                    XCTAssertEqual(r, c)
                    for q in 0..<4 {
                        XCTAssertEqual(BoardTransform.toLocal(BoardTransform.toScreen(c, q: q, n: n), q: q, n: n), c)
                    }
                }
            }
        }
    }

    func testRotationFormula() {
        // R(x, y) = (N−1−y, x): левый верхний угол уходит в правый верхний.
        XCTAssertEqual(BoardTransform.rotateOnce(Coord(0, 0), n: 6), Coord(5, 0))
        XCTAssertEqual(BoardTransform.rotateOnce(Coord(5, 0), n: 6), Coord(5, 5))
        XCTAssertEqual(BoardTransform.rotateOnce(Coord(2, 3), n: 8), Coord(4, 2))
    }

    func testGravitySequence() {
        XCTAssertEqual((0..<4).map { Direction.gravity(forOrientation: $0) }, [.down, .right, .up, .left])
        XCTAssertEqual(Direction.gravity(forOrientation: 4), .down)
    }

    func testScreenDownMapsToLocalGravity() {
        // Экранная гравитация всегда вниз; локальная — Down/Right/Up/Left.
        for q in 0..<4 {
            XCTAssertEqual(BoardTransform.localDirection(fromScreen: .down, q: q), Direction.gravity(forOrientation: q))
            XCTAssertEqual(BoardTransform.screenDirection(fromLocal: Direction.gravity(forOrientation: q), q: q), .down)
        }
    }

    func testDirectionTransformMatchesCoordinateTransform() {
        // Вектор направления поворачивается так же, как координаты (renderer и hit testing согласованы).
        let n = 8
        let base = Coord(3, 4)
        for q in 0..<4 {
            for d in Direction.allCases {
                let a = BoardTransform.toScreen(base, q: q, n: n)
                let b = BoardTransform.toScreen(base.offset(d), q: q, n: n)
                let sd = BoardTransform.screenDirection(fromLocal: d, q: q)
                XCTAssertEqual(Coord(b.x - a.x, b.y - a.y), Coord(sd.vector.dx, sd.vector.dy), "q=\(q) d=\(d)")
                XCTAssertEqual(BoardTransform.localDirection(fromScreen: sd, q: q), d)
            }
        }
    }

    func testSweepFrontierIsScreenBottomRowOnSquare() {
        let s = TB.state(Array(repeating: "HDCBSH", count: 6))
        for q in 0..<4 {
            let g = Direction.gravity(forOrientation: q)
            let frontier = s.board.sweepFrontier(along: g).map { s.board.coord($0) }
            XCTAssertEqual(frontier.count, 6)
            for c in frontier {
                XCTAssertEqual(BoardTransform.toScreen(c, q: q, n: 6).y, 5, "q=\(q) \(c)")
            }
        }
    }

    func testShapesMasks() {
        func count(_ s: String) -> Int {
            ShapeCatalog.maskRows(shape: s).reduce(0) { $0 + $1.filter { $0 == "1" }.count }
        }
        XCTAssertEqual(count("S6"), 36)
        XCTAssertEqual(count("S8"), 64)
        XCTAssertEqual(count("C7"), 49 - 8)
        XCTAssertEqual(count("C8"), 64 - 8)
        XCTAssertEqual(count("X7"), 49 - 16)
        XCTAssertEqual(count("D7"), 49 - 12)  // |x−3|+|y−3| ≤ 4 срезает по 3 клетки в каждом углу
        XCTAssertEqual(count("U8"), 64 - 20)  // x∈2…5, y∈0…4 — пусто
        XCTAssertEqual(count("T8"), 64 - 12)  // x∈3…4, y∉3…4
        XCTAssertEqual(count("R8"), 60)
        XCTAssertFalse(ShapeCatalog.contains(shape: "R8", Coord(3, 3)))
        XCTAssertTrue(ShapeCatalog.contains(shape: "T8", Coord(3, 3)))
        XCTAssertFalse(ShapeCatalog.contains(shape: "T8", Coord(3, 0)))
    }
}
