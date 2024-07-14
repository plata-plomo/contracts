  // SPDX-License-Identifier: MIT
// solhint-disable custom-errors
pragma solidity 0.8.23;

// import {IERC20} from 'forge-std/interfaces/IERC20.sol';

import {ConfirmedOwner} from '@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol';
import {VRFConsumerBaseV2} from '@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol';
import {VRFCoordinatorV2Interface} from '@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol';
import {IPlataPlomo} from 'src/interfaces/IPlataPlomo.sol';

/**
 * @title Greeter Contract
 * @author Wonderland
 * @notice This is a basic contract created in order to portray some
 * best practices and foundry functionality.
 */
contract PlataPlomo is VRFConsumerBaseV2, ConfirmedOwner, IPlataPlomo {
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
  mapping(uint256 => Player) private _playerTypes;
  mapping(uint256 => Game) private _games;
  uint256 public largestGameId;

  constructor(uint64 _subscriptionId) VRFConsumerBaseV2(vrfCoordinator) ConfirmedOwner(msg.sender) {
    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    s_subscriptionId = _subscriptionId;
  }

  function createGame(address _player1, uint256 _playerType) external returns (uint256 _gameId) {
    _gameId = largestGameId++;
    Player memory _player = _playerTypes[_playerType];
    PlayerState memory _player1State = PlayerState(_player1, _player.health, _player.weapon, true, 0);
    PlayerState memory _player2State = PlayerState(address(0), 0, _player.weapon, false, maxBranches - 1);

    _games[_gameId] = Game(address(0), 0, false, GameStatus.MakingGame, 0, _player1State, _player2State, maxBranches);
    return _gameId;
  }

  function joinGame(uint256 _gameId, address _player2, uint256 _playerType) external {
    if (_games[_gameId].player1State.player == _player2) {
      revert('Player is already in the game');
    }
    if (_games[_gameId].player2State.player != address(0)) {
      revert('Game is already full');
    }

    Player memory _player = _playerTypes[_playerType];

    _games[_gameId].player2State.player = _player2;
    _games[_gameId].player2State.weapon = _player.weapon;
    _games[_gameId].player2State.healthRemaining = _player.health;
    _games[_gameId].gameStatus = GameStatus.PendingPlayer;
  }

  function startRound(uint256 _gameId, bool _moveRight) external {
    if (_games[_gameId].gameStatus != GameStatus.PendingPlayer) {
      revert('Next round is not playable');
    }

    if (_games[_gameId].player1State.player != msg.sender || _games[_gameId].player2State.player != msg.sender) {
      revert('Player is not in the game');
    }

    if (
      _games[_gameId].player1State.player == msg.sender && _games[_gameId].player1Turn == false
        || _games[_gameId].player2State.player == msg.sender && _games[_gameId].player1Turn == true
    ) {
      revert('Not your turn');
    }

    _games[_gameId].gameStatus = GameStatus.PendingOracle;
    uint256 _requestId = _vrfRequest();

    s_requests[_requestId] = _gameId;

    emit RoundStarted(_games[_gameId].round, _gameId, msg.sender, _moveRight, _requestId);
  }

  function playerTypes(uint256 playerType) external view returns (Player memory) {
    return _playerTypes[playerType];
  }

  function getOpenGame()
    external
    view
    returns (uint256 _gameId, bool _playerOneExists, bool _playerTwoExists, bool _isPlayerOne)
  {
    for (uint256 i = 1; i <= largestGameId; i++) {
      if (_games[i].gameStatus != GameStatus.Completed) {
        if (msg.sender == _games[i].player1State.player || msg.sender == _games[i].player2State.player) {
          if (msg.sender == _games[i].player1State.player) {
            return (i, true, _games[i].player2State.player != address(0), true);
          } else {
            return (i, _games[i].player1State.player != address(0), true, false);
          }
        }
      }
      if (_games[i].gameStatus == GameStatus.MakingGame) {
        if (_games[i].player1State.player == msg.sender) {
          return (i, false, false, true);
        }
        return (i, true, false, false);
      }
    }

    return (0, false, false, false);
  }

  function games(uint256 gameId) external view override returns (Game memory) {
    return _games[gameId];
  }

  // solhint-disable-next-line
  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
    _completeRound(_requestId, _randomWords[0]);
  }

  function _completeRound(uint256 _requestId, uint256 _randomWord) private returns (uint256 _gameId) {
    _gameId = s_requests[_requestId];
    Game storage _game = _games[_gameId];

    require(_gameId != 0, 'request not found');
    require(_game.gameStatus == GameStatus.PendingOracle, 'Round is not pending oracle');

    uint256 _diceRoll = (_randomWord % 6) + 1;
    PlayerState storage currentPlayer;
    PlayerState storage otherPlayer;

    if (_game.player1Turn) {
      currentPlayer = _game.player1State;
      otherPlayer = _game.player2State;
    } else {
      currentPlayer = _game.player2State;
      otherPlayer = _game.player1State;
    }

    uint256 currentPosition = currentPlayer.position;
    bool facingRight = currentPlayer.facingRight;

    (uint256 newPosition, bool newFacingRight) = _movePlayer(currentPosition, _diceRoll, facingRight);

    // Check if monkeys are facing each other and within range
    if ((facingRight && newPosition < otherPlayer.position) || (!facingRight && newPosition > otherPlayer.position)) {
      uint256 distance =
        newPosition > otherPlayer.position ? newPosition - otherPlayer.position : otherPlayer.position - newPosition;
      if (distance <= currentPlayer.weapon.range) {
        // Apply damage if not on the same position
        if (newPosition != otherPlayer.position) {
          bool isDead = _wound(otherPlayer, currentPlayer.weapon.damage);

          // Check if the other player is dead
          if (isDead) {
            completeGame(_gameId, currentPlayer.player);
            return _gameId;
          }
        }
      }
    }

    currentPlayer.position = newPosition;
    currentPlayer.facingRight = newFacingRight;

    _game.gameStatus = GameStatus.PendingPlayer;
    _game.player1Turn = !_game.player1Turn;

    return _gameId;
  }

  function _wound(PlayerState storage player, uint256 damage) private returns (bool) {
    player.healthRemaining = player.healthRemaining > damage ? player.healthRemaining - damage : 0;
    return player.healthRemaining == 0;
  }

  function completeGame(uint256 _gameId, address winner) private {
    Game storage _game = _games[_gameId];
    _game.gameStatus = GameStatus.Completed;
    _game.winner = winner;
  }

  function _vrfRequest() private returns (uint256 _requestId) {
    // Randomisation request
    _requestId =
      COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);
    return _requestId;
  }

  function _movePlayer(
    uint256 _currentPosition,
    uint256 _diceRoll,
    bool _facingRight
  ) private view returns (uint256 newPosition, bool _newFacingRight) {
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
}
