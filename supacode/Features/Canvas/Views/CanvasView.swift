import AppKit
import SwiftUI

struct CanvasView: View {
  let terminalManager: WorktreeTerminalManager
  @State private var layoutStore = CanvasLayoutStore()

  @State private var canvasOffset: CGSize = .zero
  @State private var lastCanvasOffset: CGSize = .zero
  @State private var canvasScale: CGFloat = 1.0
  @State private var lastCanvasScale: CGFloat = 1.0
  @State private var focusedTabID: TerminalTabID?
  @State private var activeResize: [TerminalTabID: ActiveResize] = [:]

  private let minCardWidth: CGFloat = 300
  private let minCardHeight: CGFloat = 200
  private let maxCardWidth: CGFloat = 1200
  private let maxCardHeight: CGFloat = 900
  private let titleBarHeight: CGFloat = 28

  var body: some View {
    CanvasScrollContainer(offset: $canvasOffset, lastOffset: $lastCanvasOffset) {
      GeometryReader { geometry in
        let activeStates = terminalManager.activeWorktreeStates

        // Background layer: handles canvas pan and tap-to-unfocus.
        Color.clear
          .contentShape(.rect)
          .accessibilityAddTraits(.isButton)
          .onTapGesture { unfocusAll() }
          .gesture(canvasPanGesture)

        // Cards layer: one card per open tab across all worktrees.
        // Uses .offset() (not .position()) to avoid parent size proposals
        // reaching the NSView, keeping terminal grid stable during zoom.
        ForEach(activeStates, id: \.worktreeID) { state in
          ForEach(state.tabManager.tabs) { tab in
            if let surfaceView = state.surfaceView(for: tab.id) {
              let cardKey = tab.id.rawValue.uuidString
              let baseLayout = resolvedLayout(for: cardKey, canvasSize: geometry.size)
              let resized = resizedFrame(for: tab.id, baseLayout: baseLayout)
              let screenCenter = screenPosition(for: resized.center)
              let cardTotalHeight = resized.size.height + titleBarHeight

              CanvasCardView(
                repositoryName: Repository.name(for: state.repositoryRootURL),
                worktreeName: tab.title,
                surfaceView: surfaceView,
                isFocused: focusedTabID == tab.id,
                hasUnseenNotification: state.hasUnseenNotification,
                cardSize: resized.size,
                canvasScale: canvasScale,
                onTap: { focusCard(tab.id, surfaceView: surfaceView, states: activeStates) },
                onDragCommit: { translation in commitDrag(for: cardKey, translation: translation) },
                onResize: { edge, translation in
                  activeResize[tab.id] = ActiveResize(
                    edge: edge,
                    translation: CGSize(
                      width: translation.width / canvasScale,
                      height: translation.height / canvasScale
                    )
                  )
                },
                onResizeEnd: { commitResize(for: tab.id, cardKey: cardKey, surfaceView: surfaceView) }
              )
              .scaleEffect(canvasScale, anchor: .center)
              .offset(
                x: screenCenter.x - resized.size.width / 2,
                y: screenCenter.y - cardTotalHeight / 2
              )
              .zIndex(focusedTabID == tab.id ? 1 : 0)
            }
          }
        }
      }
      .contentShape(.rect)
      .simultaneousGesture(canvasZoomGesture)
    }
    .task { activateCanvas() }
    .onDisappear { deactivateCanvas() }
  }

  // MARK: - Canvas Gestures

  private var canvasPanGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        canvasOffset = CGSize(
          width: lastCanvasOffset.width + value.translation.width,
          height: lastCanvasOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        lastCanvasOffset = canvasOffset
      }
  }

  private var canvasZoomGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let newScale = max(0.25, min(2.0, lastCanvasScale * value.magnification))
        let anchor = value.startLocation

        // Keep the canvas point under the pinch center fixed:
        // screenPos = canvasPoint * scale + offset
        // → canvasPoint = (anchor - lastOffset) / lastScale
        // → newOffset  = anchor - canvasPoint * newScale
        let canvasX = (anchor.x - lastCanvasOffset.width) / lastCanvasScale
        let canvasY = (anchor.y - lastCanvasOffset.height) / lastCanvasScale

        canvasOffset = CGSize(
          width: anchor.x - canvasX * newScale,
          height: anchor.y - canvasY * newScale
        )
        canvasScale = newScale
      }
      .onEnded { _ in
        lastCanvasScale = canvasScale
        lastCanvasOffset = canvasOffset
      }
  }

  // MARK: - Layout

  private func resolvedLayout(for cardKey: String, canvasSize: CGSize) -> CanvasCardLayout {
    if let existing = layoutStore.cardLayouts[cardKey] {
      return existing
    }
    let position = autoPosition(canvasSize: canvasSize)
    let layout = CanvasCardLayout(position: position)
    layoutStore.cardLayouts[cardKey] = layout
    return layout
  }

  private func autoPosition(canvasSize: CGSize) -> CGPoint {
    let existingCount = layoutStore.cardLayouts.count
    let cardW = CanvasCardLayout.defaultSize.width
    let cardH = CanvasCardLayout.defaultSize.height + titleBarHeight
    let spacing: CGFloat = 20
    let columns = max(1, Int(canvasSize.width / (cardW + spacing)))
    let row = existingCount / columns
    let col = existingCount % columns
    return CGPoint(
      x: spacing + (cardW + spacing) * CGFloat(col) + cardW / 2,
      y: spacing + (cardH + spacing) * CGFloat(row) + cardH / 2
    )
  }

  /// Compute effective center and size accounting for resize only (not drag).
  /// Drag is applied separately via `.offset()` to avoid layout passes.
  private func resizedFrame(
    for tabID: TerminalTabID,
    baseLayout: CanvasCardLayout
  ) -> (center: CGPoint, size: CGSize) {
    var centerX = baseLayout.position.x
    var centerY = baseLayout.position.y
    var width = baseLayout.size.width
    var height = baseLayout.size.height

    if let resize = activeResize[tabID] {
      let translationX = resize.translation.width
      let translationY = resize.translation.height

      switch resize.edge {
      case .trailing:
        let newW = clampWidth(width + translationX)
        centerX += (newW - width) / 2
        width = newW

      case .leading:
        let newW = clampWidth(width - translationX)
        centerX -= (newW - width) / 2
        width = newW

      case .bottom:
        let newH = clampHeight(height + translationY)
        centerY += (newH - height) / 2
        height = newH

      case .bottomTrailing:
        let newW = clampWidth(width + translationX)
        let newH = clampHeight(height + translationY)
        centerX += (newW - width) / 2
        centerY += (newH - height) / 2
        width = newW
        height = newH

      case .bottomLeading:
        let newW = clampWidth(width - translationX)
        let newH = clampHeight(height + translationY)
        centerX -= (newW - width) / 2
        centerY += (newH - height) / 2
        width = newW
        height = newH
      }
    }

    return (CGPoint(x: centerX, y: centerY), CGSize(width: width, height: height))
  }

  private func screenPosition(for canvasCenter: CGPoint) -> CGPoint {
    CGPoint(
      x: canvasCenter.x * canvasScale + canvasOffset.width,
      y: canvasCenter.y * canvasScale + canvasOffset.height
    )
  }

  private func clampWidth(_ width: CGFloat) -> CGFloat {
    max(minCardWidth, min(maxCardWidth, width))
  }

  private func clampHeight(_ height: CGFloat) -> CGFloat {
    max(minCardHeight, min(maxCardHeight, height))
  }

  // MARK: - Drag

  private func commitDrag(for cardKey: String, translation: CGSize) {
    if var layout = layoutStore.cardLayouts[cardKey] {
      layout.position.x += translation.width
      layout.position.y += translation.height
      layoutStore.cardLayouts[cardKey] = layout
    }
  }

  // MARK: - Resize

  private func commitResize(for tabID: TerminalTabID, cardKey: String, surfaceView: GhosttySurfaceView) {
    guard activeResize[tabID] != nil else { return }
    if var layout = layoutStore.cardLayouts[cardKey] {
      let resized = resizedFrame(for: tabID, baseLayout: layout)
      layout.position = resized.center
      layout.size = resized.size
      layoutStore.cardLayouts[cardKey] = layout
    }
    activeResize[tabID] = nil
    surfaceView.needsLayout = true
    surfaceView.needsDisplay = true
  }

  // MARK: - Focus

  private func focusCard(
    _ tabID: TerminalTabID,
    surfaceView: GhosttySurfaceView,
    states: [WorktreeTerminalState]
  ) {
    let previousTabID = focusedTabID
    focusedTabID = tabID

    if let previousTabID, previousTabID != tabID {
      for state in states {
        if let previousSurface = state.surfaceView(for: previousTabID) {
          previousSurface.focusDidChange(false)
          break
        }
      }
    }

    surfaceView.focusDidChange(true)
    surfaceView.requestFocus()
  }

  private func unfocusAll() {
    guard let previousTabID = focusedTabID else { return }
    focusedTabID = nil
    for state in terminalManager.activeWorktreeStates {
      if let surface = state.surfaceView(for: previousTabID) {
        surface.focusDidChange(false)
        break
      }
    }
  }

  // MARK: - Occlusion

  private func activateCanvas() {
    for state in terminalManager.activeWorktreeStates {
      state.setAllSurfacesOccluded()
    }
    for state in terminalManager.activeWorktreeStates {
      for tab in state.tabManager.tabs {
        state.surfaceView(for: tab.id)?.setOcclusion(true)
      }
    }
  }

  private func deactivateCanvas() {
    focusedTabID = nil
    for state in terminalManager.activeWorktreeStates {
      for tab in state.tabManager.tabs {
        if let surface = state.surfaceView(for: tab.id) {
          surface.setOcclusion(false)
          surface.focusDidChange(false)
        }
      }
    }
  }
}

private struct ActiveResize {
  let edge: CanvasCardView.CardResizeEdge
  var translation: CGSize
}

// MARK: - Scroll Container

/// Wraps SwiftUI content in an NSView whose `scrollWheel` override catches
/// unhandled scroll-wheel events and translates them into canvas-offset changes.
/// Focused terminals consume their own scroll events (they don't call super),
/// so only events over empty space or unfocused cards reach this container.
private struct CanvasScrollContainer<Content: View>: NSViewRepresentable {
  @Binding var offset: CGSize
  @Binding var lastOffset: CGSize
  @ViewBuilder var content: Content

  func makeCoordinator() -> CanvasScrollCoordinator {
    CanvasScrollCoordinator()
  }

  func makeNSView(context: Context) -> CanvasScrollContainerView {
    let container = CanvasScrollContainerView()
    let hosting = NSHostingView(rootView: content)
    hosting.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.topAnchor.constraint(equalTo: container.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    container.scrollCoordinator = context.coordinator
    return container
  }

  func updateNSView(_ nsView: CanvasScrollContainerView, context: Context) {
    context.coordinator.offset = $offset
    context.coordinator.lastOffset = $lastOffset
    if let hosting = nsView.subviews.first as? NSHostingView<Content> {
      hosting.rootView = content
    }
  }
}

private class CanvasScrollCoordinator {
  var offset: Binding<CGSize> = .constant(.zero)
  var lastOffset: Binding<CGSize> = .constant(.zero)

  func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
    let current = offset.wrappedValue
    let newOffset = CGSize(
      width: current.width + deltaX,
      height: current.height + deltaY
    )
    offset.wrappedValue = newOffset
    lastOffset.wrappedValue = newOffset
  }
}

private class CanvasScrollContainerView: NSView {
  var scrollCoordinator: CanvasScrollCoordinator?

  override func scrollWheel(with event: NSEvent) {
    scrollCoordinator?.handleScroll(
      deltaX: event.scrollingDeltaX,
      deltaY: event.scrollingDeltaY
    )
  }
}
