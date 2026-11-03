import SwiftUI

/// Larry's reaction, contained: line first, then the portrait.
/// The quote sits outside the image so it can't slide underneath him.
struct LarryReactionCard: View {
    let pose: LarryVoicePose
    let quote: String
    let motion: LarryReactionMotion

    /// Tall enough for a full-body pose, hair through shoes, without cropping.
    var imageHeight: CGFloat = 340

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text(quote)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(BrandTheme.homePrimaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Larry says \(quote)")

            Image(pose.assetName)
                .resizable()
                .scaledToFit()
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
                .modifier(LarryEntranceMotion(motion: motion, replayID: "\(pose.rawValue)-\(quote)"))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrandTheme.homeCardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Plays a reaction entrance once. Hit testing stays on the whole time.
struct LarryEntranceMotion: ViewModifier {
    var motion: LarryReactionMotion
    var replayID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pose = LarryMotionPose(opacity: 0)

    func body(content: Content) -> some View {
        content
            .scaleEffect(pose.scale)
            .rotationEffect(.degrees(pose.rotation))
            .offset(x: pose.offsetX, y: pose.offsetY)
            .opacity(pose.opacity)
            .task(id: replayID) {
                await run()
            }
    }

    @MainActor
    private func run() async {
        let frames = reduceMotion ? LarryReactionMotion.reducedKeyframes : motion.keyframes
        guard let first = frames.first else { return }
        pose = first.pose
        await Task.yield()

        for index in 1..<frames.count {
            guard !Task.isCancelled else { return }
            let duration = max(0.05, frames[index].time - frames[index - 1].time)
            let next = frames[index].pose
            withAnimation(.easeInOut(duration: duration)) {
                pose = next
            }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    }
}
