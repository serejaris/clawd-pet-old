import AppKit
import Foundation

public protocol StatusBubbleDelegate: AnyObject {
    func statusDidChange(token: String, message: String)
}

public final class StatusBubble {
    public weak var delegate: StatusBubbleDelegate?

    public private(set) var currentToken: String?
    public private(set) var currentMessage: String?
    public private(set) var isVisible: Bool = false
    public private(set) var alpha: CGFloat = 0.0

    private var targetAlpha: CGFloat = 0.0
    private var lastFileModDate: Date?
    private var lastTokenTime: Date?
    private var checkTimer: Timer?

    private let primaryPath = "/tmp/clawd-status.txt"
    private let fallbackPath = NSString(string: "~/.clawd-status.txt").expandingTildeInPath

    public var bubbleBounds: CGRect = .zero

    public init() {
        startMonitoring()
    }

    deinit {
        checkTimer?.invalidate()
    }

    public func startMonitoring() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkStatusFile()
        }
        RunLoop.main.add(checkTimer!, forMode: .common)
        checkStatusFile()
    }

    public func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
        targetAlpha = 0.0
    }

    public func update(deltaTime: TimeInterval) {
        // Smooth alpha transition
        let speed: CGFloat = 8.0 * CGFloat(deltaTime)
        if alpha < targetAlpha {
            alpha = min(targetAlpha, alpha + speed)
        } else if alpha > targetAlpha {
            alpha = max(targetAlpha, alpha - speed)
        }

        isVisible = alpha > 0.01

        // Auto-dismiss if no activity for 20 seconds
        if let last = lastTokenTime, Date().timeIntervalSince(last) > 20.0 {
            if currentToken == "done" || targetAlpha > 0 {
                targetAlpha = 0.0
            }
        }
    }

    private func checkStatusFile() {
        let fileManager = FileManager.default
        let pathToCheck: String
        if fileManager.fileExists(atPath: primaryPath) {
            pathToCheck = primaryPath
        } else if fileManager.fileExists(atPath: fallbackPath) {
            pathToCheck = fallbackPath
        } else {
            return
        }

        guard let attrs = try? fileManager.attributesOfItem(atPath: pathToCheck),
              let modDate = attrs[.modificationDate] as? Date else {
            return
        }

        if let last = lastFileModDate, modDate <= last {
            return
        }
        lastFileModDate = modDate

        guard let content = try? String(contentsOfFile: pathToCheck, encoding: .utf8) else {
            return
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            targetAlpha = 0.0
            return
        }

        setToken(trimmed)
    }

    public func setToken(_ token: String) {
        currentToken = token
        lastTokenTime = Date()

        let msg: String
        switch token.lowercased() {
        case "think":
            msg = "thinking…"
        case "bash":
            msg = "running command…"
        case "edit":
            msg = "writing code…"
        case "read":
            msg = "reading files…"
        case "web":
            msg = "searching web…"
        case "task":
            msg = "subagent task…"
        case "notify":
            msg = "needs your input!"
        case "done":
            msg = "done ✓"
        default:
            msg = token
        }

        currentMessage = msg
        targetAlpha = 1.0

        delegate?.statusDidChange(token: token, message: msg)

        // If done, schedule fade-out after 6 seconds
        if token.lowercased() == "done" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                if self?.currentToken?.lowercased() == "done" {
                    self?.targetAlpha = 0.0
                }
            }
        }
    }

    public func draw(in context: CGContext, anchor: CGPoint) {
        guard isVisible, let message = currentMessage, !message.isEmpty else { return }

        context.saveGState()
        context.setAlpha(alpha)

        // Typography styling
        let font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textColor = NSColor(deviceRed: 0.96, green: 0.94, blue: 0.90, alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let attrString = NSAttributedString(string: message, attributes: attrs)
        let textSize = attrString.size()

        let paddingH: CGFloat = 14.0
        let paddingV: CGFloat = 8.0
        let arrowH: CGFloat = 7.0
        let arrowW: CGFloat = 12.0
        let cornerRadius: CGFloat = 10.0

        let bubbleW = max(70.0, textSize.width + paddingH * 2)
        let bubbleH = textSize.height + paddingV * 2

        // Bubble body positioned above the arrow
        let bubbleX = anchor.x - bubbleW / 2.0
        let bubbleY = anchor.y + arrowH
        let bubbleRect = CGRect(x: bubbleX, y: bubbleY, width: bubbleW, height: bubbleH)
        self.bubbleBounds = CGRect(x: bubbleX, y: anchor.y, width: bubbleW, height: bubbleH + arrowH)

        // Build path: rounded rectangle + downward pointer arrow
        let path = CGMutablePath()
        let minX = bubbleRect.minX
        let maxX = bubbleRect.maxX
        let minY = bubbleRect.minY
        let maxY = bubbleRect.maxY
        let midX = anchor.x

        // Top-left corner
        path.move(to: CGPoint(x: minX + cornerRadius, y: maxY))
        path.addLine(to: CGPoint(x: maxX - cornerRadius, y: maxY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX, y: maxY - cornerRadius), radius: cornerRadius)

        // Right edge and bottom-right corner
        path.addLine(to: CGPoint(x: maxX, y: minY + cornerRadius))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX - cornerRadius, y: minY), radius: cornerRadius)

        // Bottom edge with arrow pointing down
        path.addLine(to: CGPoint(x: midX + arrowW / 2.0, y: minY))
        path.addLine(to: CGPoint(x: midX, y: anchor.y))
        path.addLine(to: CGPoint(x: midX - arrowW / 2.0, y: minY))
        path.addLine(to: CGPoint(x: minX + cornerRadius, y: minY))

        // Bottom-left corner and left edge
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX, y: minY + cornerRadius), radius: cornerRadius)
        path.addLine(to: CGPoint(x: minX, y: maxY - cornerRadius))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX + cornerRadius, y: maxY), radius: cornerRadius)
        path.closeSubpath()

        // Background: stylish dark translucent charcoal
        let bgColor = NSColor(deviceRed: 0.12, green: 0.12, blue: 0.15, alpha: 0.92).cgColor
        let borderColor = NSColor(deviceWhite: 1.0, alpha: 0.20).cgColor

        // Draw shadow
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6.0, color: NSColor(deviceWhite: 0.0, alpha: 0.40).cgColor)

        context.setFillColor(bgColor)
        context.addPath(path)
        context.fillPath()

        // Draw border
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(borderColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        // Accent indicator dot for active operations
        let dotColor: NSColor
        if currentToken?.lowercased() == "done" {
            dotColor = NSColor(deviceRed: 0.30, green: 0.85, blue: 0.45, alpha: 1.0) // Green
        } else if currentToken?.lowercased() == "notify" {
            dotColor = NSColor(deviceRed: 1.0, green: 0.65, blue: 0.20, alpha: 1.0) // Amber
        } else {
            dotColor = NSColor(deviceRed: 0.85, green: 0.47, blue: 0.34, alpha: 1.0) // Claude Coral
        }

        let dotSize: CGFloat = 5.0
        let dotRect = CGRect(x: bubbleRect.minX + 11.0, y: bubbleRect.midY - dotSize / 2.0, width: dotSize, height: dotSize)
        context.setFillColor(dotColor.cgColor)
        context.fillEllipse(in: dotRect)

        // Draw text
        let textRect = CGRect(
            x: bubbleRect.minX + 20.0,
            y: bubbleRect.minY + (bubbleH - textSize.height) / 2.0 - 0.5,
            width: bubbleW - 24.0,
            height: textSize.height
        )

        // Render text via NSGraphicsContext
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        attrString.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }
}
