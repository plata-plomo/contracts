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

  function createGame(address player1, uint256 playerType) external returns (uint256 gameId);

  function joinGame(uint256 gameId, address player2, uint256 playerType) external;

  function startRound(uint256 gameId, bool moveRight) external;

  // Public state variables automatically have getter functions
  function vrfCoordinator() external view returns (address);

  function keyHash() external view returns (bytes32);

  function callbackGasLimit() external view returns (uint32);

  function requestConfirmations() external view returns (uint16);

  function numWords() external view returns (uint32);

  function maxBranches() external view returns (uint256);

  function s_subscriptionId() external view returns (uint64);

  function s_requests(uint256 requestId) external view returns (uint256);

  function playerTypes(uint256 playerType) external view returns (Player memory);

  function games(uint256 gameId) external view returns (Game memory);

  function largestGameId() external view returns (uint256);

  function getOpenGame()
    external
    view
    returns (uint256 _gameId, bool _playerOneExists, bool _playerTwoExists, bool _isPlayerOne);
}
