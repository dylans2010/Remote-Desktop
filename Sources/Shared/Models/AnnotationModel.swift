import Foundation
import CoreGraphics

/// Tool types supported for controller drawing overlays.
public enum AnnotationTool: String, Codable, Sendable, CaseIterable {
    case freehand = "Draw"
    case arrow = "Arrow"
    case pointer = "Pointer"
    case highlighter = "Highlighter"

    public var systemImageName: String {
        switch self {
        case .freehand: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .pointer: return "hand.point.up.left.fill"
        case .highlighter: return "highlighter"
        }
    }
}

/// Normalized point on the remote viewport between 0.0 and 1.0.
public struct NormalizedPoint: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = max(0.0, min(1.0, x))
        self.y = max(0.0, min(1.0, y))
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    public func denormalized(width: Double, height: Double) -> CGPoint {
        CGPoint(x: x * width, y: y * height)
    }
}

/// A complete stroke or marker annotation represented in normalized screen coordinates.
public struct AnnotationStroke: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let tool: AnnotationTool
    public let colorHex: String
    public let lineWidth: Double
    public var points: [NormalizedPoint]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool = .freehand,
        colorHex: String = "#FF3B30",
        lineWidth: Double = 4.0,
        points: [NormalizedPoint] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tool = tool
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.points = points
        self.createdAt = createdAt
    }
}

/// Action transmitted across remote session for synchronized annotation.
public enum AnnotationAction: String, Codable, Sendable {
    case begin
    case point
    case end
    case clear
    case undo
}

/// Session payload for drawing event messages.
public struct AnnotationMessagePayload: Codable, Sendable {
    public let action: AnnotationAction
    public let stroke: AnnotationStroke?
    public let point: NormalizedPoint?

    public init(action: AnnotationAction, stroke: AnnotationStroke? = nil, point: NormalizedPoint? = nil) {
        self.action = action
        self.stroke = stroke
        self.point = point
    }
}
