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
  uint256 public maxBranches = 5;

  // solhint-disable-next-line
  uint64 public s_subscriptionId;

  // solhint-disable-next-line
  mapping(uint256 => uint256 _gameId) public s_requests; /* requestId --> gameId */
  mapping(uint256 => Player) public playerTypes;
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

  function createGame(address _player1, uint256 _playerType) external returns (uint256 _gameId) {
    _gameId = largestGameId++;
    Player memory _player = playerTypes[_playerType];
    PlayerState memory _player1State = PlayerState(_player1, _player.health, _player.weapon, true, 0);
    PlayerState memory _player2State = PlayerState(address(0), 0, _player.weapon, false, maxBranches - 1);

    games[_gameId] = Game(address(0), 0, false, GameStatus.MakingGame, 0, _player1State, _player2State, maxBranches);
    return _gameId;
  }

  function joinGame(uint256 _gameId, address _player2, uint256 _playerType) external {
    if (games[_gameId].player1State.player == _player2) {
      revert('Player is already in the game');
    }
    if (games[_gameId].player2State.player != address(0)) {
      revert('Game is already full');
    }

    Player memory _player = playerTypes[_playerType];

    games[_gameId].player2State.player = _player2;
    games[_gameId].player2State.weapon = _player.weapon;
    games[_gameId].player2State.healthRemaining = _player.health;
    games[_gameId].gameStatus = GameStatus.PendingPlayer;
  }

  function startRound(uint256 _gameId, bool _moveRight) external {
    if (games[_gameId].gameStatus != GameStatus.PendingPlayer) {
      revert('Next round is not playable');
    }

    if (games[_gameId].player1State.player != msg.sender || games[_gameId].player2State.player != msg.sender) {
      revert('Player is not in the game');
    }

    if (
      games[_gameId].player1State.player == msg.sender && games[_gameId].player1Turn == false
        || games[_gameId].player2State.player == msg.sender && games[_gameId].player1Turn == true
    ) {
      revert('Not your turn');
    }

    games[_gameId].gameStatus = GameStatus.PendingOracle;
    uint256 _requestId = _vrfRequest();

    s_requests[_requestId] = _gameId;

    emit RoundStarted(games[_gameId].round, _gameId, msg.sender, _moveRight, _requestId);
  }

  // solhint-disable-next-line
  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
    uint256 _gameId = _completeRound(_requestId, _randomWords[0]);
    _completeGame(_gameId);
  }

  function _completeGame(uint256 _gameId) private {}

  function _movePlayer(
    uint256 _currentPosition,
    uint256 _diceRoll,
    bool _facingRight
  ) private returns (uint256 newPosition, bool _newFacingRight) {
    newPosition = _currentPosition;
    _newFacingRight = _facingRight;

    if (_facingRight) {
      unchecked {
        // Using unchecked as the logic ensures we won't exceed maxBranches
        if (_currentPosition + _diceRoll < maxBranches) {
          newPosition = _currentPosition + _diceRoll;
        } else {
          newPosition = maxBranches - (_diceRoll - (maxBranches - _currentPosition));
          _newFacingRight = false; // Turn around
        }
      }
    } else {
      unchecked {
        // Using unchecked as the logic ensures we won't go below 0
        if (_currentPosition >= _diceRoll) {
          newPosition = _currentPosition - _diceRoll;
        } else {
          newPosition = _diceRoll - _currentPosition;
          _newFacingRight = true; // Turn around
        }
      }
    }

    return (newPosition, _newFacingRight);
  }

  function _completeRound(uint256 _requestId, uint256 _randomWord) private returns (uint256 _gameId) {
    _gameId = s_requests[_requestId];
    Game storage _game = games[_gameId];

    require(_gameId != 0, 'request not found');
    require(_game.gameStatus == GameStatus.PendingOracle, 'Round is not pending oracle');

    uint256 _diceRoll = (_randomWord % 6) + 1;
    uint256 currentPosition;
    bool facingRight;
    if (_game.player1Turn) {
      currentPosition = _game.player1State.position;
      facingRight = _game.player1State.facingRight;
    } else {
      currentPosition = _game.player2State.position;
      facingRight = _game.player2State.facingRight;
    }

    (uint256 newPosition, bool newFacingRight) = _movePlayer(currentPosition, _diceRoll, facingRight);

    if (_game.player1Turn) {
      uint256 otherPosition = _game.player2State.position;
    } else {
      _game.player2State.position = newPosition;
      _game.player2State.facingRight = newFacingRight;
    }

    games[_gameId].gameStatus = GameStatus.PendingPlayer;

    games[_gameId].player1Turn = !games[_gameId].player1Turn;

    return _gameId;
  }

  function _vrfRequest() private returns (uint256 _requestId) {
    // Randomisation request
    _requestId =
      COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);
    return _requestId;
  }
}
