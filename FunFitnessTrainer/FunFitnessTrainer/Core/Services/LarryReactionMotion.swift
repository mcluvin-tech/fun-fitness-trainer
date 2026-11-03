import Foundation
import CoreGraphics

/// One-shot entrance for a reaction. Nothing here loops.
enum LarryReactionMotion: Equatable {
    case popBounce
    case scaleNod
    case fade
    case tilt
    case headShake
    case recoil

    static func forEmotion(_ emotion: LarryEmotion) -> LarryReactionMotion {
        switch emotion {
        case .excited:
            return .popBounce
        case .confident, .encouraging:
            return .scaleNod
        case .neutral:
            return .fade
        case .skeptical:
            return .tilt
        case .disappointed:
            return .headShake
        case .shocked:
            return .recoil
        }
    }

    var keyframes: [LarryMotionKeyframe] {
        switch self {
        case .popBounce:
            return [
                LarryMotionKeyframe(time: 0, pose: LarryMotionPose(scale: 0.88, offsetY: 10, opacity: 0)),
                LarryMotionKeyframe(time: 0.28, pose: LarryMotionPose(scale: 1.045, offsetY: -4, opacity: 1)),
                LarryMotionKeyframe(time: 0.70, pose: LarryMotionPose()),
            ]
        case .scaleNod:
            return [
                LarryMotionKeyframe(time: 0, pose: LarryMotionPose(scale: 0.92, rotation: -2.5, opacity: 0)),
                LarryMotionKeyframe(time: 0.34, pose: LarryMotionPose(scale: 1.03, rotation: 2.2, opacity: 1)),
                LarryMotionKeyframe(time: 0.80, pose: LarryMotionPose()),
            ]
        case .fade:
            return [
                LarryMotionKeyframe(time: 0, pose: LarryMotionPose(opacity: 0)),
                LarryMotionKeyframe(time: 0.50, pose: LarryMotionPose()),
            ]
        case .tilt:
            return [
                LarryMotionKeyframe(time: 0, pose: LarryMotionPose(opacity: 0)),
                LarryMotionKeyframe(time: 0.36, pose: LarryMotionPose(offsetX: 6, rotation: -6.5, opacity: 1)),
                LarryMotionKeyframe(time: 0.90, pose: LarryMotionPose(offsetX: 2, rotation: -2.5, opacity: 1)),
            ]
        case .headShake:
            return [
                LarryMotionKeyframe(time: 0, pose: LarryMotionPose(opacity: 0.15)),
                LarryMotionKeyframe(time: 0.14, pose: LarryMotionPose(offsetX: 6, rotation: 1.5, opacity: 1)),
                LarryMotionKeyframe(time: 0.30, pose: LarryMotionPose(offsetX: -6, rotation: -1.5, opacity: 1)),
                LarryMotionKeyframe(time: 0.46, pose: LarryMotionPose(offsetX: 3.5, rotation: 0.8, opacity: 1)),
                LarryMotionKeyframe(time: 0.80, pose: LarryMotionPose()),
            ]
        case .recoil:
            return [
                LarryMotionKeyframe(time: 0, pose: LarryMotionPose(scale: 1.02, opacity: 0)),
                LarryMotionKeyframe(time: 0.18, pose: LarryMotionPose(scale: 0.92, offsetY: 10, rotation: 4, opacity: 1)),
                LarryMotionKeyframe(time: 0.50, pose: LarryMotionPose(scale: 1.02, offsetY: -3, rotation: -1, opacity: 1)),
                LarryMotionKeyframe(time: 1.05, pose: LarryMotionPose()),
            ]
        }
    }

    /// Short fade used when Reduce Motion is on.
    static var reducedKeyframes: [LarryMotionKeyframe] {
        [
            LarryMotionKeyframe(time: 0, pose: LarryMotionPose(opacity: 0)),
            LarryMotionKeyframe(time: 0.25, pose: LarryMotionPose()),
        ]
    }
}

struct LarryMotionPose: Equatable {
    var scale: CGFloat = 1
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var rotation: Double = 0
    var opacity: Double = 1
}

struct LarryMotionKeyframe: Equatable {
    var time: TimeInterval
    var pose: LarryMotionPose
}
