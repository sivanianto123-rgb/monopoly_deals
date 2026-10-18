# Monopoly Deal server

Authoritative WebSocket game server. Runs the shared
[`monopoly_deal_engine`](../engine) rules engine and is the only thing that
mutates game state — clients send moves, the server validates them against
the engine and broadcasts the resulting state to everyone in the room.
Nothing here trusts client-submitted game state.

## Running it

```sh
cd server
dart pub get
dart run bin/server.dart --port 8080
```

## Running the tests

```sh
cd server
dart pub get
dart test
```

`test/server_integration_test.dart` spins the real server up in-process on
an ephemeral port and drives it with real `WebSocketChannel` clients —
create a room, join it, start a game, play cards, end a turn, trigger an
illegal-move rejection, and a full Rent-card-vs-Just-Say-No exchange.

## Protocol

One WebSocket connection per client. Every message is a JSON object with a
`type` field.

### Client → server

| `type` | Fields | Notes |
|---|---|---|
| `createRoom` | `playerName` | Creates a room, replies `roomCreated`. |
| `joinRoom` | `roomCode`, `playerName` | Replies `joined`. |
| `startGame` | — | Any player in the room can start it once 2-5 have joined. |
| `move` | `action`, plus action-specific fields (see below) | Only valid once the game has started. |

### `move` actions

These map 1:1 to `TurnEngine` methods in the engine — see
[`engine/lib/src/engine.dart`](../engine/lib/src/engine.dart) for exactly
what each one validates and does. All of them except `playJustSayNo`,
`resolvePendingAction`, and `resolvePayment` can only be sent by whoever's
turn it currently is (`currentPlayerId` in the last `gameState` broadcast).

| `action` | Fields |
|---|---|
| `startTurn` | — |
| `playToBank` | `cardId` |
| `playToProperty` | `cardId`, `chosenColor?` (required for a wildcard) |
| `moveWildcard` | `cardId`, `newColor` |
| `playPassGo` | `cardId` |
| `playHouse` / `playHotel` | `cardId`, `onColor` |
| `playDebtCollector` | `cardId`, `targetPlayerId` |
| `playItsMyBirthday` | `cardId` |
| `playSlyDeal` | `cardId`, `targetPlayerId`, `targetPropertyId` |
| `playForcedDeal` | `cardId`, `targetPlayerId`, `myPropertyId`, `theirPropertyId` |
| `playDealBreaker` | `cardId`, `targetPlayerId`, `targetColor` |
| `playRent` | `cardId`, `colorCharged`, `doubleTheRentCardId?` |
| `playJustSayNo` | `cardId` — only the player named in the current pending action's `nextResponderId` can send this. |
| `resolvePendingAction` | — same `nextResponderId` restriction; finalizes the pending action once nobody wants to play another Just Say No. |
| `resolvePayment` | `cardIds` — the cards being handed over; only the player who actually owes the debt can send this. |
| `endTurn` | `discardCardIds?` — required if the hand is over 7 cards. |

### Server → client

| `type` | When |
|---|---|
| `roomCreated` | Reply to `createRoom`: `roomCode`, `playerId`. |
| `joined` | Reply to `joinRoom`: `roomCode`, `playerId`. |
| `lobby` | Broadcast to the room whenever someone joins, before the game starts: `roomCode`, `players` (`id`/`name` list). |
| `gameState` | Broadcast to the whole room after every successful move (and once when the game starts). Each recipient gets their **own** hand in full and every other player's hand as a count only (`handCount`) — properties, banks, and pending actions/payments are public, same as the physical game. See `gameStateToJson` in the engine for the exact shape. |
| `error` | Sent to **only** the client whose move was rejected, with a human-readable `message`. The room's state is unchanged. |

## Known gaps (next steps)

- No persistence or reconnect/resume: a dropped connection just leaves the
  room (and a server restart drops every in-progress game).
- No auth — `playerName` is self-reported and rooms are joinable by anyone
  who has the code.
- No spectators, rematch, or room cleanup (abandoned rooms live forever in
  memory).
