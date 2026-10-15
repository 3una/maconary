# dictionary

A lightweight macOS terminal thesaurus. It finds English synonyms using the public [Datamuse API](https://www.datamuse.com/api/) and can show definitions from [Free Dictionary API](https://dictionaryapi.dev/).

## Install

Requires macOS 13 or later and Apple's Swift command-line tools. Install from Terminal with:

```sh
curl -fsSL https://raw.githubusercontent.com/3una/dictionary/main/install.sh | sh
```

The binary installs to `~/.local/bin/dictionary`. Add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc` if that directory is not already on your PATH. Then run:

```sh
dictionary
```

If Swift is missing, install Apple's command-line tools with `xcode-select --install`, then run the install command again.

## Use

- Press **d** to toggle word entry on or off.
- Type a word and press **Return** for synonym suggestions.
- Use **↑ / ↓** to move through suggestions. Results are sorted by the API's relevance score; colors run from green (higher ranked) to red (lower ranked).
- Press **Return** with a suggestion selected to fetch its definition.
- Press **q** to quit, or **Ctrl+D** to quit from anywhere.

The suggestions are relevance-ranked alternatives, not a guarantee that a word is better in every sentence. Datamuse and Free Dictionary API are public services, so an internet connection is required.

## Build from source

```sh
swift build -c release
```

