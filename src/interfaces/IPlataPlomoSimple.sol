// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPlataPlomo {
  enum GameStatus {
    MakingGame,
    PendingPlayer,
    PendingOracle,
    Completed
  }

  struct Weapon {
    uint256 damage;
    uint256 range;
  }

  struct Player {
    uint256 health;
    Weapon weapon;
  }

  struct PlayerState {
    address player;
    uint256 healthRemaining;
    Weapon weapon;
    bool facingRight;
    uint256 position;
  }

  struct Game {
    address winner;
    uint256 round;
    bool player1Turn;
    GameStatus gameStatus;
    uint256 lastRequestId;
    PlayerState player1State;
    PlayerState player2State;
    uint256 maxBranches;
  }

  struct RequestStatus {
    bool fulfilled;
    bool exists;
    uint256[] randomWords;
  }

  event GameCreated(uint256 indexed gameId, address indexed player1);
  event GameStarted(uint256 indexed gameId, address indexed player1, address indexed player2);
  event PlayerJoined(uint256 indexed gameId, address indexed player2);
  event RoundStarted(
    uint256 indexed round, uint256 indexed gameId, address indexed player, bool moveRight, uint256 requestId
  );
  event RoundCompleted(
    uint256 indexed round, uint256 indexed gameId, address indexed player, uint256 requestId, uint256 randomWord
  );
  event GameCompleted(uint256 indexed gameId, address indexed winner);
  event PlayerWounded(uint256 indexed gameId, address indexed player, uint256 healthRemaining);
}
