import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct Suggestion: Decodable {
    let word: String
    let score: Int
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
        request.setValue("Maconary/1.0 (macOS terminal dictionary)", forHTTPHeaderField: "User-Agent")
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
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        active = true
    }

    mutating func restore() {
        if active { _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original); active = false }
    }
}

struct App {
    private var mode = TerminalMode()
    private var input = ""
    private var suggestions: [Suggestion] = []
    private var selected = 0
    private var message = "Type a word and press Return to search."
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
                if !input.isEmpty { input.removeLast(); redraw() }
            } else if byte == 0x0D || byte == 0x0A {
                if !input.trimmingCharacters(in: .whitespaces).isEmpty { search() }
                else if !suggestions.isEmpty { showDefinition() }
            } else if byte == 0x04 {
                break
            } else if byte >= 0x20 && byte < 0x7F {
                let character = Character(UnicodeScalar(byte))
                if input.isEmpty { suggestions = []; selected = 0; definition = nil }
                input.append(character)
                redraw()
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
        out += "\u{001B}[1;36mMaconary\u{001B}[0m\n\n"
        out += "Search word  \u{001B}[1m\(input)▌\u{001B}[0m\n\n"
        if !suggestions.isEmpty {
            out += "\u{001B}[90mBest matches first · green = higher relevance · red = lower relevance\u{001B}[0m\n"
            let rankWidth = 4
            let tableWidth = max(44, min(100, terminalWidth() - 2))
            let wordWidth = max(10, tableWidth - rankWidth - 7)
            let top = "┌" + String(repeating: "─", count: rankWidth + 2) + "┬" + String(repeating: "─", count: wordWidth + 2) + "┐"
            let separator = "├" + String(repeating: "─", count: rankWidth + 2) + "┼" + String(repeating: "─", count: wordWidth + 2) + "┤"
            let bottom = "└" + String(repeating: "─", count: rankWidth + 2) + "┴" + String(repeating: "─", count: wordWidth + 2) + "┘"
            out += "\n\(top)\n"
            out += tableRow("#", word: "Suggestion", rankWidth: rankWidth, wordWidth: wordWidth) + "\n"
            out += "\(separator)\n"
            for (index, suggestion) in suggestions.enumerated() {
                let number = index == selected ? ">\(index + 1)" : " \(index + 1)"
                let coloredWord = "\(colorCode(for: index, count: suggestions.count))\(suggestion.word)\u{001B}[0m"
                out += tableRow(number, word: coloredWord, rankWidth: rankWidth, wordWidth: wordWidth) + "\n"
            }
            out += "\(bottom)\n"
            if let definition {
                out += "\n\u{001B}[1m\(suggestions[selected].word)\u{001B}[0m\n  \(definition)\n"
            }
        }
        out += "\n\u{001B}[90m\(message)\u{001B}[0m\n"
        out += "\u{001B}[90m↑/↓ select · Enter search/show definition · Ctrl+D quit\u{001B}[0m"
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

    private func tableRow(_ rank: String, word: String, rankWidth: Int, wordWidth: Int) -> String {
        let plainWord = stripANSI(word)
        let clippedWord = String(plainWord.prefix(wordWidth))
        let coloredWord = word.hasPrefix("\u{001B}") ? word.replacingOccurrences(of: plainWord, with: clippedWord) : clippedWord
        return "│ \(pad(rank, width: rankWidth, right: true)) │ \(coloredWord)\(String(repeating: " ", count: max(0, wordWidth - clippedWord.count))) │"
    }

    private func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private func pad(_ text: String, width: Int, right: Bool) -> String {
        let clipped = String(text.prefix(width))
        let spaces = String(repeating: " ", count: max(0, width - clipped.count))
        return right ? spaces + clipped : clipped + spaces
    }

    private func terminalWidth() -> Int {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else { return 80 }
        return Int(size.ws_col)
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        return Darwin.read(STDIN_FILENO, &byte, 1) == 1 ? byte : nil
    }
}

var app = App()
app.run()
