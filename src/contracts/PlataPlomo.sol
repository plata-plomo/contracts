// SPDX-License-Identifier: MIT
// solhint-disable custom-errors
pragma solidity 0.8.23;

// import {IERC20} from 'forge-std/interfaces/IERC20.sol';

import {ConfirmedOwner} from '@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol';
import {VRFConsumerBaseV2} from '@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol';
import {VRFCoordinatorV2Interface} from '@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol';

/**
 * @title Greeter Contract
 * @author Wonderland
 * @notice This is a basic contract created in order to portray some
 * best practices and foundry functionality.
 */
contract PlataPlomo is VRFConsumerBaseV2, ConfirmedOwner {
  enum GameStatus {
    PendingPlayer,
    PendingOracle,
    Completed
  }

  struct Weapon {
    uint256 damage;
    uint256 range;
  }

  struct Player {
    address player;
    uint256 health;
    Weapon weapon;
  }

  struct Game {
    address winner;
    uint256 round;
    bool player1Turn;
    GameStatus makeTurn;
    uint256 lastRequestId;
    Player player1;
    Player player2;
    uint256[] stones;
  }

  struct RequestStatus {
    bool fulfilled; // whether the request has been successfully fulfilled
    bool exists; // whether a requestId exists
    uint256[] randomWords;
  }

  // solhint-disable-next-line
  VRFCoordinatorV2Interface COORDINATOR;
  address public vrfCoordinator = 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61;
  bytes32 public keyHash = 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;
  uint32 public callbackGasLimit = 2_500_000;
  uint16 public requestConfirmations = 3;
  uint32 public numWords = 1;

  // solhint-disable-next-line
  uint64 public s_subscriptionId;

  // solhint-disable-next-line
  mapping(uint256 => uint256 _gameId) public s_requests; /* requestId --> gameId */
  mapping(address => Player) public players;
  mapping(uint256 => Game) public games;
  uint256 public largestGameId;

  event GameCreated(uint256 _gameId, address _player1);
  event GameStarted(uint256 _gameId, address _player1, address _player2);
  event RoundStarted(uint256 round, uint256 _gameId, address _player, bool _moveRight, uint256 requestId);
  event RoundCompleted(uint256 round, uint256 _gameId, address _player, uint256 requestId, uint256 randomWord);

  constructor(uint64 _subscriptionId) VRFConsumerBaseV2(vrfCoordinator) ConfirmedOwner(msg.sender) {
    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    s_subscriptionId = _subscriptionId;
  }

  function createGame(address _player1) external returns (uint256 _gameId) {
    _gameId = largestGameId++;
    games[_gameId].player1 = players[_player1];
    return _gameId;
  }

  function joinGame(uint256 _gameId, address _player2) external {
    if (games[_gameId].player1.player == _player2) {
      revert('Player is already in the game');
    }
    if (games[_gameId].player2.player != address(0)) {
      revert('Game is already full');
    }

    games[_gameId].player2 = players[_player2];
    games[_gameId].makeTurn = GameStatus.PendingPlayer;
  }

  function makeTurn(uint256 _gameId, bool _moveRight) external {
    if (games[_gameId].makeTurn != GameStatus.PendingPlayer) {
      revert('Next round is not playable');
    }

    if (games[_gameId].player1.player != msg.sender && games[_gameId].player2.player != msg.sender) {
      revert('Player is not in the game');
    }

    if (
      games[_gameId].player1.player == msg.sender && games[_gameId].player1Turn == false
        || games[_gameId].player2.player == msg.sender && games[_gameId].player1Turn == true
    ) {
      revert('Not your turn');
    }

    games[_gameId].player1Turn = !games[_gameId].player1Turn;
    games[_gameId].makeTurn = GameStatus.PendingOracle;
    uint256 _requestId = _vrfRequest();

    s_requests[_requestId] = _gameId;

    emit RoundStarted(games[_gameId].round, _gameId, msg.sender, _moveRight, _requestId);
  }

  // solhint-disable-next-line
  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
    _completeTurn(_requestId, _randomWords[0]);
  }

  function _completeTurn(uint256 _requestId, uint256 _randomWord) private {
    uint256 _gameId = s_requests[_requestId];
    require(_gameId != 0, 'request not found');
    require(games[_gameId].makeTurn == GameStatus.PendingOracle, 'Round is not pending oracle');

    games[_gameId].makeTurn = GameStatus.PendingPlayer;

    emit RoundCompleted(games[_gameId].round, _gameId, msg.sender, _requestId, _randomWord);
  }

  function _vrfRequest() private returns (uint256 _requestId) {
    // Randomisation request
    _requestId =
      COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);

    return _requestId;
  }
}
