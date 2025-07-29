// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkBaseTest} from "test/helpers/ZkBaseTest.t.sol";
import {ZkMinterERC1155EligibilityV1} from "src/ZkMinterERC1155EligibilityV1.sol";
import {ZkMinterERC1155EligibilityV1Factory} from "src/ZkMinterERC1155EligibilityV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {FakeERC1155} from "test/fakes/FakeERC1155.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title ZkMinterERC1155EligibilityV1Integration
/// @notice Integration tests for ZkMinterERC1155EligibilityV1 with zk token and capped minter
contract ZkMinterERC1155EligibilityV1Integration is ZkBaseTest {
  ZkMinterERC1155EligibilityV1 public eligibilityMinter;
  ZkMinterERC1155EligibilityV1Factory public eligibilityFactory;
  FakeERC1155 public fakeERC1155;

  function setUp() public override {
    (string memory rpcUrl, uint256 forkBlock) = _getForkConfig();
    vm.createSelectFork(rpcUrl, forkBlock);

    super.setUp();

    // Deploy our own FakeERC1155 for testing
    fakeERC1155 = new FakeERC1155();

    // Compute bytecode hash directly from the contract
    bytes32 bytecodeHash = keccak256(type(ZkMinterERC1155EligibilityV1).creationCode);

    // Deploy the factory with the bytecode hash
    eligibilityFactory = new ZkMinterERC1155EligibilityV1Factory(bytecodeHash);

    vm.label(address(eligibilityFactory), "EligibilityFactory");
    vm.label(address(fakeERC1155), "FakeERC1155");
  }

  function _boundToRealisticParameters(uint256 _tokenId, uint256 _balanceThreshold, uint256 _amount)
    internal
    pure
    returns (uint256, uint256, uint256)
  {
    return (
      bound(_tokenId, 1, 10_000), // Reasonable bounds for token ID
      bound(_balanceThreshold, 1, 1000), // Reasonable bounds for threshold
      _boundToRealisticAmount(_amount)
    );
  }

  /// @notice Helper function to setup the eligibility minter with configurable parameters
  /// @param _tokenId The token ID to check for eligibility
  /// @param _balanceThreshold The minimum balance required for eligibility
  /// @param _saltNonce The salt nonce for deterministic deployment
  function _setupEligibilityMinter(uint256 _tokenId, uint256 _balanceThreshold, uint256 _saltNonce) internal {
    eligibilityMinter = ZkMinterERC1155EligibilityV1(
      eligibilityFactory.createMinter(
        IMintable(address(cappedMinter)), admin, address(fakeERC1155), _tokenId, _balanceThreshold, _saltNonce
      )
    );

    // Grant minter role to the eligibility minter so it can mint through the cappedMinter
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(eligibilityMinter));

    vm.label(address(eligibilityMinter), "EligibilityMinter");
  }

  function testFuzz_DeployCorrectly(uint256 _tokenId, uint256 _balanceThreshold, uint256 _saltNonce) public {
    _tokenId = bound(_tokenId, 1, 10_000);
    _balanceThreshold = bound(_balanceThreshold, 1, 1000);

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    assertEq(address(eligibilityMinter.ERC1155()), address(fakeERC1155));
    assertEq(eligibilityMinter.tokenId(), _tokenId);
    assertEq(eligibilityMinter.balanceThreshold(), _balanceThreshold);
  }

  function testFuzz_MintWithSufficientBalance(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _balanceThreshold, _amount) = _boundToRealisticParameters(_tokenId, _balanceThreshold, _amount);
    vm.assume(_balanceThreshold <= type(uint256).max - 1); // Prevent overflow when adding 1
    vm.assume(_amount <= cappedMinter.CAP() / 2); // Ensure we can mint twice without exceeding cap

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Test with balance above threshold
    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 1);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    // Recipient should be able to mint
    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount);

    // Verify minting occurred
    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);

    // Test with exact balance threshold
    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold);

    uint256 newInitialBalance = token.balanceOf(_recipient);
    uint256 newInitialTotalSupply = token.totalSupply();

    // Recipient should still be able to mint with exact balance
    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount);

    // Verify minting occurred again
    assertEq(token.balanceOf(_recipient), newInitialBalance + _amount);
    assertEq(token.totalSupply(), newInitialTotalSupply + _amount);
  }

  function testFuzz_RevertIf_MintWithInsufficientBalance(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _balanceThreshold, _amount) = _boundToRealisticParameters(_tokenId, _balanceThreshold, _amount);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Give recipient insufficient balance
    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold - 1);

    // Recipient should not be able to mint
    vm.prank(_recipient);
    vm.expectRevert(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InsufficientBalance.selector);
    eligibilityMinter.mint(_recipient, _amount);
  }

  function testFuzz_MultipleMintsBySameUser(
    address _recipient,
    uint256 _amount1,
    uint256 _amount2,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    _amount1 = _boundToRealisticAmount(_amount1);
    _amount2 = _boundToRealisticAmount(_amount2);
    (_tokenId, _balanceThreshold,) = _boundToRealisticParameters(_tokenId, _balanceThreshold, 0);
    vm.assume(_balanceThreshold <= type(uint256).max - 10); // Prevent overflow when adding 10

    // Ensure the sum of amounts doesn't exceed the cap
    vm.assume(_amount1 + _amount2 <= cappedMinter.CAP());

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Give recipient sufficient balance
    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 10);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    // First mint
    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount1);
    assertEq(token.balanceOf(_recipient), initialBalance + _amount1);
    assertEq(token.totalSupply(), initialTotalSupply + _amount1);

    // Second mint
    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount2);
    assertEq(token.balanceOf(_recipient), initialBalance + _amount1 + _amount2);
    assertEq(token.totalSupply(), initialTotalSupply + _amount1 + _amount2);
  }

  function testFuzz_DifferentEligibleUsers(
    address _recipient1,
    address _recipient2,
    uint256 _amount1,
    uint256 _amount2,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient1);
    _assumeSafeAddress(_recipient2);
    vm.assume(_recipient1 != _recipient2);
    _amount1 = _boundToRealisticAmount(_amount1);
    _amount2 = _boundToRealisticAmount(_amount2);
    (_tokenId, _balanceThreshold,) = _boundToRealisticParameters(_tokenId, _balanceThreshold, 0);
    vm.assume(_balanceThreshold <= type(uint256).max - 1); // Prevent overflow when adding 1

    // Ensure the sum of amounts doesn't exceed the cap
    vm.assume(_amount1 + _amount2 <= cappedMinter.CAP());

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Give both recipients sufficient balance
    fakeERC1155.setBalance(_recipient1, _tokenId, _balanceThreshold + 1);
    fakeERC1155.setBalance(_recipient2, _tokenId, _balanceThreshold + 1);

    uint256 initialBalance1 = token.balanceOf(_recipient1);
    uint256 initialBalance2 = token.balanceOf(_recipient2);
    uint256 initialTotalSupply = token.totalSupply();

    // Recipient1 mints
    vm.prank(_recipient1);
    eligibilityMinter.mint(_recipient1, _amount1);
    assertEq(token.balanceOf(_recipient1), initialBalance1 + _amount1);
    assertEq(token.balanceOf(_recipient2), initialBalance2);
    assertEq(token.totalSupply(), initialTotalSupply + _amount1);

    // Recipient2 mints
    vm.prank(_recipient2);
    eligibilityMinter.mint(_recipient2, _amount2);
    assertEq(token.balanceOf(_recipient1), initialBalance1 + _amount1);
    assertEq(token.balanceOf(_recipient2), initialBalance2 + _amount2);
    assertEq(token.totalSupply(), initialTotalSupply + _amount1 + _amount2);
  }

  function testFuzz_MintWhenUserBalanceChanges(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _balanceThreshold, _amount) = _boundToRealisticParameters(_tokenId, _balanceThreshold, _amount);
    vm.assume(_balanceThreshold <= type(uint256).max - 1); // Prevent overflow when adding 1

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Give recipient sufficient balance initially
    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 1);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    // Recipient should be able to mint
    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount);
    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);

    // Now reduce recipient's balance below threshold
    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold - 1);

    // Recipient should not be able to mint anymore
    vm.prank(_recipient);
    vm.expectRevert(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InsufficientBalance.selector);
    eligibilityMinter.mint(_recipient, _amount);
  }

  function testFuzz_EligibilityCheck(
    address _recipient,
    uint256 _balance,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _balanceThreshold,) = _boundToRealisticParameters(_tokenId, _balanceThreshold, 0);
    vm.assume(_balance <= type(uint256).max - _balanceThreshold); // Prevent overflow

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Set recipient's balance
    fakeERC1155.setBalance(_recipient, _tokenId, _balance);

    bool shouldBeEligible = _balance >= _balanceThreshold;
    assertEq(eligibilityMinter.isEligible(_recipient), shouldBeEligible);
  }

  function testFuzz_MintWithDifferentThresholds(
    address _recipient,
    uint256 _amount,
    uint256 _threshold,
    uint256 _tokenId,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _threshold, _amount) = _boundToRealisticParameters(_tokenId, _threshold, _amount);
    vm.assume(_threshold <= type(uint256).max - 5); // Prevent overflow when adding 5

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Setup with new threshold
    _setupEligibilityMinter(_tokenId, _threshold, _saltNonce);

    uint256 userBalance = _threshold + 5;
    fakeERC1155.setBalance(_recipient, _tokenId, userBalance);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount);

    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);
  }

  function testFuzz_MintWithDifferentTokenIds(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _balanceThreshold, _amount) = _boundToRealisticParameters(_tokenId, _balanceThreshold, _amount);
    vm.assume(_balanceThreshold <= type(uint256).max - 1); // Prevent overflow when adding 1

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Setup with new token ID
    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 1);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount);

    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);
  }

  // Comprehensive fuzzing for both token ID and threshold together
  function testFuzz_MintWithDifferentTokenIdAndThreshold(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _threshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _threshold, _amount) = _boundToRealisticParameters(_tokenId, _threshold, _amount);
    vm.assume(_threshold <= type(uint256).max - 5); // Prevent overflow when adding 5

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Setup with new token ID and threshold
    _setupEligibilityMinter(_tokenId, _threshold, _saltNonce);

    uint256 userBalance = _threshold + 5;
    fakeERC1155.setBalance(_recipient, _tokenId, userBalance);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount);

    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);
  }

  // Test threshold boundary conditions
  function testFuzz_ThresholdBoundaryConditions(
    address _recipient,
    uint256 _threshold,
    uint256 _tokenId,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _threshold,) = _boundToRealisticParameters(_tokenId, _threshold, 0);
    vm.assume(_threshold <= type(uint256).max - 1); // Prevent overflow when adding 1

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    // Setup with new threshold
    _setupEligibilityMinter(_tokenId, _threshold, _saltNonce);

    // Test with balance exactly at threshold
    fakeERC1155.setBalance(_recipient, _tokenId, _threshold);
    assertTrue(eligibilityMinter.isEligible(_recipient));

    // Test with balance just below threshold
    fakeERC1155.setBalance(_recipient, _tokenId, _threshold - 1);
    assertFalse(eligibilityMinter.isEligible(_recipient));

    // Test with balance just above threshold
    fakeERC1155.setBalance(_recipient, _tokenId, _threshold + 1);
    assertTrue(eligibilityMinter.isEligible(_recipient));
  }

  function testFuzz_MintAfterPauseAndResume(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _balanceThreshold, _amount) = _boundToRealisticParameters(_tokenId, _balanceThreshold, _amount);
    vm.assume(_balanceThreshold <= type(uint256).max - 1); // Prevent overflow when adding 1

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 1);

    // Pause the eligibility minter
    vm.prank(admin);
    eligibilityMinter.pause();

    // Try to mint while paused (should fail)
    vm.prank(_recipient);
    vm.expectRevert("Pausable: paused");
    eligibilityMinter.mint(_recipient, _amount);

    // Unpause
    vm.prank(admin);
    eligibilityMinter.unpause();

    // Now minting should work
    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    vm.prank(_recipient);
    eligibilityMinter.mint(_recipient, _amount);

    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);
  }

  function testFuzz_RevertIf_MintAfterContractClosed(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    (_tokenId, _balanceThreshold, _amount) = _boundToRealisticParameters(_tokenId, _balanceThreshold, _amount);
    vm.assume(_balanceThreshold <= type(uint256).max - 1); // Prevent overflow when adding 1

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    _setupEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 1);

    // Close the contract
    vm.prank(admin);
    eligibilityMinter.close();

    // Try to mint after contract is closed (should fail)
    vm.prank(_recipient);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterV1.ZkMinter__ContractClosed.selector));
    eligibilityMinter.mint(_recipient, _amount);
  }
}
