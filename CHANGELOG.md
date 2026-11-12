# Changelog

## [1.1.4] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.1.3] - 2026-11-09

### Fixed
- A language tried once in the game's Language menu no longer sticks for
  good: the game follows KOReader's language (French when KOReader is in
  French), and a language picked in the game holds until KOReader's language
  changes. A language picked with an earlier version is forgotten once.

## [1.1.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.1.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.1.0] - 2026-11-03

### Changed
- Cards no longer come back from one game, or one evening, to the next: the
  game remembers the last 3,000 cards played (per language) and deals the
  ones not seen yet first. A card returns only once every card of the chosen
  categories has been played (with Mix, cards older than the last 3,000 may
  come back a little earlier).
- Needs game-common 1.11.0.

## [1.0.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- First release: hold the reader facing the others, guess from their clues.
- Hand-over screen and 3-2-1 countdown before each turn; 30/60/90 s timer that
  refreshes only its own area.
- Found / Pass by tapping with the holder's right / left hand (the screen's
  left / right half as the others see it; can be swapped), or with the
  page-turn buttons.
- End-of-turn summary of the found, passed and missed cards; scores per player
  over 1–5 rounds, final ranking.
- 18 categories (multi-select or Mix): 350+ cards each for the nine general ones
  (Famous people, characters, movies, animals, jobs, places, monuments,
  objects, mimes), 200+ for Mythology & legends, Superheroes & villains,
  Cartoons & comics, Sports legends, Inventions & discoveries, Food & dishes,
  Musical instruments, Famous paintings & sculptures, and Kids (easy) — 5690
  English and 5824 French cards, loaded per category.
