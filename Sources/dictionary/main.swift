import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct Suggestion: Decodable {
    let word: String
    let score: Int
    let tags: [String]?
}

struct DictionaryEntry: Decodable {
    struct Meaning: Decodable {
        struct Definition: Decodable { let definition: String }
        let definitions: [Definition]
    }
    let meanings: [Meaning]
}

enum APIError: Error, LocalizedError {
    case badResponse
    case noResults

    var errorDescription: String? {
        switch self {
        case .badResponse: "The dictionary service returned an unexpected response."
        case .noResults: "No synonym suggestions found. Try another word."
        }
    }
}

enum DictionaryAPI {
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Result<Data, Error>?

        func set(_ value: Result<Data, Error>) {
            lock.lock()
            storage = value
            lock.unlock()
        }

        func get() -> Result<Data, Error>? {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    static func suggestions(for word: String) throws -> [Suggestion] {
        var components = URLComponents(string: "https://api.datamuse.com/words")!
        components.queryItems = [
            URLQueryItem(name: "rel_syn", value: word),
            URLQueryItem(name: "md", value: "f"),
            URLQueryItem(name: "max", value: "24")
        ]
        let data = try get(components.url!)
        let results = try JSONDecoder().decode([Suggestion].self, from: data)
        guard !results.isEmpty else { throw APIError.noResults }
        return results.sorted { $0.score > $1.score }
    }

    static func definition(for word: String) throws -> String? {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)")!
        let data = try get(url)
        let entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        return entries.lazy.flatMap(\.meanings).flatMap(\.definitions).first?.definition
    }

    private static func get(_ url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("dictionary/1.0 (macOS terminal dictionary)", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error { result.set(.failure(error)); return }
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode), let data else {
                result.set(.failure(APIError.badResponse))
                return
            }
            result.set(.success(data))
        }.resume()
        semaphore.wait()
        guard let value = result.get() else { throw APIError.badResponse }
        return try value.get()
    }
}

struct TerminalMode {
    private var original = termios()
    private var active = false

    mutating func enable() {
        guard isatty(STDIN_FILENO) == 1, tcgetattr(STDIN_FILENO, &original) == 0 else { return }
        var raw = original
        raw.c_lflag &= ~UInt(ECHO | ICANON | IEXTEN | ISIG)
        raw.c_iflag &= ~UInt(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_cflag |= UInt(CS8)
        raw.c_oflag &= ~UInt(OPOST)
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        active = true
    }

    mutating func restore() {
        if active { _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original); active = false }
    }
}

struct App {
    private var mode = TerminalMode()
    private var enabled = false
    private var input = ""
    private var suggestions: [Suggestion] = []
    private var selected = 0
    private var message = "Press d to enable word entry."
    private var definition: String?

    mutating func run() {
        mode.enable()
        defer { mode.restore(); print("\u{001B}[0m\u{001B}[?25h") }
        print("\u{001B}[?25l", terminator: "")
        redraw()
        while let byte = readByte() {
            if byte == 0x1B {
                handleEscape()
            } else if byte == 0x7F || byte == 0x08 {
                if enabled, !input.isEmpty { input.removeLast(); redraw() }
            } else if byte == 0x0D || byte == 0x0A {
                if enabled, !input.trimmingCharacters(in: .whitespaces).isEmpty { search() }
                else if !suggestions.isEmpty { showDefinition() }
            } else if byte == 0x04 {
                break
            } else if byte >= 0x20 && byte < 0x7F {
                let character = Character(UnicodeScalar(byte))
                if enabled, input.isEmpty, character == "d" { enabled = false; message = "Word entry off. Press d to turn it on."; redraw() }
                else if !enabled, character == "d" { enabled = true; message = "Type a word, then press Enter."; redraw() }
                else if enabled { input.append(character); definition = nil; redraw() }
                else if character == "q" { break }
            }
        }
    }

    private mutating func handleEscape() {
        guard readByte() == 0x5B, let direction = readByte() else { return }
        if direction == 0x41, selected > 0 { selected -= 1; definition = nil; redraw() }
        if direction == 0x42, selected + 1 < suggestions.count { selected += 1; definition = nil; redraw() }
    }

    private mutating func search() {
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        message = "Looking up “\(word)”…"
        redraw()
        do {
            suggestions = try DictionaryAPI.suggestions(for: word)
            selected = 0
            definition = nil
            message = "\(suggestions.count) suggestions · arrows to browse · Enter for a definition"
        } catch {
            suggestions = []
            message = error.localizedDescription
        }
        input = ""
        redraw()
    }

    private mutating func showDefinition() {
        guard suggestions.indices.contains(selected) else { return }
        do {
            definition = try DictionaryAPI.definition(for: suggestions[selected].word) ?? "No definition is available."
        } catch {
            definition = "Definition unavailable: \(error.localizedDescription)"
        }
        redraw()
    }

    private func redraw() {
        var out = "\u{001B}[H\u{001B}[2J"
        out += "\u{001B}[1;36mdictionary\u{001B}[0m  \(enabled ? "\u{001B}[32m● ON\u{001B}[0m" : "\u{001B}[90m○ OFF\u{001B}[0m")\n"
        out += "────────────────────────────────────────────────────────\n"
        out += "\(enabled ? "Word" : "Dictionary")  \(enabled ? input + "▌" : "(press d to enable)")\n\n"
        if !suggestions.isEmpty {
            out += "Best matches first · color fades from green to red\n\n"
            for (index, suggestion) in suggestions.enumerated() {
                let color = colorCode(for: index, count: suggestions.count)
                let marker = index == selected ? "❯" : " "
                let frequency = suggestion.tags?.first(where: { $0.hasPrefix("f:") }).map { "  \($0)" } ?? ""
                out += "\(marker) \(color)\(suggestion.word)\u{001B}[0m\(frequency)\n"
            }
            if let definition {
                out += "\n\u{001B}[1m\(suggestions[selected].word)\u{001B}[0m: \(definition)\n"
            }
        }
        out += "\n\u{001B}[90m\(message)\u{001B}[0m\n"
        out += "\u{001B}[90md toggle · ↑/↓ browse · Enter search/define · q quit\u{001B}[0m"
        print(out, terminator: "")
        fflush(stdout)
    }

    private func colorCode(for index: Int, count: Int) -> String {
        let progress = count <= 1 ? 0.0 : Double(index) / Double(count - 1)
        if progress < 0.25 { return "\u{001B}[32m" }
        if progress < 0.5 { return "\u{001B}[92m" }
        if progress < 0.75 { return "\u{001B}[33m" }
        return "\u{001B}[31m"
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        return Darwin.read(STDIN_FILENO, &byte, 1) == 1 ? byte : nil
    }
}

var app = App()
app.run()
