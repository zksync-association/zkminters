// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {ZkMinterDelayV1, MintRequest} from "src/ZkMinterDelayV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {ZkCappedMinterV2Test} from "test/helpers/ZkCappedMinterV2.t.sol";

contract ZkMinterDelayV1Test is ZkCappedMinterV2Test {
  ZkMinterDelayV1 public minterDelay;
  IMintable public mintable;
  uint48 public constant MINT_DELAY = 1 days;
  address public minter = makeAddr("minter");

  function setUp() public virtual override {
    super.setUp();

    mintable = IMintable(address(cappedMinter));
    minterDelay = new ZkMinterDelayV1(mintable, admin, MINT_DELAY);

    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(minterDelay));

    vm.prank(admin);
    minterDelay.grantRole(MINTER_ROLE, minter);
  }

  function _assumeSafeAddress(address _address) internal pure {
    vm.assume(_address != address(0));
  }

  function _assumeSafeMintable(IMintable _mintable) internal pure {
    vm.assume(address(_mintable) != address(0));
  }

  function _assumeSafeMintDelay(uint48 _mintDelay) internal pure {
    vm.assume(_mintDelay != 0);
  }

  function _boundToRealisticAmount(uint256 _amount) internal pure returns (uint256) {
    return bound(_amount, 1, DEFAULT_CAP);
  }

  function _createMintRequest(address _to, uint256 _amount) internal returns (uint256) {
    vm.prank(minter);
    minterDelay.mint(_to, _amount);
    return minterDelay.nextMintRequestId() - 1;
  }
}

contract Constructor is ZkMinterDelayV1Test {
  function testFuzz_InitializesMinterDelayCorrectly(IMintable _mintable, address _admin, uint48 _mintDelay) public {
    _assumeSafeAddress(_admin);
    _assumeSafeMintable(_mintable);
    _assumeSafeMintDelay(_mintDelay);

    ZkMinterDelayV1 _minterDelay = new ZkMinterDelayV1(_mintable, _admin, _mintDelay);

    assertEq(address(_minterDelay.mintable()), address(_mintable));
    assertTrue(_minterDelay.hasRole(_minterDelay.DEFAULT_ADMIN_ROLE(), _admin));
    assertEq(_minterDelay.mintDelay(), _mintDelay);
    assertEq(_minterDelay.nextMintRequestId(), 0);
  }

  function testFuzz_EmitsMinterDelayUpdatedEvent(IMintable _mintable, address _admin, uint48 _mintDelay) public {
    _assumeSafeMintable(_mintable);
    _assumeSafeAddress(_admin);
    _assumeSafeMintDelay(_mintDelay);

    vm.expectEmit(true, true, true, true);
    emit ZkMinterDelayV1.MintDelayUpdated(minterDelay.mintDelay(), _mintDelay);
    vm.prank(admin);
    minterDelay.updateMintDelay(_mintDelay);
  }

  function testFuzz_RevertIf_AdminIsZeroAddress(IMintable _mintable, uint48 _mintDelay) public {
    _assumeSafeMintable(_mintable);
    _assumeSafeMintDelay(_mintDelay);

    vm.expectRevert(ZkMinterDelayV1.ZkMinterDelayV1__InvalidAdmin.selector);
    new ZkMinterDelayV1(_mintable, address(0), _mintDelay);
  }

  function testFuzz_RevertIf_MintDelayIsZero(IMintable _mintable, address _admin) public {
    _assumeSafeAddress(_admin);
    _assumeSafeMintable(_mintable);

    vm.expectRevert(ZkMinterDelayV1.ZkMinterDelayV1__InvalidMintDelay.selector);
    new ZkMinterDelayV1(_mintable, _admin, 0);
  }
}

contract Mint is ZkMinterDelayV1Test {
  function testFuzz_MintRequestIsCreatedCorrectly(address _toAddress, uint256 _mintAmount) public {
    _assumeSafeAddress(_toAddress);
    _mintAmount = _boundToRealisticAmount(_mintAmount);

    vm.prank(minter);
    minterDelay.mint(_toAddress, _mintAmount);

    MintRequest memory _mintRequest = minterDelay.getMintRequest(minterDelay.nextMintRequestId() - 1);

    assertEq(_mintRequest.to, _toAddress);
    assertEq(_mintRequest.amount, _mintAmount);
    assertEq(_mintRequest.createdAt, uint48(block.timestamp));
    assertEq(_mintRequest.executed, false);
    assertEq(_mintRequest.cancelled, false);
    assertEq(_mintRequest.minter, minter);
  }

  function testFuzz_IncrementsNextMintRequestId(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _nextMintRequestId = minterDelay.nextMintRequestId();

    vm.prank(minter);
    minterDelay.mint(_to, _amount);

    assertEq(minterDelay.nextMintRequestId(), _nextMintRequestId + 1);
  }

  function testFuzz_EmitsMintRequestedEvent(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    vm.expectEmit(true, true, true, true);
    emit ZkMinterDelayV1.MintRequested(1, uint48(block.timestamp));

    vm.prank(minter);
    minterDelay.mint(_to, _amount);
  }

  function testFuzz_RevertIf_ToAddressIsZeroAddress(uint256 _amount) public {
    _amount = _boundToRealisticAmount(_amount);

    vm.expectRevert(ZkMinterDelayV1.ZkMinterDelayV1__InvalidToAddress.selector);
    minterDelay.mint(address(0), _amount);
  }

  function testFuzz_RevertIf_AmountIsZero(address _to) public {
    _assumeSafeAddress(_to);

    vm.expectRevert(ZkMinterDelayV1.ZkMinterDelayV1__InvalidAmount.selector);
    minterDelay.mint(_to, 0);
  }

  function testFuzz_RevertIf_MinterIsNotMinterRole(address _to, uint256 _amount, address _caller) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);
    vm.assume(_caller != minter);

    vm.expectRevert(_formatAccessControlError(_caller, MINTER_ROLE));
    vm.prank(_caller);
    minterDelay.mint(_to, _amount);
  }

  function testFuzz_RevertIf_MintAfterContractIsPaused(address _caller, address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    vm.prank(admin);
    minterDelay.pause();

    vm.prank(_caller);
    vm.expectRevert("Pausable: paused");
    minterDelay.mint(_to, _amount);
  }

  function testFuzz_RevertIf_MintAfterContractIsClosed(address _caller, address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    vm.prank(admin);
    minterDelay.close();

    vm.prank(_caller);
    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    minterDelay.mint(_to, _amount);
  }
}

contract ExecuteMint is ZkMinterDelayV1Test {
  function testFuzz_ExecutesMintAfterDelay(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);

    assertEq(token.balanceOf(_to), 0);

    vm.warp(block.timestamp + MINT_DELAY + 1);
    minterDelay.executeMint(_mintRequestId);

    assertEq(token.balanceOf(_to), _amount);
  }

  function testFuzz_UpatedExecutedFlagAfterMint(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);
    assertFalse(minterDelay.getMintRequest(_mintRequestId).executed);

    vm.warp(block.timestamp + MINT_DELAY + 1);
    minterDelay.executeMint(_mintRequestId);

    assertTrue(minterDelay.getMintRequest(_mintRequestId).executed);
  }

  function testFuzz_EmitsMintedEvent(address _caller, address _to, uint256 _amount) public {
    _assumeSafeAddress(_caller);
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);
    vm.warp(block.timestamp + MINT_DELAY + 1);

    vm.expectEmit(true, true, true, true);
    emit ZkMinterV1.Minted(minter, _to, _amount);

    vm.prank(_caller);
    minterDelay.executeMint(_mintRequestId);
  }

  function testFuzz_RevertIf_MintRequestIdIsInvalid(uint256 _mintRequestId) public {
    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__InvalidMintRequest.selector, _mintRequestId)
    );
    minterDelay.executeMint(_mintRequestId);
  }

  function testFuzz_RevertIf_MintingIsPaused(uint256 _mintRequestId) public {
    vm.prank(admin);
    minterDelay.pause();

    vm.expectRevert("Pausable: paused");
    minterDelay.executeMint(_mintRequestId);
  }

  function testFuzz_RevertIf_MintingIsClosed(uint256 _mintRequestId) public {
    vm.prank(admin);
    minterDelay.close();

    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    minterDelay.executeMint(_mintRequestId);
  }

  function testFuzz_RevertIf_MintRequestIdIsAlreadyExecuted(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);

    // Execute the mint request first
    vm.warp(block.timestamp + MINT_DELAY + 1);
    minterDelay.executeMint(_mintRequestId);

    // Try to execute the same mint request again
    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintAlreadyExecuted.selector, _mintRequestId)
    );
    minterDelay.executeMint(_mintRequestId);
  }

  function testFuzz_RevertIf_MintRequestIsCancelled(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);

    vm.prank(admin);
    minterDelay.cancelMintRequest(_mintRequestId);

    vm.warp(block.timestamp + MINT_DELAY + 1);

    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintRequestCancelled.selector, _mintRequestId)
    );
    minterDelay.executeMint(_mintRequestId);
  }

  function testFuzz_RevertIf_MintTooEarly(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);

    // Try to execute before the delay has elapsed
    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintRequestNotReady.selector, _mintRequestId)
    );
    minterDelay.executeMint(_mintRequestId);
  }
}

contract UpdateMintDelay is ZkMinterDelayV1Test {
  function testFuzz_AdminCanUpdateMintDelay(uint48 _newMintDelay) public {
    _assumeSafeMintDelay(_newMintDelay);
    vm.prank(admin);
    minterDelay.updateMintDelay(_newMintDelay);
    assertEq(minterDelay.mintDelay(), _newMintDelay);
  }

  function testFuzz_EmitsMintDelayUpdatedEvent(uint48 _newMintDelay) public {
    _assumeSafeMintDelay(_newMintDelay);
    vm.expectEmit(true, true, true, true);
    emit ZkMinterDelayV1.MintDelayUpdated(minterDelay.mintDelay(), _newMintDelay);
    vm.prank(admin);
    minterDelay.updateMintDelay(_newMintDelay);
  }

  function testFuzz_RevertIf_CalledByNonAdmin(uint48 _newMintDelay, address _caller) public {
    _assumeSafeMintDelay(_newMintDelay);
    vm.assume(_caller != admin);
    vm.expectRevert(_formatAccessControlError(_caller, DEFAULT_ADMIN_ROLE));
    vm.prank(_caller);
    minterDelay.updateMintDelay(_newMintDelay);
  }

  function test_RevertIf_MintDelayIsZero() public {
    vm.expectRevert(ZkMinterDelayV1.ZkMinterDelayV1__InvalidMintDelay.selector);
    vm.prank(admin);
    minterDelay.updateMintDelay(0);
  }
}

contract CancelMintRequest is ZkMinterDelayV1Test {
  function testFuzz_CanCancelMintRequestBeforeDelay(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);

    assertFalse(minterDelay.getMintRequest(_mintRequestId).cancelled);

    vm.prank(admin);
    minterDelay.cancelMintRequest(_mintRequestId);

    assertTrue(minterDelay.getMintRequest(_mintRequestId).cancelled);
  }

  function testFuzz_CanCancelMintRequestAfterDelay(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);

    assertFalse(minterDelay.getMintRequest(_mintRequestId).cancelled);

    vm.warp(block.timestamp + MINT_DELAY);

    vm.prank(admin);
    minterDelay.cancelMintRequest(_mintRequestId);

    assertTrue(minterDelay.getMintRequest(_mintRequestId).cancelled);
  }

  function testFuzz_EmitsMintRequestCancelledEvent(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);

    vm.expectEmit(true, true, true, true);
    emit ZkMinterDelayV1.MintRequestCancelled(_mintRequestId);

    vm.prank(admin);
    minterDelay.cancelMintRequest(_mintRequestId);
  }

  function testFuzz_RevertIf_MintRequestIsInvalid(uint256 _mintRequestId) public {
    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__InvalidMintRequest.selector, _mintRequestId)
    );
    vm.prank(admin);
    minterDelay.cancelMintRequest(_mintRequestId);
  }

  function testFuzz_RevertIf_MintIsAlreadyExecuted(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 _mintRequestId = _createMintRequest(_to, _amount);

    vm.warp(block.timestamp + MINT_DELAY + 1);
    minterDelay.executeMint(_mintRequestId);

    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__MintAlreadyExecuted.selector, _mintRequestId)
    );
    vm.prank(admin);
    minterDelay.cancelMintRequest(_mintRequestId);
  }

  function testFuzz_RevertIf_CalledByNonAdmin(uint256 _mintRequestId, address _caller) public {
    vm.assume(_caller != admin);
    vm.expectRevert(_formatAccessControlError(_caller, DEFAULT_ADMIN_ROLE));
    vm.prank(_caller);
    minterDelay.cancelMintRequest(_mintRequestId);
  }
}
