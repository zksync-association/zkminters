// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {ZkMinterERC1155EligibilityV1} from "src/ZkMinterERC1155EligibilityV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {ZkBaseTest} from "test/helpers/ZkBaseTest.t.sol";
import {FakeERC1155} from "test/fakes/FakeERC1155.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract ZkMinterERC1155EligibilityV1Test is ZkBaseTest {
  ZkMinterERC1155EligibilityV1 public minterERC1155;
  IMintable public mintable;
  FakeERC1155 public fakeERC1155;
  uint256 public constant TOKEN_ID = 1;
  uint256 public constant BALANCE_THRESHOLD = 10;
  address public minter = makeAddr("minter");

  function setUp() public virtual override {
    super.setUp();

    mintable = IMintable(address(cappedMinter));
    fakeERC1155 = new FakeERC1155();
    minterERC1155 = new ZkMinterERC1155EligibilityV1(mintable, admin, address(fakeERC1155), TOKEN_ID, BALANCE_THRESHOLD);

    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(minterERC1155));

    // Set up minter with sufficient balance
    fakeERC1155.setBalance(minter, TOKEN_ID, BALANCE_THRESHOLD);
  }

  function _mockSupportsInterfaceCall(address _target, bool _isSupported) internal {
    vm.mockCall(
      _target,
      abi.encodeWithSelector(bytes4(keccak256("supportsInterface(bytes4)")), type(IERC1155).interfaceId),
      abi.encode(_isSupported)
    );
  }
}

contract Constructor is ZkMinterERC1155EligibilityV1Test {
  function testFuzz_InitializesMinterERC1155Correctly(
    IMintable _mintable,
    address _erc1155,
    address _admin,
    uint256 _tokenId,
    uint256 _balanceThreshold
  ) public {
    _assumeSafeAddress(_admin);
    _assumeSafeUint(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    ZkMinterERC1155EligibilityV1 _minterERC1155 =
      new ZkMinterERC1155EligibilityV1(_mintable, _admin, _erc1155, _tokenId, _balanceThreshold);

    assertEq(address(_minterERC1155.mintable()), address(_mintable));
    assertEq(address(_minterERC1155.ERC1155()), address(_erc1155));
    assertEq(_minterERC1155.tokenId(), _tokenId);
    assertEq(_minterERC1155.balanceThreshold(), _balanceThreshold);
    assertTrue(_minterERC1155.hasRole(_minterERC1155.DEFAULT_ADMIN_ROLE(), _admin));
  }

  function testFuzz_EmitsTokenIdUpdatedEvent(
    IMintable _mintable,
    address _erc1155,
    address _admin,
    uint256 _tokenId,
    uint256 _balanceThreshold
  ) public {
    _assumeSafeAddress(_admin);
    _assumeSafeUint(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    vm.expectEmit();
    emit ZkMinterERC1155EligibilityV1.TokenIdUpdated(0, _tokenId);
    new ZkMinterERC1155EligibilityV1(_mintable, _admin, _erc1155, _tokenId, _balanceThreshold);
  }

  function testFuzz_EmitsBalanceThresholdUpdatedEvent(
    IMintable _mintable,
    address _erc1155,
    address _admin,
    uint256 _tokenId,
    uint256 _balanceThreshold
  ) public {
    _assumeSafeAddress(_admin);
    _assumeSafeUint(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    vm.expectEmit();
    emit ZkMinterERC1155EligibilityV1.BalanceThresholdUpdated(0, _balanceThreshold);
    new ZkMinterERC1155EligibilityV1(_mintable, _admin, _erc1155, _tokenId, _balanceThreshold);
  }

  function testFuzz_RevertIf_AdminIsZeroAddress(
    IMintable _mintable,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold
  ) public {
    _assumeSafeUint(_balanceThreshold);

    vm.expectRevert(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InvalidZeroAddress.selector);
    new ZkMinterERC1155EligibilityV1(_mintable, address(0), _erc1155, _tokenId, _balanceThreshold);
  }

  function testFuzz_RevertIf_BalanceThresholdIsZero(
    IMintable _mintable,
    address _erc1155,
    address _admin,
    uint256 _tokenId
  ) public {
    _assumeSafeAddress(_admin);

    _mockSupportsInterfaceCall(_erc1155, true);

    vm.expectRevert(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InvalidBalanceThreshold.selector);
    new ZkMinterERC1155EligibilityV1(_mintable, _admin, address(fakeERC1155), _tokenId, 0);
  }

  function testFuzz_RevertIf_ERC1155IsNonContract(
    IMintable _mintable,
    address _admin,
    uint256 _tokenId,
    uint256 _balanceThreshold
  ) public {
    _assumeSafeUint(_balanceThreshold);
    _assumeSafeAddress(_admin);

    vm.expectRevert(bytes(""));
    new ZkMinterERC1155EligibilityV1(_mintable, _admin, makeAddr("Fake ERC1155"), _tokenId, _balanceThreshold);
  }

  function testFuzz_RevertIf_ERC1155SupportsADifferentInterface(
    IMintable _mintable,
    address _admin,
    uint256 _tokenId,
    uint256 _balanceThreshold
  ) public {
    _assumeSafeUint(_balanceThreshold);
    _assumeSafeAddress(_admin);
    ERC721 _nonErc1155 = new ERC721("FAK", "Fake");

    vm.expectRevert(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InvalidERC1155Contract.selector);
    new ZkMinterERC1155EligibilityV1(_mintable, _admin, address(_nonErc1155), _tokenId, _balanceThreshold);
  }
}

contract Mint is ZkMinterERC1155EligibilityV1Test {
  function testFuzz_MintsTokensWhenBalanceThresholdMet(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    uint256 balanceBefore = token.balanceOf(_to);

    vm.prank(minter);
    minterERC1155.mint(_to, _amount);

    assertEq(token.balanceOf(_to), balanceBefore + _amount);
  }

  function testFuzz_EmitsMintedEvent(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    vm.expectEmit();
    emit ZkMinterV1.Minted(minter, _to, _amount);

    vm.prank(minter);
    minterERC1155.mint(_to, _amount);
  }

  function testFuzz_RevertIf_InsufficientBalance(address _to, uint256 _amount, uint256 _balance) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);
    _balance = bound(_balance, 0, BALANCE_THRESHOLD - 1);

    // Set balance below threshold
    fakeERC1155.setBalance(minter, TOKEN_ID, _balance);

    vm.expectRevert(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InsufficientBalance.selector);
    vm.prank(minter);
    minterERC1155.mint(_to, _amount);
  }

  function testFuzz_RevertIf_MintAfterContractIsPaused(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    vm.prank(admin);
    minterERC1155.pause();

    vm.expectRevert("Pausable: paused");
    vm.prank(minter);
    minterERC1155.mint(_to, _amount);
  }

  function testFuzz_RevertIf_MintAfterContractIsClosed(address _to, uint256 _amount) public {
    _assumeSafeAddress(_to);
    _amount = _boundToRealisticAmount(_amount);

    vm.prank(admin);
    minterERC1155.close();

    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    vm.prank(minter);
    minterERC1155.mint(_to, _amount);
  }
}

contract UpdateTokenId is ZkMinterERC1155EligibilityV1Test {
  function testFuzz_AdminCanUpdateTokenId(uint256 _newTokenId) public {
    vm.prank(admin);
    minterERC1155.updateTokenId(_newTokenId);
    assertEq(minterERC1155.tokenId(), _newTokenId);
  }

  function testFuzz_EmitsTokenIdUpdatedEvent(uint256 _newTokenId) public {
    vm.expectEmit();
    emit ZkMinterERC1155EligibilityV1.TokenIdUpdated(TOKEN_ID, _newTokenId);
    vm.prank(admin);
    minterERC1155.updateTokenId(_newTokenId);
  }

  function testFuzz_RevertIf_CalledByNonAdmin(uint256 _newTokenId, address _caller) public {
    vm.assume(_caller != admin);
    vm.expectRevert(_formatAccessControlError(_caller, DEFAULT_ADMIN_ROLE));
    vm.prank(_caller);
    minterERC1155.updateTokenId(_newTokenId);
  }
}

contract UpdateBalanceThreshold is ZkMinterERC1155EligibilityV1Test {
  function testFuzz_AdminCanUpdateBalanceThreshold(uint256 _newBalanceThreshold) public {
    _assumeSafeUint(_newBalanceThreshold);
    vm.prank(admin);
    minterERC1155.updateBalanceThreshold(_newBalanceThreshold);
    assertEq(minterERC1155.balanceThreshold(), _newBalanceThreshold);
  }

  function testFuzz_EmitsBalanceThresholdUpdatedEvent(uint256 _newBalanceThreshold) public {
    _assumeSafeUint(_newBalanceThreshold);
    vm.expectEmit();
    emit ZkMinterERC1155EligibilityV1.BalanceThresholdUpdated(BALANCE_THRESHOLD, _newBalanceThreshold);
    vm.prank(admin);
    minterERC1155.updateBalanceThreshold(_newBalanceThreshold);
  }

  function testFuzz_RevertIf_CalledByNonAdmin(uint256 _newBalanceThreshold, address _caller) public {
    _assumeSafeUint(_newBalanceThreshold);
    vm.assume(_caller != admin);
    vm.expectRevert(_formatAccessControlError(_caller, DEFAULT_ADMIN_ROLE));
    vm.prank(_caller);
    minterERC1155.updateBalanceThreshold(_newBalanceThreshold);
  }

  function test_RevertIf_BalanceThresholdIsZero() public {
    vm.expectRevert(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InvalidBalanceThreshold.selector);
    vm.prank(admin);
    minterERC1155.updateBalanceThreshold(0);
  }
}

contract IsEligible is ZkMinterERC1155EligibilityV1Test {
  function testFuzz_ReturnsFalseWhenBalanceBelowThreshold(address _caller, uint256 _balance) public {
    _assumeSafeAddress(_caller);
    _balance = bound(_balance, 1, BALANCE_THRESHOLD - 1);

    fakeERC1155.setBalance(_caller, TOKEN_ID, _balance);

    assertFalse(minterERC1155.isEligible(_caller));
  }

  function testFuzz_ReturnsFalseWhenNoBalance(address _caller) public view {
    _assumeSafeAddress(_caller);
    vm.assume(_caller != minter); // Avoid the minter which has balance set in setUp

    // Don't set any balance, so it defaults to 0
    assertFalse(minterERC1155.isEligible(_caller));
  }

  function testFuzz_ReturnsTrueWhenBalanceAtOrAboveThreshold(address _caller, uint256 _balance) public {
    _assumeSafeAddress(_caller);
    _balance = bound(_balance, BALANCE_THRESHOLD, BALANCE_THRESHOLD * 10);

    fakeERC1155.setBalance(_caller, TOKEN_ID, _balance);

    assertTrue(minterERC1155.isEligible(_caller));
  }
}
