// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkBaseTest} from "test/helpers/ZkBaseTest.t.sol";
import {ZkMinterERC1155EligibilityV1} from "src/ZkMinterERC1155EligibilityV1.sol";
import {ZkMinterERC1155EligibilityV1Factory} from "src/ZkMinterERC1155EligibilityV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {FakeERC1155} from "test/fakes/FakeERC1155.sol";

/// @title ZkMinterERC1155EligibilityV1Integration
/// @notice Integration tests for ZkMinterERC1155EligibilityV1 with zk token and capped minter
contract ZkMinterERC1155EligibilityV1Integration is ZkBaseTest {
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

  function _boundToRealisticThreshold(uint256 _balanceThreshold) internal pure returns (uint256) {
    return bound(_balanceThreshold, 1, 100_000e18);
  }

  /// @notice Helper function to setup the eligibility minter with configurable parameters
  /// @param _tokenId The token ID to check for eligibility
  /// @param _balanceThreshold The minimum balance required for eligibility
  /// @param _saltNonce The salt nonce for deterministic deployment
  function _createEligibilityMinter(uint256 _tokenId, uint256 _balanceThreshold, uint256 _saltNonce)
    internal
    returns (ZkMinterERC1155EligibilityV1)
  {
    ZkMinterERC1155EligibilityV1 _eligibilityMinter = ZkMinterERC1155EligibilityV1(
      eligibilityFactory.createMinter(
        IMintable(address(cappedMinter)), admin, address(fakeERC1155), _tokenId, _balanceThreshold, _saltNonce
      )
    );

    // Grant minter role to the eligibility minter so it can mint through the cappedMinter
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(_eligibilityMinter));

    vm.label(address(_eligibilityMinter), "EligibilityMinter");
    return _eligibilityMinter;
  }

  function testFuzz_DeployEligibilityMinterCorrectly(uint256 _tokenId, uint256 _balanceThreshold, uint256 _saltNonce)
    public
  {
    _balanceThreshold = _boundToRealisticThreshold(_balanceThreshold);

    ZkMinterERC1155EligibilityV1 _eligibilityMinter = _createEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    assertEq(address(_eligibilityMinter.ERC1155()), address(fakeERC1155));
    assertEq(_eligibilityMinter.tokenId(), _tokenId);
    assertEq(_eligibilityMinter.balanceThreshold(), _balanceThreshold);
  }

  function testFuzz_MintAboveBalanceThreshold(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce,
    uint256 _balance
  ) public {
    _assumeSafeAddress(_recipient);
    _balanceThreshold = _boundToRealisticThreshold(_balanceThreshold);
    _balance = bound(_balance, _balanceThreshold, type(uint256).max);
    _amount = _boundToRealisticAmount(_amount);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    ZkMinterERC1155EligibilityV1 _eligibilityMinter = _createEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Test with balance above threshold
    fakeERC1155.setBalance(_recipient, _tokenId, _balance);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    // Recipient should be able to mint
    vm.prank(_recipient);
    _eligibilityMinter.mint(_recipient, _amount);

    // Verify minting occurred
    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);
    assertEq(_eligibilityMinter.isEligible(_recipient), true);
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
    _balanceThreshold = _boundToRealisticThreshold(_balanceThreshold);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    ZkMinterERC1155EligibilityV1 _eligibilityMinter = _createEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Give recipient sufficient balance
    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 10);

    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    // First mint
    vm.prank(_recipient);
    _eligibilityMinter.mint(_recipient, _amount1);
    assertEq(token.balanceOf(_recipient), initialBalance + _amount1);
    assertEq(token.totalSupply(), initialTotalSupply + _amount1);

    // Second mint
    vm.prank(_recipient);
    _eligibilityMinter.mint(_recipient, _amount2);
    assertEq(token.balanceOf(_recipient), initialBalance + _amount1 + _amount2);
    assertEq(token.totalSupply(), initialTotalSupply + _amount1 + _amount2);
  }

  function testFuzz_MultipleMintsByDifferentUsers(
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
    _balanceThreshold = _boundToRealisticThreshold(_balanceThreshold);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    ZkMinterERC1155EligibilityV1 _eligibilityMinter = _createEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Give both recipients sufficient balance
    fakeERC1155.setBalance(_recipient1, _tokenId, _balanceThreshold + 1);
    fakeERC1155.setBalance(_recipient2, _tokenId, _balanceThreshold + 1);

    uint256 initialBalance1 = token.balanceOf(_recipient1);
    uint256 initialBalance2 = token.balanceOf(_recipient2);
    uint256 initialTotalSupply = token.totalSupply();

    // Recipient1 mints
    vm.prank(_recipient1);
    _eligibilityMinter.mint(_recipient1, _amount1);
    assertEq(token.balanceOf(_recipient1), initialBalance1 + _amount1);
    assertEq(token.balanceOf(_recipient2), initialBalance2);
    assertEq(token.totalSupply(), initialTotalSupply + _amount1);

    // Recipient2 mints
    vm.prank(_recipient2);
    _eligibilityMinter.mint(_recipient2, _amount2);
    assertEq(token.balanceOf(_recipient1), initialBalance1 + _amount1);
    assertEq(token.balanceOf(_recipient2), initialBalance2 + _amount2);
    assertEq(token.totalSupply(), initialTotalSupply + _amount1 + _amount2);
  }

  function testFuzz_MintAfterMinterIsPaused(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    _balanceThreshold = _boundToRealisticThreshold(_balanceThreshold);
    _amount = _boundToRealisticAmount(_amount);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    ZkMinterERC1155EligibilityV1 _eligibilityMinter = _createEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 1);

    // Pause the eligibility minter
    vm.prank(admin);
    _eligibilityMinter.pause();

    // Try to mint while paused (should fail)
    vm.prank(_recipient);
    vm.expectRevert("Pausable: paused");
    _eligibilityMinter.mint(_recipient, _amount);

    // Unpause
    vm.prank(admin);
    _eligibilityMinter.unpause();

    // Now minting should work
    uint256 initialBalance = token.balanceOf(_recipient);
    uint256 initialTotalSupply = token.totalSupply();

    vm.prank(_recipient);
    _eligibilityMinter.mint(_recipient, _amount);

    assertEq(token.balanceOf(_recipient), initialBalance + _amount);
    assertEq(token.totalSupply(), initialTotalSupply + _amount);
  }

  function testFuzz_RevertIf_BelowTheBalanceThreshold(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    _balanceThreshold = _boundToRealisticThreshold(_balanceThreshold);
    _amount = _boundToRealisticAmount(_amount);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    ZkMinterERC1155EligibilityV1 _eligibilityMinter = _createEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    // Give recipient insufficient balance
    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold - 1);

    assertEq(_eligibilityMinter.isEligible(_recipient), false);

    // Recipient should not be able to mint
    vm.prank(_recipient);
    vm.expectRevert(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InsufficientBalance.selector);
    _eligibilityMinter.mint(_recipient, _amount);
  }

  function testFuzz_RevertIf_MinterClosed(
    address _recipient,
    uint256 _amount,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeSafeAddress(_recipient);
    _balanceThreshold = _boundToRealisticThreshold(_balanceThreshold);
    _amount = _boundToRealisticAmount(_amount);

    // Warp to a valid time within the capped minter's window
    vm.warp(cappedMinter.START_TIME() + 1);

    ZkMinterERC1155EligibilityV1 _eligibilityMinter = _createEligibilityMinter(_tokenId, _balanceThreshold, _saltNonce);

    fakeERC1155.setBalance(_recipient, _tokenId, _balanceThreshold + 1);

    // Close the contract
    vm.prank(admin);
    _eligibilityMinter.close();

    // Try to mint after contract is closed (should fail)
    vm.prank(_recipient);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterV1.ZkMinter__ContractClosed.selector));
    _eligibilityMinter.mint(_recipient, _amount);
  }
}
