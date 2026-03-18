import CoreGraphics
import Testing

@testable import supacode

struct CanvasCardPackerTests {
  private let packer = CanvasCardPacker(spacing: 20, titleBarHeight: 28)

  private func card(_ key: String, width: CGFloat = 800, height: CGFloat = 550) -> CanvasCardPacker.CardInfo {
    CanvasCardPacker.CardInfo(key: key, size: CGSize(width: width, height: height))
  }

  // MARK: - Basic packing

  @Test func singleCardPacks() throws {
    let result = packer.pack(cards: [card("a")], targetRatio: 16.0 / 9.0)

    let layout = try #require(result.layouts["a"])
    #expect(layout.size == CGSize(width: 800, height: 550))
    #expect(result.boundingSize.width > 0)
    #expect(result.boundingSize.height > 0)
  }

  @Test func preservesOriginalCardSizes() {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 800, height: 300),
    ]
    let result = packer.pack(cards: cards, targetRatio: 1.5)

    #expect(result.layouts["a"]?.size == CGSize(width: 600, height: 400))
    #expect(result.layouts["b"]?.size == CGSize(width: 800, height: 300))
  }

  @Test func allCardsArePlaced() {
    let cards = (0..<5).map { card("card\($0)") }
    let result = packer.pack(cards: cards, targetRatio: 16.0 / 9.0)
    #expect(result.layouts.count == 5)
  }

  // MARK: - Scale maximization

  @Test func threeEqualCardsFormOnePlusTwoOnWidescreen() throws {
    // 3 equal default-size cards on 16:9 viewport.
    // [1][2] gives scale 0.000822, beats single-column (0.000551) and single-row (0.000717).
    let cards = (0..<3).map { card("card\($0)") }
    let result = packer.pack(cards: cards, targetRatio: 16.0 / 9.0)

    let c0 = try #require(result.layouts["card0"])
    let c1 = try #require(result.layouts["card1"])
    let c2 = try #require(result.layouts["card2"])

    // Row 1: card0 alone
    // Row 2: card1, card2 side by side
    #expect(c0.position.y < c1.position.y)
    #expect(c1.position.y == c2.position.y)
  }

  @Test func wideCardAloneWhenItMaximizesScale() throws {
    // With these sizes on a 1.5 ratio viewport, [wide][n1+n2] gives higher
    // scale than other configs because the bounding box fits better.
    let cards = [
      card("wide", width: 800, height: 400),
      card("narrow1", width: 700, height: 400),
      card("narrow2", width: 700, height: 400),
    ]
    let result = packer.pack(cards: cards, targetRatio: 1.5)

    let wide = try #require(result.layouts["wide"])
    let narrow1 = try #require(result.layouts["narrow1"])
    let narrow2 = try #require(result.layouts["narrow2"])

    let wideBottom = wide.position.y + (wide.size.height + 28) / 2
    let narrow1Top = narrow1.position.y - (narrow1.size.height + 28) / 2
    #expect(narrow1Top >= wideBottom)
    #expect(narrow1.position.y == narrow2.position.y)
  }

  @Test func uniformCardsFormGrid() throws {
    // 4 equal cards with square target → should form 2×2 grid.
    let cards = (0..<4).map { card("card\($0)", width: 400, height: 400) }
    let result = packer.pack(cards: cards, targetRatio: 1.0)

    let c0 = try #require(result.layouts["card0"])
    let c1 = try #require(result.layouts["card1"])
    let c2 = try #require(result.layouts["card2"])
    let c3 = try #require(result.layouts["card3"])

    // Row 1: card0, card1; Row 2: card2, card3
    #expect(c0.position.y == c1.position.y)
    #expect(c2.position.y == c3.position.y)
    #expect(c0.position.y < c2.position.y)
    #expect(c0.position.x == c2.position.x)
  }

  // MARK: - No overlap

  @Test func cardsDoNotOverlap() {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 800, height: 300),
      card("c", width: 500, height: 500),
      card("d", width: 700, height: 350),
    ]
    let result = packer.pack(cards: cards, targetRatio: 1.5)

    let rects = result.layouts.map { (_, layout) -> CGRect in
      CGRect(
        x: layout.position.x - layout.size.width / 2,
        y: layout.position.y - (layout.size.height + 28) / 2,
        width: layout.size.width,
        height: layout.size.height + 28
      )
    }

    for i in 0..<rects.count {
      for j in (i + 1)..<rects.count {
        let insetA = rects[i].insetBy(dx: 1, dy: 1)
        let insetB = rects[j].insetBy(dx: 1, dy: 1)
        #expect(!insetA.intersects(insetB), "Cards \(i) and \(j) overlap")
      }
    }
  }

  // MARK: - Row centering

  @Test func shorterRowIsCenteredWithinBoundingWidth() throws {
    let cards = [
      card("wide", width: 1000, height: 400),
      card("narrow", width: 400, height: 400),
    ]
    let result = packer.pack(cards: cards, targetRatio: 0.8)

    let wide = try #require(result.layouts["wide"])
    let narrow = try #require(result.layouts["narrow"])

    let boundingCenterX = result.boundingSize.width / 2
    #expect(abs(narrow.position.x - boundingCenterX) < 1)
    #expect(abs(wide.position.x - boundingCenterX) < 1)
  }

  // MARK: - Edge cases

  @Test func emptyCardsReturnsEmptyResult() {
    let result = packer.pack(cards: [], targetRatio: 1.5)
    #expect(result.layouts.isEmpty)
    #expect(result.boundingSize == .zero)
  }

  // MARK: - Spacing

  @Test func cardsOnSameRowHaveMinimumSpacing() throws {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 600, height: 400),
    ]
    // Wide target → both cards on the same row.
    let result = packer.pack(cards: cards, targetRatio: 3.0)

    let a = try #require(result.layouts["a"])
    let b = try #require(result.layouts["b"])

    #expect(a.position.y == b.position.y)
    let aRight = a.position.x + a.size.width / 2
    let bLeft = b.position.x - b.size.width / 2
    #expect(bLeft - aRight >= 20 - 1, "Horizontal gap too small: \(bLeft - aRight)")
  }

  @Test func rowsHaveMinimumSpacing() throws {
    let cards = [
      card("a", width: 800, height: 400),
      card("b", width: 800, height: 400),
    ]
    // Narrow target → each card on its own row.
    let result = packer.pack(cards: cards, targetRatio: 0.5)

    let a = try #require(result.layouts["a"])
    let b = try #require(result.layouts["b"])

    let aBottom = a.position.y + (a.size.height + 28) / 2
    let bTop = b.position.y - (b.size.height + 28) / 2
    #expect(bTop - aBottom >= 20 - 1, "Vertical gap too small: \(bTop - aBottom)")
  }
}
