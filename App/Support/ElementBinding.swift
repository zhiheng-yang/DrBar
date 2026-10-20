import SwiftUI

extension Binding where Value: Identifiable & Sendable, Value.ID: Sendable {
    /// A binding to the element with `id`, looked up on every access, so it stays valid while the
    /// list changes under it, as when an open editor's element is deleted. Once the element is gone,
    /// reads return `fallback` and writes do nothing.
    init(_ elements: Binding<[Value]>, id: Value.ID, fallback: Value) {
        self.init(
            get: { elements.wrappedValue.first { $0.id == id } ?? fallback },
            set: { newValue in
                if let index = elements.wrappedValue.firstIndex(where: { $0.id == id }) {
                    elements.wrappedValue[index] = newValue
                }
            })
    }
}
