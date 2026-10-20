import Foundation

/// The conferences the user follows: starred series and the editions their papers target.
public struct Following: Hashable, Sendable {
    public struct Edition: Hashable, Sendable {
        public var series: String
        public var year: Int

        public init(series: String, year: Int) {
            self.series = series
            self.year = year
        }
    }

    public var starredSeries: Set<String>
    public var targetedEditions: Set<Edition>

    public init(starredSeries: Set<String> = [], targetedEditions: Set<Edition> = []) {
        self.starredSeries = starredSeries
        self.targetedEditions = targetedEditions
    }

    public init(_ userData: UserData) {
        var editions = Set<Edition>()
        for target in userData.papers.compactMap(\.target) {
            editions.insert(Edition(series: target.series, year: target.year))
        }
        self.init(starredSeries: userData.favoriteSeries, targetedEditions: editions)
    }

    public func follows(series: String, year: Int) -> Bool {
        starredSeries.contains(series) || targetedEditions.contains(Edition(series: series, year: year))
    }

    public func followsAnyEdition(of series: String) -> Bool {
        starredSeries.contains(series) || targetedEditions.contains { $0.series == series }
    }
}
