// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkBaseTest} from "test/helpers/ZkBaseTest.t.sol";
import {ZkMinterDelayV1, MintRequest} from "src/ZkMinterDelayV1.sol";
import {ZkMinterDelayV1Factory} from "src/ZkMinterDelayV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title ZkMinterDelayV1Integration
/// @notice Integration tests for ZkMinterDelayV1 with zk token and capped minter
contract ZkMinterDelayV1Integration is ZkBaseTest {
  ZkMinterDelayV1 public delayMinter;
  ZkMinterDelayV1Factory public delayFactory;

  address minter = makeAddr("minter");
  address recipient = makeAddr("recipient");

  function setUp() public override {
    (string memory rpcUrl, uint256 forkBlock) = _getForkConfig();
    vm.createSelectFork(rpcUrl, forkBlock);

    super.setUp();

    // Read the bytecode hash from the JSON file
    string memory _root = vm.projectRoot();
    string memory _path = string.concat(_root, "/zkout/ZkMinterDelayV1.sol/ZkMinterDelayV1.json");
    string memory _json = vm.readFile(_path);
    bytes32 bytecodeHash = bytes32(stdJson.readBytes(_json, ".hash"));

    // Deploy the factory with the bytecode hash
    delayFactory = new ZkMinterDelayV1Factory(bytecodeHash);

    vm.label(address(delayFactory), "DelayFactory");
  }

  function _setupDelayMinter(uint48 _delay, uint256 _saltNonce) internal {
    delayMinter =
      ZkMinterDelayV1(delayFactory.createMinter(IMintable(address(cappedMinter)), admin, _delay, _saltNonce));

    // Grant minter role to the delay minter
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(delayMinter));

    // Grant minter role to a test minter
    vm.startPrank(admin);
    delayMinter.grantRole(delayMinter.MINTER_ROLE(), minter);
    vm.stopPrank();

    vm.label(address(delayMinter), "DelayMinter");
  }

  function testFuzz_ExecutesMintAfterDelayPeriod(address _recipient, uint256 _amount, uint48 _delay, uint256 _saltNonce)
    public
  {
    _assumeSafeAddress(_recipient);
    _amount = _boundToRealisticAmount(_amount);
    _assumeSafeUint(_delay);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Ensure the delay doesn't exceed the capped minter's expiration time
    vm.assume(_delay < cappedMinter.EXPIRATION_TIME() - block.timestamp);

    // Deploy a new delay minter with fuzzed delay
    _setupDelayMinter(_delay, _saltNonce);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    // Step 1: Create a mint request
    vm.prank(minter);
    delayMinter.mint(_recipient, _amount);

    uint256 requestId = 1; // First request
    MintRequest memory request = delayMinter.getMintRequest(requestId);

    assertEq(request.minter, minter);
    assertEq(request.to, _recipient);
    assertEq(request.amount, _amount);
    assertEq(request.executed, false);
    assertEq(request.vetoed, false);

    // Step 2: Try to execute before delay (should fail)
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintRequestNotReady.selector, requestId));
    delayMinter.executeMint(requestId);

    // Verify no tokens were minted
    assertEq(token.balanceOf(_recipient), initialBalance);
    assertEq(token.totalSupply(), initialTotalSupply);

    // Step 3: Fast forward past the delay period
    vm.warp(block.timestamp + _delay + 1);

    // Step 4: Execute the mint request
    delayMinter.executeMint(requestId);

    // Verify tokens were minted
    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);

    // Verify request is marked as executed
    request = delayMinter.getMintRequest(requestId);
    assertTrue(request.executed);
  }

  function testFuzz_RevertIf_ExecutingVetoedMintRequest(
    address _recipient,
    uint256 _amount,
    uint48 _delay,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    _amount = _boundToRealisticAmount(_amount);
    _assumeSafeUint(_delay);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Ensure the delay doesn't exceed the capped minter's expiration time
    vm.assume(_delay < cappedMinter.EXPIRATION_TIME() - block.timestamp);

    // Deploy a new delay minter with fuzzed delay
    _setupDelayMinter(_delay, _saltNonce);

    // Create a mint request
    vm.prank(minter);
    delayMinter.mint(_recipient, _amount);

    uint256 _requestId = 1;

    // Admin vetoes the request
    vm.prank(admin);
    delayMinter.vetoMintRequest(_requestId);

    // Fast forward past delay
    vm.warp(block.timestamp + _delay + 1);

    // Try to execute vetoed request (should fail)
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintRequestVetoed.selector, _requestId));
    delayMinter.executeMint(_requestId);
  }

  function testFuzz_ExecutesMintAfterUpdatedDelayPeriod(
    address _recipient,
    uint256 _amount,
    uint48 _delay,
    uint48 _newDelay,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    _amount = _boundToRealisticAmount(_amount);
    _assumeSafeUint(_delay);
    _assumeSafeUint(_newDelay);
    vm.assume(_newDelay > _delay); // Ensure new delay is longer

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Ensure both delays don't exceed the capped minter's expiration time
    vm.assume(_delay < cappedMinter.EXPIRATION_TIME() - block.timestamp);
    vm.assume(_newDelay < cappedMinter.EXPIRATION_TIME() - block.timestamp);

    // Deploy a new delay minter with fuzzed delay
    _setupDelayMinter(_delay, _saltNonce);

    // Create a mint request
    vm.prank(minter);
    delayMinter.mint(_recipient, _amount);

    uint256 requestId = 1;

    // Admin updates the delay to be longer
    vm.prank(admin);
    delayMinter.updateMintDelay(_newDelay);

    // Try to execute after original delay (should fail)
    vm.warp(block.timestamp + _delay + 1);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintRequestNotReady.selector, requestId));
    delayMinter.executeMint(requestId);

    // Wait for new delay period
    vm.warp(block.timestamp + _newDelay - _delay);

    // Now it should work
    delayMinter.executeMint(requestId);
  }

  function testFuzz_ExecutesMultipleMintRequests(
    address _recipient1,
    address _recipient2,
    uint256 _amount1,
    uint256 _amount2,
    uint48 _delay,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient1);
    _assumeSafeAddress(_recipient2);
    vm.assume(_recipient1 != _recipient2);
    _amount1 = _boundToRealisticAmount(_amount1);
    _amount2 = _boundToRealisticAmount(_amount2);
    _assumeSafeUint(_delay);

    // Ensure the sum of amounts doesn't exceed the cap
    vm.assume(_amount1 + _amount2 <= cappedMinter.CAP());

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Ensure the delay doesn't exceed the capped minter's expiration time
    vm.assume(_delay < cappedMinter.EXPIRATION_TIME() - block.timestamp);

    // Deploy a new delay minter with fuzzed delay
    _setupDelayMinter(_delay, _saltNonce);

    // Create multiple requests
    vm.prank(minter);
    delayMinter.mint(_recipient1, _amount1);

    vm.prank(minter);
    delayMinter.mint(_recipient2, _amount2);

    // Fast forward past delay
    vm.warp(block.timestamp + _delay + 1);

    // Execute both requests
    delayMinter.executeMint(0);
    delayMinter.executeMint(1);

    // Verify both were executed
    assertEq(token.balanceOf(_recipient1), _amount1);
    assertEq(token.balanceOf(_recipient2), _amount2);
  }

  function testFuzz_ExecutesMintAfterPauseAndResume(
    address _recipient,
    uint256 _amount,
    uint48 _delay,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    _amount = _boundToRealisticAmount(_amount);
    _assumeSafeUint(_delay);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Ensure the delay doesn't exceed the capped minter's expiration time
    vm.assume(_delay < cappedMinter.EXPIRATION_TIME() - block.timestamp);

    // Deploy a new delay minter with fuzzed delay
    _setupDelayMinter(_delay, _saltNonce);

    // Grant pauser role to admin for this test
    vm.startPrank(admin);
    delayMinter.grantRole(delayMinter.PAUSER_ROLE(), admin);
    vm.stopPrank();

    // Create a mint request
    vm.prank(minter);
    delayMinter.mint(_recipient, _amount);

    uint256 requestId = 1;

    // Pause the delay minter
    vm.prank(admin);
    delayMinter.pause();

    // Try to create new request (should fail)
    vm.prank(minter);
    vm.expectRevert("Pausable: paused");
    delayMinter.mint(_recipient, _amount);

    // Try to execute existing request (should fail)
    vm.warp(block.timestamp + _delay + 1);
    vm.expectRevert("Pausable: paused");
    delayMinter.executeMint(requestId);

    // Unpause
    vm.prank(admin);
    delayMinter.unpause();

    // Now execution should work
    delayMinter.executeMint(requestId);
  }

  function testFuzz_RevertIf_ExecutingMintAfterContractClosed(
    address _recipient,
    uint256 _amount,
    uint48 _delay,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    _amount = _boundToRealisticAmount(_amount);
    _assumeSafeUint(_delay);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Ensure the delay doesn't exceed the capped minter's expiration time
    vm.assume(_delay < cappedMinter.EXPIRATION_TIME() - block.timestamp);

    // Deploy a new delay minter with fuzzed delay
    _setupDelayMinter(_delay, _saltNonce);

    // Create a mint request
    vm.prank(minter);
    delayMinter.mint(_recipient, _amount);

    uint256 requestId = 1;

    // Close the contract
    vm.prank(admin);
    delayMinter.close();

    // Try to create new request (should fail)
    vm.prank(minter);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterV1.ZkMinter__ContractClosed.selector));
    delayMinter.mint(_recipient, _amount);

    // Try to execute existing request (should fail)
    vm.warp(block.timestamp + _delay + 1);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterV1.ZkMinter__ContractClosed.selector));
    delayMinter.executeMint(requestId);
  }
}
