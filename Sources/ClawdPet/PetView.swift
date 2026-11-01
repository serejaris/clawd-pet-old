import AppKit
import Foundation

public enum PetState: String {
    case idle
    case walk
    case dangle
    case fall
    case dance
    case work
    case cook
    case jump
    case wave
}

public final class PetView: NSView, StatusBubbleDelegate {
    public var config: PetConfig

    // State machine
    public private(set) var state: PetState = .idle
    private var stateTime: TimeInterval = 0.0
    private var stateDuration: TimeInterval = 0.0

    // Dimensions
    public var crabWidth: CGFloat = 84.0
    public var crabHeight: CGFloat = 105.0
    public var crabBottomMargin: CGFloat = 60.0

    // Position in screen coordinates (origin = bottom-left of window)
    public var currentX: CGFloat = 0.0
    public var currentY: CGFloat = 0.0

    // Velocity (for fall / fling)
    public var velocityX: CGFloat = 0.0
    public var velocityY: CGFloat = 0.0

    // Walking
    public var isFacingLeft: Bool = false
    private var walkSpeed: CGFloat = 1.2

    // Blinking & Eye tracking
    private var blinkTimer: TimeInterval = 3.0
    private var isBlinking: Bool = false
    private var eyeOffsetX: CGFloat = 0.0
    private var eyeOffsetY: CGFloat = 0.0

    // Pendulum physics (dangling)
    private var anchor = CGPoint.zero
    private var ancVX: CGFloat = 0.0
    private var ancVY: CGFloat = 0.0
    private var lastAncVX: CGFloat = 0.0
    private var theta: CGFloat = 0.0
    private var omega: CGFloat = 0.0

    // Drag tracking
    private var isMouseDown: Bool = false
    private var hasDragged: Bool = false
    private var dragStartMouse = CGPoint.zero
    private var lastMousePos = CGPoint.zero
    private var cursorVelX: CGFloat = 0.0
    private var cursorVelY: CGFloat = 0.0

    // Squash & Stretch
    private var squashScaleX: CGFloat = 1.0
    private var squashScaleY: CGFloat = 1.0

    // Timers and Status Bubble
    private var displayTimer: Timer?
    public let statusBubble = StatusBubble()
    public var isClaudeWatchEnabled: Bool = true

    // Current tracking area
    private var trackingAreaRef: NSTrackingArea?

    public init(frame frameRect: NSRect, config: PetConfig) {
        self.config = config
        super.init(frame: frameRect)

        let sizeCfg = CGFloat(config.size ?? 80.0)
        self.crabWidth = max(50.0, min(160.0, sizeCfg))
        self.crabHeight = self.crabWidth * (1499.0 / 1200.0)
        self.walkSpeed = CGFloat(config.walkSpeed ?? 1.2)
        self.isClaudeWatchEnabled = config.features?.claudeWatch ?? true

        statusBubble.delegate = self
        setupTrackingArea()
        startLoop()

        // Welcome toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.statusBubble.setToken("done")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayTimer?.invalidate()
    }

    public override var isFlipped: Bool {
        return false // Native Cocoa bottom-up coordinates
    }

    private func setupTrackingArea() {
        if let old = trackingAreaRef {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingAreaRef = area
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    // MARK: - Loop & Physics

    private func startLoop() {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.displayTimer = timer
    }

    @objc private func tick() {
        let dt: TimeInterval = 1.0 / 60.0
        stateTime += dt

        statusBubble.update(deltaTime: dt)

        // Squash recovery
        if abs(squashScaleX - 1.0) > 0.005 || abs(squashScaleY - 1.0) > 0.005 {
            squashScaleX += (1.0 - squashScaleX) * 0.22
            squashScaleY += (1.0 - squashScaleY) * 0.22
        } else {
            squashScaleX = 1.0
            squashScaleY = 1.0
        }

        switch state {
        case .idle:
            tickIdle(dt: dt)
        case .walk:
            tickWalk(dt: dt)
        case .dangle:
            tickDangle(dt: dt)
        case .fall:
            tickFall(dt: dt)
        case .dance, .work, .cook, .jump, .wave:
            tickAnimation(dt: dt)
        }

        needsDisplay = true
    }

    private func tickIdle(dt: TimeInterval) {
        updateEyeTracking()

        // Blinking
        blinkTimer -= dt
        if blinkTimer <= 0 {
            if isBlinking {
                isBlinking = false
                let minSec = config.blinkSecondsMin ?? 2.5
                let maxSec = config.blinkSecondsMax ?? 5.5
                blinkTimer = Double.random(in: minSec...maxSec)
            } else {
                isBlinking = true
                blinkTimer = 0.16 // Blink duration
            }
        }

        // Random action after idle duration
        if stateTime >= stateDuration {
            let roll = Double.random(in: 0...1)
            if roll < 0.65 {
                // Start walking
                setWalking(directionLeft: Bool.random(), duration: Double.random(in: 4.0...9.0))
            } else {
                // Continue idling
                stateTime = 0
                stateDuration = Double.random(in: 4.0...8.0)
            }
        }
    }

    private func tickWalk(dt: TimeInterval) {
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        let step = walkSpeed * (isFacingLeft ? -1.0 : 1.0)
        currentX += step

        let petMargin: CGFloat = 8.0
        let leftLimit = visible.minX + petMargin
        let rightLimit = visible.maxX - bounds.width - petMargin

        if currentX <= leftLimit {
            currentX = leftLimit
            isFacingLeft = false
        } else if currentX >= rightLimit {
            currentX = rightLimit
            isFacingLeft = true
        }

        currentY = visible.minY - crabBottomMargin
        window?.setFrameOrigin(CGPoint(x: currentX, y: currentY))

        if stateTime >= stateDuration {
            setIdle(duration: Double.random(in: 4.0...9.0))
        }
    }

    private func tickDangle(dt: TimeInterval) {
        let mouse = NSEvent.mouseLocation

        // Cursor velocity
        cursorVelX = mouse.x - lastMousePos.x
        cursorVelY = mouse.y - lastMousePos.y
        lastMousePos = mouse

        // Anchor easing
        ancVX = (mouse.x - anchor.x) * 0.35
        ancVY = (mouse.y - anchor.y) * 0.35
        anchor.x += ancVX
        anchor.y += ancVY

        // Pendulum physics
        let accX = ancVX - lastAncVX
        lastAncVX = ancVX
        let stiff = 1.0 + (theta * theta * 1.6)
        let alpha = (-0.0075 * theta * stiff) - (0.03 * omega) - (0.012 * accX) - (0.0022 * ancVX)
        omega = max(-0.28, min(0.28, omega + alpha))
        theta += omega
        theta = max(-1.35, min(1.35, theta))

        // Position window so claw attaches to cursor anchor
        let clawAnchorX = bounds.midX + crabWidth * 0.40
        let clawAnchorY = crabBottomMargin + crabHeight * 0.90
        currentX = anchor.x - clawAnchorX
        currentY = anchor.y - clawAnchorY
        window?.setFrameOrigin(CGPoint(x: currentX, y: currentY))
    }

    private func tickFall(dt: TimeInterval) {
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        let grav = CGFloat(config.gravity ?? 1.0) * 0.82
        velocityY -= grav
        velocityX *= 0.995
        velocityY *= 0.995

        currentX += velocityX
        currentY += velocityY

        let leftLimit = visible.minX
        let rightLimit = visible.maxX - bounds.width
        let topLimit = visible.maxY - bounds.height
        let bottomLimit = visible.minY - crabBottomMargin

        // Bounce walls
        if currentX <= leftLimit {
            currentX = leftLimit
            velocityX = abs(velocityX) * 0.52
        } else if currentX >= rightLimit {
            currentX = rightLimit
            velocityX = -abs(velocityX) * 0.52
        }

        // Bounce ceiling
        if currentY >= topLimit {
            currentY = topLimit
            velocityY = -abs(velocityY) * 0.40
        }

        // Floor collision
        if currentY <= bottomLimit {
            currentY = bottomLimit

            if abs(velocityY) > 3.2 {
                // Bounce with restitution
                velocityY = abs(velocityY) * 0.35
                velocityX *= 0.85
                squashScaleY = 0.65
                squashScaleX = 1.25
            } else {
                // Settle on the floor
                velocityY = 0
                velocityX *= 0.85

                if abs(velocityX) < 0.8 {
                    velocityX = 0
                    squashScaleY = 0.70
                    squashScaleX = 1.20
                    window?.setFrameOrigin(CGPoint(x: currentX, y: currentY))
                    // Happy bounce after fall!
                    setAnimation(.jump, duration: 2.2)
                    return
                }
            }
        }

        window?.setFrameOrigin(CGPoint(x: currentX, y: currentY))
    }

    private func tickAnimation(dt: TimeInterval) {
        // One-shot animations return to idle after duration
        if stateTime >= stateDuration {
            setIdle(duration: Double.random(in: 4.0...8.0))
        }
    }

    private func updateEyeTracking() {
        guard config.features?.eyeTracking ?? true else {
            eyeOffsetX = 0
            eyeOffsetY = 0
            return
        }

        let mouse = NSEvent.mouseLocation
        let crabCenter = CGPoint(x: (window?.frame.minX ?? 0) + bounds.midX, y: (window?.frame.minY ?? 0) + crabBottomMargin + crabHeight / 2.0)
        let dx = mouse.x - crabCenter.x
        let dy = mouse.y - crabCenter.y

        let targetOX = max(-1.0, min(1.0, dx / 150.0)) * 22.0
        let targetOY = max(-1.0, min(1.0, dy / 150.0)) * 16.0

        eyeOffsetX += (targetOX - eyeOffsetX) * 0.22
        eyeOffsetY += (targetOY - eyeOffsetY) * 0.22
    }

    // MARK: - State Transitions

    public func setIdle(duration: TimeInterval = 6.0) {
        state = .idle
        stateTime = 0
        stateDuration = duration
        theta = 0
        omega = 0
    }

    public func setWalking(directionLeft: Bool, duration: TimeInterval = 6.0) {
        state = .walk
        stateTime = 0
        stateDuration = duration
        isFacingLeft = directionLeft
    }

    public func setAnimation(_ newState: PetState, duration: TimeInterval) {
        state = newState
        stateTime = 0
        stateDuration = duration
    }

    // MARK: - StatusBubbleDelegate

    public func statusDidChange(token: String, message: String) {
        guard isClaudeWatchEnabled else { return }

        switch token.lowercased() {
        case "done":
            setAnimation(.jump, duration: 2.5)
        case "edit", "bash":
            setAnimation(.work, duration: 8.0)
        case "notify":
            setAnimation(.wave, duration: 3.5)
        case "think", "read", "web", "task":
            if state == .idle || state == .walk {
                setAnimation(.work, duration: 5.0)
            }
        default:
            break
        }
    }

    // MARK: - Hit Testing (Click-through)

    public override func hitTest(_ point: NSPoint) -> NSView? {
        if state == .dangle {
            return self
        }
        let crabRect = CGRect(x: (bounds.width - crabWidth) / 2.0, y: crabBottomMargin, width: crabWidth, height: crabHeight)
        if crabRect.contains(point) {
            return self
        }
        if statusBubble.isVisible && statusBubble.bubbleBounds.contains(point) {
            return self
        }
        return nil
    }

    // MARK: - Mouse Events

    public override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        hasDragged = false
        dragStartMouse = NSEvent.mouseLocation
        lastMousePos = dragStartMouse

        if state == .fall {
            velocityX = 0
            velocityY = 0
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isMouseDown else { return }
        let mouse = NSEvent.mouseLocation

        let dx = abs(mouse.x - dragStartMouse.x)
        let dy = abs(mouse.y - dragStartMouse.y)

        if !hasDragged && (dx > 4.0 || dy > 4.0) {
            hasDragged = true
            state = .dangle
            stateTime = 0
            anchor = mouse
            ancVX = 0
            ancVY = 0
            lastAncVX = 0
            theta = 0
            omega = 0
        }
    }

    public override func mouseUp(with event: NSEvent) {
        guard isMouseDown else { return }
        isMouseDown = false

        if hasDragged {
            hasDragged = false
            // Fling handover
            state = .fall
            stateTime = 0
            velocityX = max(-35.0, min(35.0, cursorVelX * 0.92))
            velocityY = max(-35.0, min(35.0, cursorVelY * 0.92))
        } else {
            // Click reaction: random delightful action
            let roll = Double.random(in: 0...1)
            if roll < 0.40 {
                setAnimation(.wave, duration: 2.2)
            } else if roll < 0.75 {
                setAnimation(.jump, duration: 2.2)
            } else {
                setAnimation(.dance, duration: 3.8)
            }
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        // Show context menu
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    // MARK: - Context Menu

    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        // Status Item
        let statusTitle: String
        switch state {
        case .idle: statusTitle = "Status: Idle (Отдыхает)"
        case .walk: statusTitle = "Status: Walking (Гуляет)"
        case .dangle: statusTitle = "Status: Dangle! (Держится)"
        case .fall: statusTitle = "Status: Flying! (Летит)"
        case .dance: statusTitle = "Status: Dancing (Танцует)"
        case .work: statusTitle = "Status: Working (Работает)"
        case .cook: statusTitle = "Status: Cooking (Готовит)"
        case .jump: statusTitle = "Status: Jumping (Прыгает)"
        case .wave: statusTitle = "Status: Waving (Машет)"
        }

        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if let msg = statusBubble.currentMessage, statusBubble.isVisible {
            let bubbleItem = NSMenuItem(title: "Activity: \(msg)", action: nil, keyEquivalent: "")
            bubbleItem.isEnabled = false
            menu.addItem(bubbleItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Animations Submenu
        let animMenu = NSMenu()
        animMenu.addItem(NSMenuItem(title: "💃 Dance (Танец)", action: #selector(playDance), keyEquivalent: "d"))
        animMenu.addItem(NSMenuItem(title: "💻 Work (Работа)", action: #selector(playWork), keyEquivalent: "w"))
        animMenu.addItem(NSMenuItem(title: "🍳 Cook (Готовка)", action: #selector(playCook), keyEquivalent: "c"))
        animMenu.addItem(NSMenuItem(title: "🦘 Jump (Прыжок)", action: #selector(playJump), keyEquivalent: "j"))
        animMenu.addItem(NSMenuItem(title: "👋 Wave (Помахать)", action: #selector(playWave), keyEquivalent: ""))

        let animItem = NSMenuItem(title: "Animations (Анимации)", action: nil, keyEquivalent: "")
        animItem.submenu = animMenu
        menu.addItem(animItem)

        menu.addItem(NSMenuItem.separator())

        // Reset Position
        menu.addItem(NSMenuItem(title: "🔄 Reset Position (Сбросить позицию)", action: #selector(resetPosition), keyEquivalent: "r"))

        // Toggle Claude Watch
        let watchTitle = isClaudeWatchEnabled ? "✓ Claude Watch (Включен)" : "Claude Watch (Выключен)"
        menu.addItem(NSMenuItem(title: watchTitle, action: #selector(toggleClaudeWatch), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "❌ Quit Clawd Pet (Выход)", action: #selector(quitApp), keyEquivalent: "q"))

        return menu
    }

    @objc public func playDance() { setAnimation(.dance, duration: 4.5) }
    @objc public func playWork() { setAnimation(.work, duration: 6.0) }
    @objc public func playCook() { setAnimation(.cook, duration: 6.0) }
    @objc public func playJump() { setAnimation(.jump, duration: 2.2) }
    @objc public func playWave() { setAnimation(.wave, duration: 2.2) }

    @objc public func resetPosition() {
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        currentX = visible.midX - bounds.width / 2.0
        currentY = visible.minY - crabBottomMargin
        velocityX = 0
        velocityY = 0
        window?.setFrameOrigin(CGPoint(x: currentX, y: currentY))
        setIdle(duration: 5.0)
    }

    @objc public func toggleClaudeWatch() {
        isClaudeWatchEnabled.toggle()
        if isClaudeWatchEnabled {
            statusBubble.setToken("Claude Watch ON")
        } else {
            statusBubble.setToken("Claude Watch OFF")
        }
    }

    @objc public func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Clear transparent canvas
        context.clear(bounds)

        // Draw Status Speech Bubble above crab head
        let headAnchor = CGPoint(x: bounds.midX, y: crabBottomMargin + crabHeight + 2.0)
        statusBubble.draw(in: context, anchor: headAnchor)

        // Draw Crab
        context.saveGState()

        let crabCenterX = bounds.midX
        let crabBottomY = crabBottomMargin

        // Handle Squash & Stretch around bottom-center
        if squashScaleX != 1.0 || squashScaleY != 1.0 {
            context.translateBy(x: crabCenterX, y: crabBottomY)
            context.scaleBy(x: squashScaleX, y: squashScaleY)
            context.translateBy(x: -crabCenterX, y: -crabBottomY)
        }

        // Handle Dangling Rotation around claw pivot
        if state == .dangle {
            let clawPivot = CGPoint(x: bounds.midX + crabWidth * 0.40, y: crabBottomMargin + crabHeight * 0.90)
            context.translateBy(x: clawPivot.x, y: clawPivot.y)
            context.rotate(by: theta)
            context.translateBy(x: -clawPivot.x, y: -clawPivot.y)
        }

        // Flip horizontally if facing left
        if isFacingLeft && state == .walk {
            context.translateBy(x: bounds.midX, y: 0)
            context.scaleBy(x: -1.0, y: 1.0)
            context.translateBy(x: -bounds.midX, y: 0)
        }

        let crabRect = CGRect(x: (bounds.width - crabWidth) / 2.0, y: crabBottomMargin, width: crabWidth, height: crabHeight)

        switch state {
        case .idle:
            drawIdle(in: context, rect: crabRect)
        case .walk:
            drawWalk(in: context, rect: crabRect)
        case .dangle:
            drawDangle(in: context, rect: crabRect)
        case .fall:
            drawFall(in: context, rect: crabRect)
        case .dance:
            drawAnimated(asset: AssetManager.shared.danceAnimation(), in: context, rect: crabRect)
        case .work:
            drawAnimated(asset: AssetManager.shared.workAnimation(), in: context, rect: crabRect)
        case .cook:
            drawAnimated(asset: AssetManager.shared.cookAnimation(), in: context, rect: crabRect)
        case .jump:
            drawAnimated(asset: AssetManager.shared.jumpAnimation(), in: context, rect: crabRect)
        case .wave:
            drawAnimated(asset: AssetManager.shared.waveAnimation(), in: context, rect: crabRect)
        }

        context.restoreGState()
    }

    private func drawIdle(in context: CGContext, rect: CGRect) {
        let mgr = AssetManager.shared

        if isBlinking, let blink = mgr.blinkImage {
            context.draw(blink, in: rect)
        } else if let noEyes = mgr.noEyesImage {
            context.draw(noEyes, in: rect)
            drawEyes(in: context, crabRect: rect, panic: false)
        } else if let still = mgr.stillImage {
            context.draw(still, in: rect)
        }
    }

    private func drawDangle(in context: CGContext, rect: CGRect) {
        let mgr = AssetManager.shared
        if let noEyes = mgr.noEyesImage {
            context.draw(noEyes, in: rect)
            drawEyes(in: context, crabRect: rect, panic: true)
        } else if let still = mgr.stillImage {
            context.draw(still, in: rect)
        }
    }

    private func drawFall(in context: CGContext, rect: CGRect) {
        let mgr = AssetManager.shared
        if let noEyes = mgr.noEyesImage {
            context.draw(noEyes, in: rect)
            drawEyes(in: context, crabRect: rect, panic: true)
        } else if let still = mgr.stillImage {
            context.draw(still, in: rect)
        }
    }

    private func drawWalk(in context: CGContext, rect: CGRect) {
        if let walkAsset = AssetManager.shared.walkAnimation(),
           let frame = walkAsset.frame(at: stateTime, loop: true) {
            context.draw(frame, in: rect)
        } else {
            drawIdle(in: context, rect: rect)
        }
    }

    private func drawAnimated(asset: AnimatedAsset?, in context: CGContext, rect: CGRect) {
        if let asset = asset, let frame = asset.frame(at: stateTime, loop: true) {
            // Standalone GIFs maintain proper aspect ratio bottom-aligned
            let frameAspect = CGFloat(frame.width) / CGFloat(frame.height)
            let drawW = crabHeight * frameAspect
            let drawRect = CGRect(x: bounds.midX - drawW / 2.0, y: rect.minY, width: drawW, height: crabHeight)
            context.draw(frame, in: drawRect)
        } else {
            drawIdle(in: context, rect: rect)
        }
    }

    private func drawEyes(in context: CGContext, crabRect: CGRect, panic: Bool) {
        let mgr = AssetManager.shared

        let scaleX = crabRect.width / mgr.spriteSize.width
        let scaleY = crabRect.height / mgr.spriteSize.height

        let eyeSockets = [mgr.leftEyeRect, mgr.rightEyeRect]

        for socket in eyeSockets {
            let bx = crabRect.minX + socket.minX * scaleX
            let by = crabRect.minY + socket.minY * scaleY
            let ew = socket.width * scaleX
            let eh = socket.height * scaleY

            if panic {
                // Panic bulging eyes: white sclera expands, pupil shrinks in center
                context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
                context.fill(CGRect(x: bx - 1.5, y: by - 1.5, width: ew + 3.0, height: eh + 3.0))

                let pw = ew * 0.55
                let ph = eh * 0.55
                context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0))
                context.fill(CGRect(x: bx + (ew - pw) / 2.0, y: by + (eh - ph) / 2.0, width: pw, height: ph))
            } else {
                // Normal eye tracking: pupils shift inside socket
                let px = bx + eyeOffsetX * scaleX
                let py = by + eyeOffsetY * scaleY

                context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0))
                context.fill(CGRect(x: px, y: py, width: ew, height: eh))
            }
        }
    }
}
