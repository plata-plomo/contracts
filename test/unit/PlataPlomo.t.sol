// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import 'forge-std/Test.sol';
import 'src/contracts/PlataPlomo.sol';

contract PlataPlomoTest is Test {
  PlataPlomo public plataPlomo;

  address vrfCoordinator = 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61;
  bytes32 keyHash = 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;
  uint64 subscriptionId = 1;

  function setUp() public {
    plataPlomo = new PlataPlomo(subscriptionId);
  }

  function test_Constructor() public {
    assertEq(plataPlomo.vrfCoordinator(), vrfCoordinator);
    assertEq(plataPlomo.keyHash(), keyHash);
    assertEq(plataPlomo.callbackGasLimit(), 2_500_000);
    assertEq(plataPlomo.requestConfirmations(), 3);
    assertEq(plataPlomo.numWords(), 1);
    assertEq(plataPlomo.maxBranches(), 5);
    assertEq(plataPlomo.s_subscriptionId(), subscriptionId);
    assertEq(plataPlomo.owner(), address(this));
  }
}
