import AppKit
import QuartzCore

/// Which drink the menu bar icon (and its fill animation) currently represents.
enum IconStyle: String {
    case coffee
    case energyDrink
}

/// Draws the menu bar icon for the current `style`: either a coffee cup with rising
/// steam, or a Red Bull-style can that sprouts wings, while the underlying toggle
/// behavior (and Info.plist identity) stays the same either way.
final class CoffeeIconView: NSView {
    private let container = CALayer()
    private let outlineLayer = CALayer()
    private let fillLayer = CALayer()

    private let leftWing = CAShapeLayer()
    private let rightWing = CAShapeLayer()
    private var steamWisps: [CAShapeLayer] = []

    /// How long the wings/steam stay out before folding back in.
    private let wingsHoldDuration: CFTimeInterval = 1.9

    private(set) var isFilled = false

    var style: IconStyle = .energyDrink {
        didSet {
            guard style != oldValue else { return }
            hideWingsImmediately()
            stopSteamAnimation()
            updateImages()
        }
    }

    /// Hover in/out, used to open the custom menu on hover. Tracked here
    /// (rather than on the underlying NSStatusBarButton) because that button
    /// is an AppKit-private control that manages its own tracking areas and
    /// silently drops ones added from outside during its own layout passes.
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()

        outlineLayer.contentsGravity = .resizeAspect
        fillLayer.contentsGravity = .resizeAspect
        fillLayer.opacity = 0

        container.addSublayer(outlineLayer)
        container.addSublayer(fillLayer)
        layer?.addSublayer(container)

        setupWings()
        setupSteamWisps()
        updateImages()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverExit?()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        outlineLayer.frame = container.bounds
        fillLayer.frame = container.bounds
        positionWings()
        positionSteamWisps()
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        outlineLayer.contentsScale = scale
        fillLayer.contentsScale = scale
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateImages()
    }

    func setFilled(_ filled: Bool, animated: Bool) {
        guard filled != isFilled || !animated else { return }
        isFilled = filled

        if animated {
            // A single generic "charging" cue for turning on, regardless of icon
            // style — no drink-specific jingle, just a quick power-up chime.
            NSSound(named: filled ? "Hero" : "Bottle")?.play()
            switch style {
            case .energyDrink:
                filled ? playWingsSequence() : hideWingsImmediately()
            case .coffee:
                filled ? startSteamAnimation() : stopSteamAnimation()
            }
        } else if !filled {
            hideWingsImmediately()
            stopSteamAnimation()
        }

        guard animated else {
            outlineLayer.opacity = filled ? 0 : 1
            fillLayer.opacity = filled ? 1 : 0
            return
        }

        let duration: CFTimeInterval = 0.35
        let fadeOutline = CABasicAnimation(keyPath: "opacity")
        fadeOutline.fromValue = outlineLayer.opacity
        fadeOutline.toValue = filled ? 0 : 1
        fadeOutline.duration = duration
        outlineLayer.opacity = filled ? 0 : 1
        outlineLayer.add(fadeOutline, forKey: "fade")

        let fadeFill = CABasicAnimation(keyPath: "opacity")
        fadeFill.fromValue = fillLayer.opacity
        fadeFill.toValue = filled ? 1 : 0
        fadeFill.duration = duration
        fillLayer.opacity = filled ? 1 : 0
        fillLayer.add(fadeFill, forKey: "fade")

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = filled ? 0.82 : 1.12
        pop.toValue = 1.0
        pop.mass = 0.6
        pop.stiffness = 220
        pop.damping = 12
        pop.duration = pop.settlingDuration
        container.add(pop, forKey: "pop")
    }

    // MARK: - Wings (energy drink)

    private func setupWings() {
        for wing in [leftWing, rightWing] {
            wing.fillColor = NSColor.white.withAlphaComponent(0.95).cgColor
            wing.strokeColor = NSColor(white: 0.6, alpha: 0.6).cgColor
            wing.lineWidth = 0.4
            wing.opacity = 0
            wing.transform = CATransform3DMakeScale(0.001, 0.001, 1)
            container.addSublayer(wing)
        }
    }

    private func positionWings() {
        guard style == .energyDrink else { return }
        let width = bounds.width
        let height = bounds.height

        // canImage draws into a 16x20 canvas with resizeAspect, which letterboxes
        // when the view's aspect ratio doesn't match — find where that canvas
        // actually lands in view space so the wings line up with the can's edges.
        let canvasAspect: CGFloat = 16.0 / 20.0
        let containerAspect = width / height
        let imageRect: CGRect
        if containerAspect > canvasAspect {
            let imageWidth = height * canvasAspect
            imageRect = CGRect(x: (width - imageWidth) / 2, y: 0, width: imageWidth, height: height)
        } else {
            let imageHeight = width / canvasAspect
            imageRect = CGRect(x: 0, y: (height - imageHeight) / 2, width: width, height: imageHeight)
        }

        // Matches the can body's left/right edges and shoulder height as drawn in canImage
        // (bodyInset 3.0 of 16 wide; body spans y 0.8...17.4 of 20 tall).
        let leftEdgeX = imageRect.minX + imageRect.width * 0.1875
        let rightEdgeX = imageRect.minX + imageRect.width * 0.8125
        let anchorY = imageRect.minY + imageRect.height * 0.54

        leftWing.position = CGPoint(x: leftEdgeX, y: anchorY)
        leftWing.bounds = CGRect(x: 0, y: 0, width: imageRect.width * 0.55, height: imageRect.height * 0.36)
        leftWing.anchorPoint = CGPoint(x: 1.0, y: 0.5)
        leftWing.path = wingPath(in: leftWing.bounds, flipped: false)

        rightWing.position = CGPoint(x: rightEdgeX, y: anchorY)
        rightWing.bounds = leftWing.bounds
        rightWing.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        rightWing.path = wingPath(in: rightWing.bounds, flipped: true)
    }

    /// A single swept-back wing, tip at the trailing edge, root at x = flipped ? 0 : maxX.
    private func wingPath(in rect: CGRect, flipped: Bool) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width
        let h = rect.height
        let root = CGPoint(x: flipped ? 0 : w, y: h * 0.5)
        let tip = CGPoint(x: flipped ? w : 0, y: h * 0.08)

        path.move(to: root)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: flipped ? w * 0.35 : w * 0.65, y: h * 0.95),
            control2: CGPoint(x: flipped ? w * 0.85 : w * 0.15, y: h * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: root.x, y: h * 0.35),
            control1: CGPoint(x: flipped ? w * 0.5 : w * 0.5, y: h * 0.0),
            control2: CGPoint(x: flipped ? w * 0.15 : w * 0.85, y: h * 0.18)
        )
        path.closeSubpath()
        return path
    }

    private func playWingsSequence() {
        let growDuration: CFTimeInterval = 0.3
        let shrinkDuration: CFTimeInterval = 0.32

        // Figure out how long the pop-in spring actually takes to settle so the flap
        // stroke starts cleanly afterward, instead of fighting with the bounce.
        let popInTemplate = CASpringAnimation(keyPath: "transform.scale")
        popInTemplate.mass = 0.7
        popInTemplate.stiffness = 180
        popInTemplate.damping = 13
        let settleDuration = popInTemplate.settlingDuration
        let flapDuration: CFTimeInterval = 1.1
        let collapseDelay = settleDuration + flapDuration + wingsHoldDuration
        let flapStartTime = CACurrentMediaTime() + settleDuration

        for wing in [leftWing, rightWing] {
            wing.removeAllAnimations()

            // One long, fluid stroke after the pop-in settles, then hold still.
            // A gentle ease per segment (rather than one global curve) keeps the
            // sweep from ever feeling like it snaps between keyframes.
            let flapAngle: CGFloat = 13 * .pi / 180
            let easeSegment = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.55, 1)
            let flap = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            flap.values = [0, flapAngle, -flapAngle * 0.25, 0]
            flap.keyTimes = [0, 0.45, 0.8, 1.0]
            flap.timingFunctions = [easeSegment, easeSegment, easeSegment]
            flap.duration = flapDuration
            flap.beginTime = flapStartTime
            flap.fillMode = .forwards
            flap.isRemovedOnCompletion = false

            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = 1
            fadeIn.duration = growDuration
            fadeIn.fillMode = .forwards
            fadeIn.isRemovedOnCompletion = false

            let popIn = CASpringAnimation(keyPath: "transform.scale")
            popIn.fromValue = 0.001
            popIn.toValue = 1.0
            popIn.mass = 0.7
            popIn.stiffness = 180
            popIn.damping = 13
            popIn.duration = popIn.settlingDuration
            popIn.fillMode = .forwards
            popIn.isRemovedOnCompletion = false

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1
            fadeOut.toValue = 0
            fadeOut.beginTime = CACurrentMediaTime() + collapseDelay
            fadeOut.duration = shrinkDuration
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false

            let popOut = CASpringAnimation(keyPath: "transform.scale")
            popOut.fromValue = 1.0
            popOut.toValue = 0.001
            popOut.beginTime = CACurrentMediaTime() + collapseDelay
            popOut.mass = 0.5
            popOut.stiffness = 220
            popOut.damping = 18
            popOut.duration = popOut.settlingDuration
            popOut.fillMode = .forwards
            popOut.isRemovedOnCompletion = false

            wing.add(fadeIn, forKey: "fadeIn")
            wing.add(popIn, forKey: "popIn")
            wing.add(flap, forKey: "flap")
            wing.add(fadeOut, forKey: "fadeOut")
            wing.add(popOut, forKey: "popOut")
        }
    }

    private func hideWingsImmediately() {
        for wing in [leftWing, rightWing] {
            wing.removeAllAnimations()
            wing.opacity = 0
            wing.transform = CATransform3DMakeScale(0.001, 0.001, 1)
        }
    }

    // MARK: - Steam (coffee)

    private func setupSteamWisps() {
        for _ in 0..<2 {
            let wisp = CAShapeLayer()
            wisp.fillColor = nil
            wisp.lineWidth = 1.2
            wisp.lineCap = .round
            wisp.opacity = 0
            container.addSublayer(wisp)
            steamWisps.append(wisp)
        }
    }

    private func positionSteamWisps() {
        guard style == .coffee else { return }
        let tint = currentTint().cgColor
        let width = bounds.width
        let height = bounds.height

        for (index, wisp) in steamWisps.enumerated() {
            wisp.strokeColor = tint
            let xOffset: CGFloat = index == 0 ? width * 0.42 : width * 0.58
            let startY = height * 0.65
            let path = CGMutablePath()
            let dx: CGFloat = index == 0 ? -1.5 : 1.5
            path.move(to: CGPoint(x: xOffset, y: startY))
            path.addCurve(
                to: CGPoint(x: xOffset + dx, y: startY + 5),
                control1: CGPoint(x: xOffset + dx * 1.5, y: startY + 1.8),
                control2: CGPoint(x: xOffset, y: startY + 3.5)
            )
            wisp.path = path
        }
    }

    private func startSteamAnimation() {
        let duration: CFTimeInterval = 1.3

        for (index, wisp) in steamWisps.enumerated() {
            wisp.removeAllAnimations()
            let delay = Double(index) * 0.35

            let group = CAAnimationGroup()
            group.duration = duration
            group.repeatCount = 2
            group.beginTime = CACurrentMediaTime() + delay

            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = 0
            rise.toValue = 4.0

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.65, 0.4, 0]
            fade.keyTimes = [0, 0.25, 0.7, 1.0]

            group.animations = [rise, fade]
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wisp.add(group, forKey: "steam")
        }
    }

    private func stopSteamAnimation() {
        for wisp in steamWisps {
            wisp.removeAllAnimations()
            wisp.opacity = 0
        }
    }

    // MARK: - Appearance & Images

    private func updateImages() {
        let tint = currentTint()
        switch style {
        case .energyDrink:
            outlineLayer.contents = canImage(tint: tint, filled: false)
            fillLayer.contents = canImage(tint: tint, filled: true)
        case .coffee:
            outlineLayer.contents = symbolImage("cup.and.saucer", tint: tint)
            fillLayer.contents = symbolImage("cup.and.saucer.fill", tint: tint)
        }
        for wisp in steamWisps {
            wisp.strokeColor = tint.cgColor
        }
    }

    private func currentTint() -> NSColor {
        var color = NSColor.labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .labelColor
        }
        return color
    }

    private func symbolImage(_ name: String, tint: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }

        return NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// A drink-can silhouette — original artwork, not a reproduction of any real can's
    /// logo or wordmark. The active/filled state uses a silver body with a single
    /// diagonal blue stripe and a small abstract red/yellow color-block accent (no
    /// figurative logo); the inactive/outline state is a plain monochrome template shape.
    private func canImage(tint: NSColor, filled: Bool) -> NSImage? {
        let size = NSSize(width: 16, height: 20)

        return NSImage(size: size, flipped: false) { rect in
            // Slimmer body, closer to a real can's proportions.
            let bodyInset: CGFloat = 3.0
            let bodyRect = NSRect(
                x: bodyInset,
                y: 0.8,
                width: rect.width - bodyInset * 2,
                height: rect.height - 3.4
            )
            let body = NSBezierPath(roundedRect: bodyRect, xRadius: 1.1, yRadius: 1.1)

            let lidRect = NSRect(
                x: bodyInset - 0.3,
                y: bodyRect.maxY - 0.55,
                width: bodyRect.width + 0.6,
                height: 1.8
            )
            let lid = NSBezierPath(ovalIn: lidRect)

            let tab = NSBezierPath()
            let tabCenter = NSPoint(x: rect.midX, y: lidRect.maxY - 0.75)
            tab.appendOval(in: NSRect(x: tabCenter.x - 1.3, y: tabCenter.y - 0.55, width: 2.6, height: 1.1))

            if filled {
                NSGraphicsContext.saveGraphicsState()
                body.setClip()

                NSColor(calibratedWhite: 0.93, alpha: 1).set()
                body.fill()

                // Single diagonal blue stripe sweeping across the silver body.
                let stripeCenter = NSPoint(x: bodyRect.midX, y: bodyRect.midY)
                var stripeTransform = AffineTransform.identity
                stripeTransform.translate(x: stripeCenter.x, y: stripeCenter.y)
                stripeTransform.rotate(byDegrees: 22)
                stripeTransform.translate(x: -stripeCenter.x, y: -stripeCenter.y)
                let stripeRect = NSRect(
                    x: bodyRect.midX - bodyRect.width * 0.42,
                    y: bodyRect.minY - bodyRect.height * 0.3,
                    width: bodyRect.width * 0.84,
                    height: bodyRect.height * 1.6
                )
                let stripe = NSBezierPath(rect: stripeRect)
                stripe.transform(using: stripeTransform)
                NSColor(calibratedRed: 0.07, green: 0.17, blue: 0.46, alpha: 1).set()
                stripe.fill()

                // Small abstract red/yellow color-block accent, not a figurative logo.
                let emblemY = bodyRect.minY + bodyRect.height * 0.47
                let emblemCenter = NSPoint(x: bodyRect.midX, y: emblemY)
                let yellowRadius: CGFloat = bodyRect.width * 0.24
                NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.1, alpha: 1).set()
                NSBezierPath(ovalIn: NSRect(
                    x: emblemCenter.x - yellowRadius, y: emblemCenter.y - yellowRadius * 0.6,
                    width: yellowRadius * 2, height: yellowRadius * 1.2
                )).fill()

                NSColor(calibratedRed: 0.82, green: 0.13, blue: 0.13, alpha: 1).set()
                let redRadius: CGFloat = bodyRect.width * 0.19
                for dx: CGFloat in [-1, 1] {
                    let cx = emblemCenter.x + dx * yellowRadius * 0.8
                    NSBezierPath(ovalIn: NSRect(
                        x: cx - redRadius, y: emblemCenter.y - redRadius * 0.5,
                        width: redRadius * 2, height: redRadius * 1.0
                    )).fill()
                }

                NSGraphicsContext.restoreGraphicsState()

                NSColor(calibratedWhite: 0.86, alpha: 1).set()
                lid.fill()
                NSColor(calibratedWhite: 0.55, alpha: 1).set()
                tab.fill()
            } else {
                tint.set()
                body.lineWidth = 1.1
                body.stroke()
                lid.lineWidth = 1.0
                lid.stroke()
                tab.lineWidth = 0.9
                tab.stroke()
            }
            return true
        }
    }
}
