# Monopoly Deal

A Monopoly Deal app for iOS and Android with online multiplayer.

## Architecture

- **`engine/`** — pure Dart package with the rules engine (cards, deck,
  game state, turn logic, action-card effects). No UI, no networking.
  Shared by both the client and the server so the rules only exist in one
  place.
- **`app/`** — Flutter client (iOS + Android).
- **`server/`** — Dart WebSocket backend (room/lobby management,
  authoritative game state, move validation). Depends on `engine/` as a
  path dependency, same as `app/` will.

Using Dart end-to-end (engine + server) means the client and server never
have two separate reimplementations of the rules to keep in sync.

## Status

Built so far, in `engine/`:
- Full 108-card deck (money, properties, property wildcards, rent cards,
  action cards) with exact official counts/values.
- Game state (players, hands, banks, in-play property sets, draw/discard
  piles).
- Basic turn flow: deal, draw 2, play up to 3 cards/turn (to bank or to a
  property set), move wildcards between colors, discard to the 7-card hand
  limit, win detection (3 complete property sets).
- All 10 action card effects: Pass Go, House, Hotel (instant); Sly Deal,
  Forced Deal, Deal Breaker, Debt Collector, It's My Birthday, Rent (+
  Double The Rent) go through a `PendingAction` queue so the target can
  respond with Just Say No (chainable — the original player can counter)
  before anything resolves. Debt Collector/Birthday/Rent turn into a
  `PendingPayment`, settled via `resolvePayment` (bank cards first, falling
  back to surrendering properties, including "give everything you have"
  when the payer can't fully cover it). `endTurn()` refuses to run while
  anything is still pending.
- JSON serialization (`cardToJson`/`cardFromJson`, `gameStateToJson`) with
  a per-viewer game state view that hides other players' hand contents.
- 38 passing tests, clean `dart analyze`.

Built so far, in `server/`:
- A room/lobby system (create/join by code, 2-5 players) and a WebSocket
  protocol that maps 1:1 onto the engine's `TurnEngine` methods — the
  server is authoritative, validates every move, and broadcasts a
  per-player `gameState` after each one. See `server/README.md` for the
  full protocol.
- 3 end-to-end integration tests driving the real server over real
  `WebSocketChannel` connections (create/join/start/play/end-turn, illegal
  moves getting rejected to just the sender, and a full Rent-card-vs-Just-
  Say-No exchange).

Built so far, in `app/`:
- A Flutter client (iOS + Android project scaffolding) using `provider`
  for state management and `web_socket_channel` to speak the server's
  protocol directly — no mocking layer, it's the same wire format
  `server/README.md` documents.
- Screens: connect (pick a server, create/join a room), lobby (player
  list, start game), and the game table (hand, property sets grouped by
  color with house/hotel indicators, opponents' hand counts and bank
  totals, draw/discard piles, turn indicator).
- Card rendering for all 5 card kinds (money, property, property
  wildcard, rent, action), visually distinct the way the physical cards
  are.
- A full play/response flow: tapping a card in hand offers the moves that
  make sense for it (bank it, place it, or its special action), including
  nested pickers for actions that need a target player/property/color
  (Sly Deal, Forced Deal, Deal Breaker, Rent + Double The Rent, Debt
  Collector, It's My Birthday, House/Hotel). Pending actions targeting you
  surface a Just-Say-No-or-accept banner; a pending payment you owe opens
  a card picker (bank first, properties if needed) before it'll let you
  confirm.
- 9 passing tests (widget + model-parsing), clean `flutter analyze`.
- Verified end-to-end in a real browser (via a Flutter web build used only
  for this local check — the shipped app targets iOS/Android) against the
  real server: two simulated players connect, create/join a room, see the
  lobby update live, start a game, see their own hand in full and the
  other player's hand as a count only, draw, and end their turn with the
  turn correctly rotating.

Not yet implemented:
- Reconnect/resume, persistence, auth — see "Known gaps" in
  `server/README.md`.
- Haven't built/run on an actual iOS or Android device or emulator (this
  environment has neither Xcode nor the Android SDK) — the widget tests,
  `flutter analyze`, and the browser-based end-to-end check are what's
  been verified so far.

## Running the tests

```sh
cd engine && dart pub get && dart test
cd ../server && dart pub get && dart test
cd ../app && flutter pub get && flutter analyze && flutter test
```

## Running the app

```sh
cd server && dart pub get && dart run bin/server.dart --port 8080
# in another terminal, on a device/simulator with the Flutter SDK installed:
cd app && flutter pub get && flutter run
```
Enter the server's address (e.g. `localhost:8080`, or your machine's LAN
IP if running on a physical device) on the connect screen.

## Deck reference

Source: https://monopolydealrules.com/index.php?page=play (official counts
confirmed from that page's photographed cards, Oct 2026). One discrepancy
worth noting: that page's "34 Action Cards" section header doesn't match
the sum of the per-card counts it lists right below it (2+3+3+4+3+3+10+3+3+2
= 36). The engine uses the itemized per-card counts (36), since those are
individually tied to named cards; this makes the full deck 108 cards
rather than the site's stated 106. If you can confirm which number is the
typo, update `engine/lib/src/deck.dart` and the counts in
`engine/README` references accordingly.

Red, Yellow, and Utility property prices/rents use the standard published
values (the source page's screenshots cut off before showing those three
colors) rather than a screenshot-confirmed source — everything else was
read directly off photographed cards.
