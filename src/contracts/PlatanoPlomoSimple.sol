// SPDX-License-Identifier: MIT
// solhint-disable custom-errors
pragma solidity 0.8.23;

import {VRFConsumerBaseV2Plus} from '../../node_modules/@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol';
import {VRFV2PlusClient} from '../../node_modules/@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol';

import {IERC20} from '../../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract PlatanoPlomo is VRFConsumerBaseV2Plus {
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

  bytes32 public keyHash = 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;
  uint32 public callbackGasLimit = 2_500_000;
  uint16 public requestConfirmations = 3;
  uint32 public numWords = 2;
  uint256 public maxBranches = 5;

  // solhint-disable-next-line
  uint256 public s_subscriptionId;
  IERC20 public apeToken;

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

  event RequestSent(uint256 requestId, uint32 numWords);
  event RequestFulfilled(uint256 requestId, uint256[] randomWords);
  event GameCreated(address player, string name);
  event DiceRolled(address player, bool facingRight);
  event PlayerMoved(address player, uint256 newPosition, bool facingRight);
  event BananaShot(address shooter, address target, uint256 newHealth, bool targetDead);
  event GameCompleted(address winner);

  error NextRoundNotPlayable();
  error PlayerNotInGame();
  error NotYourTurn();
  error InternalServerError();

  constructor(
    uint256 _subscriptionId,
    address _apeTokenAddress
  ) VRFConsumerBaseV2Plus(0x5CE8D5A2BC84beb22a398CCA51996F7930313D61) {
    s_subscriptionId = _subscriptionId;
    gameState = GameState.Completed;
    _plataOwner = msg.sender;
    apeToken = IERC20(_apeTokenAddress);
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
    emit GameCreated(msg.sender, _name);
  }

  function rollDice(bool _facingRight) external {
    // Check if the game state is either PendingPlayerOne or PendingPlayerTwo
    if (gameState != GameState.PendingPlayerOne && gameState != GameState.PendingPlayerTwo) {
      revert NextRoundNotPlayable();
    }

    // Check if the caller is either player one or player two
    if (playerOne.player != msg.sender && playerTwo.player != msg.sender) {
      revert PlayerNotInGame();
    }

    // Check if it's player one's turn but not in the PendingPlayerOne state
    if (playerOne.player == msg.sender && gameState == GameState.PendingPlayerOne) {
      stateStored++;
      if (stateStored == 1) {
        playerOne.facingRight = _facingRight;
        gameState = GameState.PendingPlayerTwo;
        emit DiceRolled(msg.sender, _facingRight);
      } else if (stateStored == 2) {
        gameState = GameState.PendingOracle;
        lastRequestId = _vrfRequest();
        stateStored = 0;
      } else {
        revert InternalServerError();
      }
    }
    // Check if it's player two's turn but not in the PendingPlayerTwo state
    else if (playerTwo.player == msg.sender && gameState == GameState.PendingPlayerTwo) {
      stateStored++;
      if (stateStored == 1) {
        playerTwo.facingRight = _facingRight;
        gameState = GameState.PendingPlayerOne;
        emit DiceRolled(msg.sender, _facingRight);
      } else if (stateStored == 2) {
        gameState = GameState.PendingOracle;
        lastRequestId = _vrfRequest();
        stateStored = 0;
      } else {
        revert InternalServerError();
      }
    } else {
      revert NotYourTurn();
    }
  }

  // solhint-disable-next-line
  function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
    require(gameState == GameState.PendingOracle, 'not pending oracle?');
    require(lastRequestId == _requestId, 'wrong request id');
    emit RequestFulfilled(_requestId, _randomWords);
    _completeRound(_randomWords);
  }

  function _completeRound(uint256[] calldata _randomWords) private {
    playerOne.lastDice = _randomWords[0] % 6 + 1;
    playerTwo.lastDice = _randomWords[1] % 6 + 1;

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
        emit BananaShot(_firstPlayer.player, _secondPlayer.player, _secondPlayer.health, isDead);

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
    emit GameCompleted(_winner);
  }

  function _movePlayer(Player storage _player) private {
    uint256 _currentPosition = _player.position;
    uint256 _diceRoll = _player.lastDice;
    bool _newFacingRight = _player.facingRight;

    if (_newFacingRight) {
      if (_currentPosition + _diceRoll < maxBranches) {
        _currentPosition += _diceRoll;
      } else {
        uint256 overflow = _currentPosition + _diceRoll - maxBranches;
        _currentPosition = maxBranches - overflow;
        _newFacingRight = false; // Turn around
      }
    } else {
      if (_currentPosition >= _diceRoll) {
        _currentPosition -= _diceRoll;
      } else {
        uint256 overflow = _diceRoll - _currentPosition;
        _currentPosition = overflow;
        _newFacingRight = true; // Turn around
      }
    }

    _player.facingRight = _newFacingRight;
    _player.position = _currentPosition;
    emit PlayerMoved(_player.player, _currentPosition, _newFacingRight);
  }

  function _vrfRequest() private returns (uint256 _requestId) {
    // Randomisation request
    _requestId = s_vrfCoordinator.requestRandomWords(
      VRFV2PlusClient.RandomWordsRequest({
        keyHash: keyHash,
        subId: s_subscriptionId,
        requestConfirmations: requestConfirmations,
        callbackGasLimit: callbackGasLimit,
        numWords: numWords,
        extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
      })
    );
    emit RequestSent(_requestId, numWords);
    return _requestId;
  }

  function forceEndGame(address _to) public {
    require(msg.sender == _plataOwner, 'not the owner');
    bool success = apeToken.transfer(_to, apeToken.balanceOf(address(this)));
    require(success, 'transfer failed');
  }
}
