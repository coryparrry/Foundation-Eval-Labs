import AppKit
import SwiftUI
import Testing
#if canImport(FoundationEvalsUIComponents)
@testable import FoundationEvalsUIComponents
#endif
@testable import FoundationEvals

@MainActor
struct TimelineRenderingTests {
    @Test func longSpanRemainsSolidInsideItsOutline() throws {
        let bitmap = try render(width: 80, offset: 20, color: .red)
        let center = try #require(bitmap.colorAt(x: 60, y: 10)?.usingColorSpace(.deviceRGB))
        #expect(center.redComponent > 0.95)
        #expect(center.alphaComponent > 0.95)
        #expect(try #require(bitmap.colorAt(x: 10, y: 10)).alphaComponent == 0)
        #expect(try #require(bitmap.colorAt(x: 110, y: 10)).alphaComponent == 0)
    }

    @Test func shortAndFinalSpansStillRenderVisibleSolidBars() throws {
        for offset in [20.0, 118.0] {
            let bitmap = try render(width: 2, offset: offset, color: .blue)
            let center = try #require(bitmap.colorAt(x: Int(offset), y: 10)?.usingColorSpace(.deviceRGB))
            #expect(center.blueComponent > 0.9)
            #expect(center.alphaComponent > 0.5)
        }
    }

    @Test func parentSpanKeepsItsOriginalFillOpacity() throws {
        let bitmap = try render(width: 80, offset: 0, color: .red.opacity(0.6))
        let center = try #require(bitmap.colorAt(x: 40, y: 10)?.usingColorSpace(.deviceRGB))
        #expect(abs(center.alphaComponent - 0.6) < 0.02)
    }

    @Test func fittedSubmillisecondSpansRenderAsReadableBars() throws {
        for (start, end) in [(1.0, 1.8), (28_839.8, 28_840.0)] {
            let interval = WorkflowTimelineInterval(start: start, end: end, extent: 28_840, width: 120)
            #expect(interval.width < 1)
            #expect(interval.displayWidth == 16)
            let bitmap = try render(width: interval.displayWidth, offset: interval.displayOffset, color: .cyan)
            let center = try #require(bitmap.colorAt(x: Int(interval.displayOffset + 8), y: 10)?.usingColorSpace(.deviceRGB))
            #expect(center.greenComponent > 0.5)
            #expect(center.alphaComponent > 0.95)
        }
    }

    private func render(width: CGFloat, offset: CGFloat, color: Color) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content:
            SolidTimelineBar(width: width, offset: offset, color: color)
                .frame(width: 120, height: 20, alignment: .leading)
        )
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }
}
