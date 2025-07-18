// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ZkBaseTest} from "test/helpers/ZkBaseTest.t.sol";
import {ZkMinterDelayV1, MintRequest} from "src/ZkMinterDelayV1.sol";
import {ZkMinterDelayV1Factory} from "src/ZkMinterDelayV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkCappedMinterV2} from "lib/zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title ZkMinterDelayV1Integration
/// @notice Integration tests for ZkMinterDelayV1 with zk token and capped minter
contract ZkMinterDelayV1Integration is ZkBaseTest {
  ZkMinterDelayV1 public delayMinter;
  ZkMinterDelayV1Factory public delayFactory;

  address minter = makeAddr("minter");
  address recipient = makeAddr("recipient");

  uint48 constant DELAY_PERIOD = 3600; // 1 hour
  uint256 constant MINT_AMOUNT = 1000e18;

  function setUp() public override {
    super.setUp();

    // Read the bytecode hash from the JSON file
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/zkout/ZkMinterDelayV1.sol/ZkMinterDelayV1.json");
    string memory json = vm.readFile(path);
    bytes32 bytecodeHash = bytes32(stdJson.readBytes(json, ".hash"));

    // Deploy the factory with the bytecode hash
    delayFactory = new ZkMinterDelayV1Factory(bytecodeHash);

    // Deploy delay minter using factory
    uint256 saltNonce = 1; // Use a unique salt nonce
    delayMinter =
      ZkMinterDelayV1(delayFactory.createMinter(IMintable(address(cappedMinter)), admin, DELAY_PERIOD, saltNonce));

    // Grant minter role to the delay minter
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(delayMinter));

    // Grant minter role to a test minter
    vm.startPrank(admin);
    delayMinter.grantRole(delayMinter.MINTER_ROLE(), minter);
    vm.stopPrank();

    vm.label(address(delayFactory), "DelayFactory");
    vm.label(address(delayMinter), "DelayMinter");
  }

  function test_Simple_DelayMintingFlow() public {
    uint256 initialBalance = token.balanceOf(recipient);
    uint256 initialTotalSupply = token.totalSupply();

    // Step 1: Create a mint request
    vm.prank(minter);
    delayMinter.mint(recipient, MINT_AMOUNT);

    uint256 requestId = 0; // First request
    MintRequest memory request = delayMinter.getMintRequest(requestId);

    assertEq(request.minter, minter);
    assertEq(request.to, recipient);
    assertEq(request.amount, MINT_AMOUNT);
    assertEq(request.executed, false);
    assertEq(request.cancelled, false);

    // Step 2: Try to execute before delay (should fail)
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintRequestNotReady.selector, requestId));
    delayMinter.executeMint(requestId);

    // Verify no tokens were minted
    assertEq(token.balanceOf(recipient), initialBalance);
    assertEq(token.totalSupply(), initialTotalSupply);

    // Step 3: Fast forward past the delay period
    vm.warp(block.timestamp + DELAY_PERIOD + 1);

    // Step 4: Execute the mint request
    delayMinter.executeMint(requestId);

    // Verify tokens were minted
    assertEq(token.balanceOf(recipient), initialBalance + MINT_AMOUNT);
    assertEq(token.totalSupply(), initialTotalSupply + MINT_AMOUNT);

    // Verify request is marked as executed
    request = delayMinter.getMintRequest(requestId);
    assertTrue(request.executed);
  }

  function test_Integration_AdminCancellation() public {
    // Create a mint request
    vm.prank(minter);
    delayMinter.mint(recipient, MINT_AMOUNT);

    uint256 requestId = 0;

    // Admin cancels the request
    vm.prank(admin);
    delayMinter.cancelMintRequest(requestId);

    // Fast forward past delay
    vm.warp(block.timestamp + DELAY_PERIOD + 1);

    // Try to execute cancelled request (should fail)
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintRequestCancelled.selector, requestId));
    delayMinter.executeMint(requestId);
  }

  function test_Integration_DelayUpdate() public {
    // Create a mint request
    vm.prank(minter);
    delayMinter.mint(recipient, MINT_AMOUNT);

    uint256 requestId = 0;

    // Admin updates the delay to be longer
    uint48 newDelay = DELAY_PERIOD * 2;
    vm.prank(admin);
    delayMinter.updateMintDelay(newDelay);

    // Try to execute after original delay (should fail)
    vm.warp(block.timestamp + DELAY_PERIOD + 1);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintRequestNotReady.selector, requestId));
    delayMinter.executeMint(requestId);

    // Wait for new delay period
    vm.warp(block.timestamp + DELAY_PERIOD);

    // Now it should work
    delayMinter.executeMint(requestId);
  }

  function test_Integration_MultipleRequests() public {
    address recipient1 = makeAddr("recipient1");
    address recipient2 = makeAddr("recipient2");

    // Create multiple requests
    vm.prank(minter);
    delayMinter.mint(recipient1, MINT_AMOUNT);

    vm.prank(minter);
    delayMinter.mint(recipient2, MINT_AMOUNT * 2);

    // Fast forward past delay
    vm.warp(block.timestamp + DELAY_PERIOD + 1);

    // Execute both requests
    delayMinter.executeMint(0);
    delayMinter.executeMint(1);

    // Verify both were executed
    assertEq(token.balanceOf(recipient1), MINT_AMOUNT);
    assertEq(token.balanceOf(recipient2), MINT_AMOUNT * 2);
  }

  function test_Integration_PauseAndResume() public {
    // Create a mint request
    vm.prank(minter);
    delayMinter.mint(recipient, MINT_AMOUNT);

    uint256 requestId = 0;

    // Pause the delay minter
    vm.prank(admin);
    delayMinter.pause();

    // Try to create new request (should fail)
    vm.prank(minter);
    vm.expectRevert("Pausable: paused");
    delayMinter.mint(recipient, MINT_AMOUNT);

    // Try to execute existing request (should fail)
    vm.warp(block.timestamp + DELAY_PERIOD + 1);
    vm.expectRevert("Pausable: paused");
    delayMinter.executeMint(requestId);

    // Unpause
    vm.prank(admin);
    delayMinter.unpause();

    // Now execution should work
    delayMinter.executeMint(requestId);
  }

  function test_Integration_CloseContract() public {
    // Create a mint request
    vm.prank(minter);
    delayMinter.mint(recipient, MINT_AMOUNT);

    uint256 requestId = 0;

    // Close the contract
    vm.prank(admin);
    delayMinter.close();

    // Try to create new request (should fail)
    vm.prank(minter);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterV1.ZkMinter__ContractClosed.selector));
    delayMinter.mint(recipient, MINT_AMOUNT);

    // Try to execute existing request (should fail)
    vm.warp(block.timestamp + DELAY_PERIOD + 1);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterV1.ZkMinter__ContractClosed.selector));
    delayMinter.executeMint(requestId);
  }
}
