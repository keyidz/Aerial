//
//  AnimationLayer.swift
//  Aerial
//
//  Created by Guillaume Louel on 11/12/2019.
//  Copyright © 2019 Guillaume Louel. All rights reserved.
//

import Foundation
import AVKit

class AnimationLayer: CATextLayer {
    var layerManager: LayerManager
    var lastCorner = -1
    var isPreview: Bool
    var baseLayer: CALayer
    var offsets: LayerOffsets
    var corner: InfoCorner = .bottomLeft

    var currentCorner: InfoCorner?
    var currentHeight: CGFloat?
    var currentPosition: CGPoint?

    // Super init, used by CATextLayer's setFont, etc
    override init(layer: Any) {
        layerManager = (layer as! AnimationLayer).layerManager
        isPreview = (layer as! AnimationLayer).isPreview
        baseLayer = (layer as! AnimationLayer).baseLayer
        offsets = (layer as! AnimationLayer).offsets
        corner = (layer as! AnimationLayer).corner
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Our init
    init(withLayer: CALayer, isPreview: Bool, offsets: LayerOffsets, manager: LayerManager) {
        self.layerManager = manager
        self.isPreview = isPreview
        self.baseLayer = withLayer
        self.offsets = offsets
        super.init()

        // Same size as the screen
        self.frame = withLayer.bounds
        // Starts hidden, with a bit of shadow for text separation
        self.opacity = 0
        self.shadowRadius = 2
        self.shadowOpacity = 1.0
        self.shadowColor = CGColor.black
    }

    // Called before starting a new video, usually overridden
    func clear(player: AVPlayer) {
    }

    // Called at each new video, usually overridden
    func setupForVideo(video: AerialVideo, player: AVPlayer) {
    }

    // Update the string and move to a corner
    func update(string: String) {
        // Setup string
        self.string = string
        self.isWrapped = true

        // This is the rect resized to our string
        frame = calculateRect(string: string, font: font as! NSFont)
        move(toCorner: getCorner(), fullRedraw: false)
    }

    // Handle the random corner
    func getCorner() -> InfoCorner {
        if corner != .random {
            return corner
        }

        // Find a new corner, different from the previous one
        var newCorner = Int.random(in: 0...5)

        while newCorner == lastCorner || !layerManager.isCornerAcceptable(corner: newCorner) {
            newCorner = Int.random(in: 0...5)
        }

        return InfoCorner(rawValue: newCorner)!
    }

    // Move to a corner, this may need to force the redraw of a whole corner
    func move(toCorner: InfoCorner, fullRedraw: Bool) {
        if let currCorner = currentCorner, !fullRedraw {
            // Are we on the same corner ?
            if currCorner == toCorner {
                // And same height ?
                if currentHeight! == frame.height {
                    // position is reset, so we need to set it again
                    position = currentPosition!
                    return
                } else {
                    // It's a whole corner redraw, then
                    layerManager.redrawCorner(corner: toCorner)
                    return
                }
            } else {
                // So we changed corner... we redraw our previous corner
                // and redraw the new one too !
                let prevCorner = currCorner
                currentCorner = toCorner
                layerManager.redrawCorner(corner: prevCorner)
                layerManager.redrawCorner(corner: toCorner)
                return
            }
        }

        let mx = getHorizontalMargin()
        let my = getVerticalMargin(forCorner: toCorner)

        var newPos: CGPoint

        switch toCorner {
        case .topLeft:
            anchorPoint = CGPoint(x: 0, y: 1)
            newPos = CGPoint(x: mx, y: baseLayer.bounds.height - my)
            alignmentMode = .left
        case .topCenter:
            anchorPoint = CGPoint(x: 0.5, y: 1)
            newPos = CGPoint(x: baseLayer.bounds.width/2,
                             y: baseLayer.bounds.height-my)
            alignmentMode = .center
        case .topRight:
            anchorPoint = CGPoint(x: 1, y: 1)
            newPos = CGPoint(x: baseLayer.bounds.width-mx,
                             y: baseLayer.bounds.height-my)
            alignmentMode = .right

        case .bottomLeft:
            anchorPoint = CGPoint(x: 0, y: 0)
            newPos = CGPoint(x: mx, y: my)
            alignmentMode = .left
        case .bottomCenter:
            anchorPoint = CGPoint(x: 0.5, y: 0)
            newPos = CGPoint(x: baseLayer.bounds.width/2, y: my)
            alignmentMode = .center
        default:    // bottomRight
            anchorPoint = CGPoint(x: 1, y: 0)
            newPos = CGPoint(x: baseLayer.bounds.width-mx, y: my)
            alignmentMode = .right
        }

        moveTo(point: newPos)

        let offset = offsets.corner[toCorner] == 0
            ? my + frame.height
            : frame.height

        // Make sure we update our offsets for the next layer
        offsets.corner[toCorner]! += offset

        // We need to save for next time !
        currentCorner = toCorner
        currentHeight = frame.height
        currentPosition = newPos
    }

    // MARK: Animations
    // Move in 1 second to a position
    // Those are masked by the transition between fades
    func moveTo(point: CGPoint) {
        CATransaction.begin()
        CATransaction.setValue(1, forKey: kCATransactionAnimationDuration)
        self.position = point
        CATransaction.commit()
    }

    // Create a Fade In/Out animation
    func createFadeInOutAnimation(duration: Double) -> CAKeyframeAnimation {
        let fadeAnimation = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnimation.values = [0, 0, 1, 1, 0] as [NSNumber]
        fadeAnimation.keyTimes = [
            0,
            Double(1 / duration ),
            Double((1 + AerialView.textFadeDuration) / duration),
            Double(1 - AerialView.textFadeDuration / duration),
            1,
        ] as [NSNumber]
        fadeAnimation.duration = duration
        return fadeAnimation
    }

    // Create a Fade In (only) animation, used for things that
    // should always be on screen (clock, etc)
    func createFadeInAnimation() -> CAKeyframeAnimation {
        let fadeAnimation = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnimation.values = [0, 0, 1] as [NSNumber]
        fadeAnimation.keyTimes = [
            0,
            Double(1 / (1 + AerialView.textFadeDuration)),
            Double(1),
        ] as [NSNumber]
        fadeAnimation.duration = 1 + AerialView.textFadeDuration
        return fadeAnimation
    }

    // MARK: Text/Font stuff
    // Calculate the screen rect that will be used by our string
    func calculateRect(string: String, font: NSFont) -> CGRect {
        let mx = getHorizontalMargin()
        let boundingRect = CGSize(width: baseLayer.visibleRect.size.width-2*mx,
                                  height: baseLayer.visibleRect.size.height)

        // We need an attributed string to take the font into account
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key.font: font as Any]
        let str = NSAttributedString(string: string, attributes: attributes)

        // Calculate bounding box
        let rect = str.boundingRect(with: boundingRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])

        // Last line won't appear if we don't adjust
        return CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height + 10)
    }

    // Get the font and font size
    func getFont(name: String, size: Double) -> (NSFont, CGFloat) {
        let fontSize = isPreview ? 12 : CGFloat(size)

        // Get font with a fallback in case
        var font = NSFont(name: "Helvetica Neue Medium", size: 28)
        if let tryFont = NSFont(name: name, size: fontSize) {
            font = tryFont
        }

        return (font!, fontSize)
    }

    // Get the horizontal margin to the border of the screen
    func getHorizontalMargin() -> CGFloat {
        // We override for previews
        if isPreview {
            return 10
        }

        let preferences = Preferences.sharedInstance
        var mx: CGFloat = 50

        // We may override margins
        if preferences.overrideMargins {
            mx = CGFloat(preferences.marginX!)
        }

        return mx
    }

    // Get the horizontal margin to the border of the screen
    func getVerticalMargin(forCorner: InfoCorner) -> CGFloat {
        // If we already have an offset, use that !
        if offsets.corner[forCorner] != 0 {
            return offsets.corner[forCorner]!
        }

        // We override for previews
        if isPreview {
            offsets.corner[forCorner] = 10
            return offsets.corner[forCorner]!
        }

        let preferences = Preferences.sharedInstance
        var my: CGFloat = 50

        // We may override margins
        if preferences.overrideMargins {
            my = CGFloat(preferences.marginY!)
        }

        offsets.corner[forCorner] = my
        return my
    }
}
