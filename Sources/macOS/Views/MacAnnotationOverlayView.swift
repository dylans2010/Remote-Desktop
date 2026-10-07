import SwiftUI

/// Non-destructive canvas overlay rendering normalized drawing annotations over remote video.
public struct MacAnnotationOverlayView: View {
    @Binding var currentTool: AnnotationTool
    @Binding var strokes: [AnnotationStroke]
    @Binding var selectedColorHex: String
    var isEnabled: Bool
    var onAction: (AnnotationStroke?, AnnotationAction, NormalizedPoint?) -> Void

    @State private var activePoints: [NormalizedPoint] = []
    @State private var activeStrokeId: UUID = UUID()

    public init(
        currentTool: Binding<AnnotationTool>,
        strokes: Binding<[AnnotationStroke]>,
        selectedColorHex: Binding<String>,
        isEnabled: Bool,
        onAction: @escaping (AnnotationStroke?, AnnotationAction, NormalizedPoint?) -> Void
    ) {
        self._currentTool = currentTool
        self._strokes = strokes
        self._selectedColorHex = selectedColorHex
        self.isEnabled = isEnabled
        self.onAction = onAction
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Render completed strokes
                Canvas { context, size in
                    for stroke in strokes {
                        drawStroke(stroke, in: &context, size: size)
                    }
                    if !activePoints.isEmpty {
                        let activeStroke = AnnotationStroke(
                            id: activeStrokeId,
                            tool: currentTool,
                            colorHex: selectedColorHex,
                            lineWidth: currentTool == .highlighter ? 12.0 : 4.0,
                            points: activePoints
                        )
                        drawStroke(activeStroke, in: &context, size: size)
                    }
                }
                .allowsHitTesting(false)

                // Touch / Drag capture layer when annotation mode is enabled
                if isEnabled {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let normX = value.location.x / geometry.size.width
                                    let normY = value.location.y / geometry.size.height
                                    let normPoint = NormalizedPoint(x: normX, y: normY)

                                    if activePoints.isEmpty {
                                        activeStrokeId = UUID()
                                        activePoints = [normPoint]
                                        let stroke = AnnotationStroke(
                                            id: activeStrokeId,
                                            tool: currentTool,
                                            colorHex: selectedColorHex,
                                            lineWidth: currentTool == .highlighter ? 12.0 : 4.0,
                                            points: [normPoint]
                                        )
                                        onAction(stroke, .begin, normPoint)
                                    } else {
                                        activePoints.append(normPoint)
                                        onAction(nil, .point, normPoint)
                                    }
                                }
                                .onEnded { value in
                                    guard !activePoints.isEmpty else { return }
                                    let stroke = AnnotationStroke(
                                        id: activeStrokeId,
                                        tool: currentTool,
                                        colorHex: selectedColorHex,
                                        lineWidth: currentTool == .highlighter ? 12.0 : 4.0,
                                        points: activePoints
                                    )
                                    strokes.append(stroke)
                                    onAction(stroke, .end, nil)
                                    activePoints = []
                                }
                        )
                }
            }
        }
    }

    private func drawStroke(_ stroke: AnnotationStroke, in context: inout GraphicsContext, size: CGSize) {
        guard !stroke.points.isEmpty else { return }

        let color = Color(hex: stroke.colorHex) ?? .red

        switch stroke.tool {
        case .freehand, .highlighter:
            var path = Path()
            let first = stroke.points[0].denormalized(width: size.width, height: size.height)
            path.move(to: first)

            for point in stroke.points.dropFirst() {
                let denorm = point.denormalized(width: size.width, height: size.height)
                path.addLine(to: denorm)
            }

            let opacity = stroke.tool == .highlighter ? 0.45 : 1.0
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .arrow:
            guard stroke.points.count >= 2 else { return }
            let start = stroke.points.first!.denormalized(width: size.width, height: size.height)
            let end = stroke.points.last!.denormalized(width: size.width, height: size.height)

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round))

            // Arrowhead
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 16.0
            let arrowAngle: CGFloat = .pi / 6

            var arrowPath = Path()
            let p1 = CGPoint(x: end.x - arrowLength * cos(angle - arrowAngle), y: end.y - arrowLength * sin(angle - arrowAngle))
            let p2 = CGPoint(x: end.x - arrowLength * cos(angle + arrowAngle), y: end.y - arrowLength * sin(angle + arrowAngle))

            arrowPath.move(to: end)
            arrowPath.addLine(to: p1)
            arrowPath.move(to: end)
            arrowPath.addLine(to: p2)
            context.stroke(arrowPath, with: .color(color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round))

        case .pointer:
            if let last = stroke.points.last {
                let pos = last.denormalized(width: size.width, height: size.height)
                let rect = CGRect(x: pos.x - 12, y: pos.y - 12, width: 24, height: 24)
                context.fill(Circle().path(in: rect), with: .color(color.opacity(0.85)))
                context.stroke(Circle().path(in: rect.insetBy(dx: -4, dy: -4)), with: .color(color.opacity(0.4)), lineWidth: 2)
            }
        }
    }
}

// Color hex parser extension
extension Color {
    init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }

        guard cleanHex.count == 6, let intVal = UInt64(cleanHex, radix: 16) else { return nil }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
