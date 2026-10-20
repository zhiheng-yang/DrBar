import SwiftUI

/// A text field for a web address, with a button that opens it.
struct LinkField: View {
    private let title: LocalizedStringKey
    @Binding private var text: String
    private let prompt: String

    init(_ title: LocalizedStringKey, text: Binding<String>, prompt: String) {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        HStack {
            TextField(title, text: $text, prompt: Text(verbatim: prompt))
            if let url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open in browser")
            }
        }
    }

    private var url: URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
            url.scheme == "https" || url.scheme == "http"
        else { return nil }
        return url
    }
}
