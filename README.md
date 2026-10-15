# Maconary

A lightweight macOS terminal thesaurus. It finds English synonyms using the public [Datamuse API](https://www.datamuse.com/api/) and can show definitions from [Free Dictionary API](https://dictionaryapi.dev/).

## Install

Requires macOS 13 or later and Apple's Swift command-line tools. Install from Terminal with:

```sh
curl -fsSL https://raw.githubusercontent.com/3una/maconary/main/install.sh | sh
```

The binary installs to `~/.local/bin/maconary`. The installer adds that folder to your shell profile when needed. Open a new Terminal window, then run:

```sh
maconary
```

If Swift is missing, install Apple's command-line tools with `xcode-select --install`, then run the install command again.

## Use

- Type a word and press **Return** for synonym suggestions.
- Use **↑ / ↓** to move through the table. Results are sorted by API relevance; colors run from green (higher ranked) to red (lower ranked).
- Press **Return** with a suggestion selected to fetch its definition.
- Press **Ctrl+D** to quit.

## Privacy

Maconary sends the word you enter to the public Datamuse API to find synonyms. When you request a definition, it sends the selected suggestion to Free Dictionary API. Maconary does not save searches or send analytics. Those services receive the requests and may process your IP address and query under their own privacy policies.

The suggestions are relevance-ranked alternatives, not a guarantee that a word is better in every sentence. Datamuse and Free Dictionary API are public services, so an internet connection is required.

## Build from source

```sh
swift build -c release
```

