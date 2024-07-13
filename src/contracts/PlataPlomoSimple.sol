  // SPDX-License-Identifier: MIT
// solhint-disable custom-errors
pragma solidity 0.8.23;

import {ConfirmedOwner} from '@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol';
import {VRFConsumerBaseV2} from '@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol';
import {VRFCoordinatorV2Interface} from '@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol';
import {IERC20} from 'forge-std/interfaces/IERC20.sol';

contract PlataPlomo is VRFConsumerBaseV2, ConfirmedOwner {
  struct Player {
    address player;
    string name;
    uint256 health;
    bool facingRight;
    uint256 position;
    uint256 lastDice;
  }

  enum GameState {
    MakingGame,
    PendingPlayerOne,
    PendingPlayerTwo,
    PendingOracle,
    Completed
  }

  // solhint-disable-next-line
  VRFCoordinatorV2Interface COORDINATOR;
  address public vrfCoordinator = 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61;
  bytes32 public keyHash = 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;
  uint32 public callbackGasLimit = 2_500_000;
  uint16 public requestConfirmations = 3;
  uint32 public numWords = 2;
  uint256 public maxBranches = 5;

  // solhint-disable-next-line
  uint64 public s_subscriptionId;
  IERC20 public apeToken = IERC20(address(0));

  Player public playerOne;
  Player public playerTwo;

  uint256 public entranceFee = 10e18;
  uint256 public initialHealth = 100;
  uint256 public bananaDamage = 40;
  uint256 private stateStored = 0;
  uint256 public lastRequestId;
  uint256 public roundNumber;
  address public _plataOwner;

  GameState public gameState;

  constructor(uint64 _subscriptionId) VRFConsumerBaseV2(vrfCoordinator) ConfirmedOwner(msg.sender) {
    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    s_subscriptionId = _subscriptionId;
    gameState = GameState.Completed;
    _plataOwner = msg.sender;
  }

  function createGame(string memory _name) external {
    bool success = apeToken.transferFrom(msg.sender, address(this), entranceFee);
    require(success, 'erc 20 transfer failed');
    require(gameState == GameState.Completed || gameState == GameState.MakingGame, 'Game already started');
    if (gameState == GameState.Completed) {
      playerOne = Player(msg.sender, _name, initialHealth, true, 0, 0);
      gameState = GameState.MakingGame;
    } else if (gameState == GameState.MakingGame) {
      playerTwo = Player(msg.sender, _name, initialHealth, false, maxBranches - 1, 0);
      gameState = GameState.PendingPlayerOne;
    }
  }

  function rollDice(bool _facingRight) external {
    if (gameState != GameState.PendingPlayerOne || gameState != GameState.PendingPlayerTwo) {
      revert('Next round is not playable');
    }

    if (playerOne.player != msg.sender && playerTwo.player != msg.sender) {
      revert('Player is not in the game');
    }

    if (
      playerOne.player == msg.sender && gameState != GameState.PendingPlayerOne
        || playerTwo.player == msg.sender && gameState != GameState.PendingPlayerTwo
    ) {
      revert('Not your turn');
    }

    if (gameState == GameState.PendingPlayerOne && playerOne.player == msg.sender) {
      if (++stateStored == 1) {
        playerOne.facingRight = _facingRight;
        gameState = GameState.PendingPlayerTwo;
      } else if (++stateStored == 2) {
        gameState = GameState.PendingOracle;
        lastRequestId = _vrfRequest();
        stateStored = 0;
      } else {
        require(false, 'Internal Server Error');
      }
    } else if (gameState == GameState.PendingPlayerTwo && playerTwo.player == msg.sender) {
      if (++stateStored == 1) {
        playerTwo.facingRight = _facingRight;
        gameState = GameState.PendingPlayerOne;
      } else if (++stateStored == 2) {
        gameState = GameState.PendingOracle;
        lastRequestId = _vrfRequest();
        stateStored = 0;
      } else {
        require(false, 'Internal Server Error');
      }
    }
  }

  // solhint-disable-next-line
  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
    require(gameState == GameState.PendingOracle, 'not pending oracle?');
    require(lastRequestId == _requestId, 'wrong request id');
    _completeRound(_randomWords);
  }

  function _completeRound(uint256[] memory _randomWords) private {
    playerOne.lastDice == _randomWords[0] % 6 + 1;
    playerTwo.lastDice == _randomWords[1] % 6 + 1;

    _movePlayer(playerOne);
    _movePlayer(playerTwo);
    if (roundNumber % 2 == 0) {
      _shootBananas(playerOne, playerTwo);
      _shootBananas(playerTwo, playerOne);
      if (gameState != GameState.Completed) {
        gameState = GameState.PendingPlayerOne;
      }
    } else {
      _shootBananas(playerTwo, playerOne);
      _shootBananas(playerOne, playerTwo);
      if (gameState != GameState.Completed) {
        gameState = GameState.PendingPlayerTwo;
      }
    }
    roundNumber++;
  }

  function _shootBananas(Player storage _firstPlayer, Player storage _secondPlayer) private {
    bool facingRight = _firstPlayer.facingRight;
    uint256 firstPlayerPosition = _firstPlayer.position;
    uint256 secondPlayerPosition = _secondPlayer.position;

    // Check if monkeys are facing each other and within range
    if (
      (facingRight && firstPlayerPosition < secondPlayerPosition)
        || (!facingRight && firstPlayerPosition > secondPlayerPosition)
    ) {
      if (firstPlayerPosition != secondPlayerPosition) {
        bool isDead = _wound(_secondPlayer, bananaDamage);

        // Check if the other player is dead
        if (isDead) {
          completeGame(_firstPlayer.player);
        }
      }
    }
  }

  function _wound(Player storage player, uint256 damage) private returns (bool) {
    player.health = player.health > damage ? player.health - damage : 0;
    return player.health == 0;
  }

  function completeGame(address _winner) private {
    gameState = GameState.Completed;
    apeToken.transfer(_winner, apeToken.balanceOf(address(this)));
  }

  function _movePlayer(Player storage _player) private {
    uint256 _currentPosition = _player.position;
    uint256 _newPosition = _player.position;
    bool _newFacingRight = _player.facingRight;
    uint256 _diceRoll = _player.lastDice;

    if (_newFacingRight) {
      unchecked {
        // Using unchecked as the logic ensures we won't exceed maxBranches
        if (_currentPosition + _diceRoll < maxBranches) {
          _newPosition = _currentPosition + _diceRoll;
        } else {
          _newPosition = maxBranches - (_diceRoll - (maxBranches - _currentPosition));
          _newFacingRight = false; // Turn around
        }
      }
    } else {
      unchecked {
        // Using unchecked as the logic ensures we won't go below 0
        if (_currentPosition >= _diceRoll) {
          _newPosition = _currentPosition - _diceRoll;
        } else {
          _newPosition = _diceRoll - _currentPosition;
          _newFacingRight = true; // Turn around
        }
      }
    }

    _player.facingRight = _newFacingRight;
    _player.position = _newPosition;
  }

  function _vrfRequest() private returns (uint256 _requestId) {
    // Randomisation request
    _requestId =
      COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);
    return _requestId;
  }

  function forceEndGame(address _to) public {
    require(msg.sender == _plataOwner, 'not the owner');
    bool success = apeToken.transfer(_to, apeToken.balanceOf(address(this)));
    require(success, 'transfer failed');
  }
}
