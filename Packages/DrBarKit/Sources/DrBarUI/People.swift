import AppKit
import DrBarKit
import SwiftUI

extension EnvironmentValues {
    /// The people of the recipient groups, whom blocks name as working on them.
    @Entry public var planPeople: [UUID: Person] = [:]
}

/// The monograms of the people on a block, overlapping a little; past three, the third says how many
/// more there are. In the block's own color, so that they belong to it and stay small beside it.
public struct PeopleBadges: View {
    public let people: [Person]
    public var color: Color
    public var size: CGFloat

    static let maxShown = 3

    public init(_ people: [Person], color: Color, size: CGFloat) {
        self.people = people
        self.color = color
        self.size = size
    }

    /// How wide `count` badges are, for the name beside them to leave room.
    public static func width(count: Int, size: CGFloat) -> CGFloat {
        let shown = min(count, maxShown)
        return shown == 0 ? 0 : size + CGFloat(shown - 1) * size * 0.72
    }

    public var body: some View {
        let overflow = people.count > Self.maxShown
        let shown = overflow ? Array(people.prefix(Self.maxShown - 1)) : people
        HStack(spacing: -size * 0.28) {
            ForEach(shown) { person in
                badge(person.initials)
            }
            if overflow {
                badge("+\(people.count - shown.count)")
            }
        }
        .accessibilityHidden(true)
    }

    private func badge(_ text: String) -> some View {
        Circle()
            .fill(color)
            .overlay {
                Text(verbatim: text)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 1)
            }
            // Keeps overlapping monograms apart, and a solid block from its own color.
            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.9), lineWidth: 1))
            .frame(width: size, height: size)
    }
}
