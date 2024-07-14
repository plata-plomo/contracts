Thanks to Wonderland for the cool Foundry Boilerplate :)

# PlatanoPlomo

PlatanoPlomo is a smart contract game where two players roll dice and shoot bananas at each other. The game uses Chainlink VRF (Verifiable Random Function) for random number generation.

## How to Play

1. **Join the Game**: Players join by calling `createGame` and paying an entrance fee.
2. **Roll Dice**: Players take turns rolling dice using `rollDice`.
3. **Move and Shoot**: Players move and shoot bananas at each other based on their dice rolls.
4. **Win**: The game continues until one player's health reaches zero.

## Contract Details

### Player Structure

- `player`: Player's address
- `name`: Player's name
- `health`: Player's health
- `facingRight`: Direction the player is facing
- `position`: Player's position
- `lastDice`: Last dice roll value

### Game States

- `MakingGame`: Setting up the game
- `PendingPlayerOne`: Waiting for player one to roll
- `PendingPlayerTwo`: Waiting for player two to roll
- `PendingOracle`: Waiting for random number from Chainlink VRF
- `Completed`: Game is over

## Functions

### createGame

Join the game by paying the entrance fee.

```solidity
function createGame(string memory _name) external
```

### rollDice
Roll the dice and update your direction.

```solidity
function rollDice(bool _facingRight) external
```

### fulfillRandomWords
Callback for Chainlink VRF to complete the round.

```solidity
function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override
```

### forceEndGame

Forcefully end the game and transfer the prize to a specified address (owner only).

```solidity
function forceEndGame(address _to) public
```

## Custom Errors
NextRoundNotPlayable(): Thrown when the game state is not suitable for starting the next round.
PlayerNotInGame(): Thrown when a non-player tries to roll the dice.
NotYourTurn(): Thrown when a player tries to roll the dice out of turn.
InternalServerError(): Thrown when an unexpected state is encountered.

### Events

// Emitted when a player joins the game.
event GameCreated(address player, string name);

// Emitted when a player rolls the dice.
event DiceRolled(address player, uint256 diceValue, bool facingRight);

// Emitted when a player moves to a new position.
event PlayerMoved(address player, uint256 newPosition, bool facingRight);

// Emitted when a player shoots a banana at another player.
event BananaShot(address shooter, address target, uint256 newHealth, bool targetDead);

// Emitted when the game is completed.
event GameCompleted(address winner);

## Deployment
Deploy the contract with:

solidity
```solidity
constructor(uint256 _subscriptionId, address _apeTokenAddress)
```

## Features

<dl>
  <dt>Sample contracts</dt>
  <dd>Basic Greeter contract with an external interface.</dd>

  <dt>Foundry setup</dt>
  <dd>Foundry configuration with multiple custom profiles and remappings.</dd>

  <dt>Deployment scripts</dt>
  <dd>Sample scripts to deploy contracts on both mainnet and testnet.</dd>

  <dt>Sample Integration, Unit, Property-based fuzzed and symbolic tests</dt>
  <dd>Example tests showcasing mocking, assertions and configuration for mainnet forking. As well it includes everything needed in order to check code coverage.</dd>
  <dd>Unit tests are built based on the <a href="https://twitter.com/PaulRBerg/status/1682346315806539776">Branched-Tree Technique</a>, using <a href="https://github.com/alexfertel/bulloak">Bulloak</a>.
  <dd>Formal verification and property-based fuzzing are achieved with <a href="https://github.com/a16z/halmos">Halmos</a> and <a href="https://github.com/crytic/echidna">Echidna</a> (resp.).

  <dt>Linter</dt>
  <dd>Simple and fast solidity linting thanks to forge fmt.</dd>
  <dd>Find missing natspec automatically.</dd>

  <dt>Github workflows CI</dt>
  <dd>Run all tests and see the coverage as you push your changes.</dd>
  <dd>Export your Solidity interfaces and contracts as packages, and publish them to NPM.</dd>
</dl>

## Setup

1. Install Foundry by following the instructions from [their repository](https://github.com/foundry-rs/foundry#installation).
2. Copy the `.env.example` file to `.env` and fill in the variables.
3. Install the dependencies by running: `yarn install`. In case there is an error with the commands, run `foundryup` and try them again.

## Build

The default way to build the code is suboptimal but fast, you can run it via:

```bash
yarn build
```

In order to build a more optimized code ([via IR](https://docs.soliditylang.org/en/v0.8.15/ir-breaking-changes.html#solidity-ir-based-codegen-changes)), run:

```bash
yarn build:optimized
```

## Running tests

Unit tests should be isolated from any externalities, while Integration usually run in a fork of the blockchain. In this boilerplate you will find example of both.

In order to run both unit and integration tests, run:

```bash
yarn test
```

In order to check your current code coverage, run:

```bash
yarn coverage
```

<br>

## Deploy & verify

### Setup

Configure the `.env` variables.

### Sepolia

```bash
yarn deploy:sepolia
```

### Mainnet

```bash
yarn deploy:mainnet
```

The deployments are stored in ./broadcast

See the [Foundry Book for available options](https://book.getfoundry.sh/reference/forge/forge-create.html).

## Licensing
The primary license for the boilerplate is MIT, see [`LICENSE`](https://github.com/defi-wonderland/solidity-foundry-boilerplate/blob/main/LICENSE)