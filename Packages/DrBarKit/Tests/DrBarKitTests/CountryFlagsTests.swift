import Testing

@testable import DrBarKit

@Suite struct CountryFlagsTests {
    @Test func theCountryIsReadFromTheEndOfThePlace() {
        #expect(CountryFlags.flags(in: "Marrakesh, Morocco") == "🇲🇦")
        #expect(CountryFlags.flags(in: "Honolulu, Hawaii, USA (Hybrid)") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Vienna, Austria / Online") == "🇦🇹")
        #expect(CountryFlags.flags(in: "Seoul, Republic of Korea") == "🇰🇷")
        #expect(CountryFlags.flags(in: "Prague, Czech Republic and Online") == "🇨🇿")
        #expect(CountryFlags.flags(in: "Antalya, Türkiye") == "🇹🇷")
        #expect(CountryFlags.flags(in: "Nanjing， China") == "🇨🇳")
        #expect(CountryFlags.flags(in: "Rio de Janeiro, Brazil.") == "🇧🇷")
    }

    @Test func statesProvincesAndCitiesStandForTheirCountry() {
        #expect(CountryFlags.flags(in: "San Francisco, CA") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Orlando, Florida USA") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Vancouver BC Canada") == "🇨🇦")
        #expect(CountryFlags.flags(in: "Washington, DC and Online") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Tbilisi, Georgia") == "🇬🇪")
        #expect(CountryFlags.flags(in: "Atlanta, Georgia, USA") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Singapore EXPO") == "🇸🇬")
        #expect(CountryFlags.flags(in: "Hong Kong SAR") == "🇭🇰")
        #expect(
            CountryFlags.flags(in: "Edinburgh, Scotland") == "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}")
    }

    @Test func everyVenueHasItsFlag() {
        #expect(CountryFlags.flags(in: "Sydney, Australia; Atlanta, USA; Paris, France") == "🇦🇺🇺🇸🇫🇷")
        #expect(CountryFlags.flags(in: "Singapore and Hong Kong") == "🇸🇬🇭🇰")
        #expect(CountryFlags.flags(in: "Atlanta, USA and Cambridge, UK") == "🇺🇸🇬🇧")
        #expect(CountryFlags.flags(in: "Vancouver, Canada; Montreal, Canada") == "🇨🇦")
        #expect(CountryFlags.flags(in: "Sarajevo, Bosnia and Herzegovina") == "🇧🇦")
    }

    @Test func whatCouldBeEitherYieldsToWhatIsCertain() {
        #expect(CountryFlags.flags(in: "Jersey City, New Jersey, USA") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Columbia, SC, USA") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Vancouver, CA") == "🇨🇦")
        #expect(CountryFlags.flags(in: "Long Beach, CA") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Perth, WA") == "🇦🇺")
        #expect(CountryFlags.flags(in: "Atlanta, Georgia") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Georgia Tech, Atlanta") == "🇺🇸")
        #expect(CountryFlags.flags(in: "Hong Kong, China") == "🇭🇰")
        #expect(CountryFlags.flags(in: "Macau SAR, China") == "🇲🇴")
    }

    @Test func aPlaceWithoutAClearCountryHasNoFlag() {
        let places = [
            "Virtual", "Online", "TBD", "co-located with SIGCOMM'24", "Jordan Hall, Stanford", "Taipei",
            "Taipei, Taiwan, China", "Hsinchu, Taiwan， China", "Taipei, China", "", ",", "Seoul, (Hybrid)",
        ]
        for place in places {
            #expect(CountryFlags.flags(in: place).isEmpty, "\(place)")
        }
    }

    @Test func emptyPartsAtTheEndAreLeftOut() {
        #expect(CountryFlags.flags(in: "Seoul, South Korea, (Hybrid)") == "🇰🇷")
        #expect(CountryFlags.flags(in: "Singapore, .") == "🇸🇬")
        #expect(CountryFlags.flags(in: "Orlando, Florida USA, ") == "🇺🇸")
    }
}
