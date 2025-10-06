// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {ZkCappedMinterV3} from "src/ZkCappedMinterV3.sol";

contract MockMintable is IMintable {
  mapping(address => uint256) public balanceOf;

  function mint(address _to, uint256 _amount) external {
    balanceOf[_to] += _amount;
  }
}

contract ZkCappedMinterV3Test is Test {
  ZkCappedMinterV3 public cappedMinterV3;
  MockMintable public token;

  address public cappedMinterAdmin;

  uint256 public constant DEFAULT_CAP = 100_000_000e18;
  uint48 public DEFAULT_START_TIME;
  uint48 public DEFAULT_EXPIRATION_TIME;

  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  uint256 public constant MAX_MINT_SUPPLY = type(uint208).max;

  function setUp() public virtual {
    cappedMinterAdmin = makeAddr("cappedMinterAdmin");
    DEFAULT_START_TIME = uint48(vm.getBlockTimestamp());
    DEFAULT_EXPIRATION_TIME = uint48(DEFAULT_START_TIME + 3 days);

    token = new MockMintable();
    cappedMinterV3 = new ZkCappedMinterV3(
      IMintable(address(token)), cappedMinterAdmin, DEFAULT_CAP, DEFAULT_START_TIME, DEFAULT_EXPIRATION_TIME
    );
  }

  function _boundToValidTimeControls(uint48 _startTime, uint48 _expirationTime) internal view returns (uint48, uint48) {
    _startTime = uint48(bound(_startTime, vm.getBlockTimestamp(), type(uint32).max - 1));
    _expirationTime = uint48(bound(_expirationTime, _startTime + 1, type(uint32).max));
    return (_startTime, _expirationTime);
  }

  function _formatAccessControlError(address account, bytes32 role) internal pure returns (bytes memory) {
    return bytes(
      string.concat(
        "AccessControl: account ",
        Strings.toHexString(uint160(account), 20),
        " is missing role ",
        Strings.toHexString(uint256(role), 32)
      )
    );
  }
}

contract Mint is ZkCappedMinterV3Test {
  function testFuzz_MintsNewTokensWhenTheAmountRequestedIsBelowTheCap(
    address _minter,
    address _receiver,
    uint256 _amount
  ) public {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 1, DEFAULT_CAP - 1);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    uint256 balanceBefore = token.balanceOf(_receiver);

    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), balanceBefore + _amount);
  }

  function testFuzz_RevertIf_CapExceededOnMint(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, DEFAULT_CAP + 1, type(uint256).max);
    vm.assume(_receiver != address(0));

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV3.ZkCappedMinterV3__CapExceeded.selector, _minter, _amount));
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_MintBeforeStartTime(
    address _minter,
    address _receiver,
    uint256 _amount,
    uint256 _beforeStartTime
  ) public {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 1, DEFAULT_CAP);
    _beforeStartTime = bound(_beforeStartTime, 0, cappedMinterV3.START_TIME() - 1);

    vm.warp(_beforeStartTime);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    vm.expectRevert(ZkCappedMinterV3.ZkCappedMinterV3__NotStarted.selector);
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_MintAfterExpiration(
    address _minter,
    address _receiver,
    uint256 _amount,
    uint256 _afterExpirationTime
  ) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));
    _afterExpirationTime = bound(_afterExpirationTime, cappedMinterV3.EXPIRATION_TIME() + 1, type(uint256).max);

    vm.warp(_afterExpirationTime);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    vm.expectRevert(ZkCappedMinterV3.ZkCappedMinterV3__Expired.selector);
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_CorrectlyPermanentlyBlocksMintingWhenClosed(address _minter, address _receiver, uint256 _amount)
    public
  {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.close();

    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_EmitsMintedEvent(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    vm.expectEmit();
    emit ZkMinterV1.Minted(_minter, _receiver, _amount);
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_MintAttemptedByNonMinter(address _nonMinter, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);

    vm.expectRevert(_formatAccessControlError(_nonMinter, MINTER_ROLE));
    vm.prank(_nonMinter);
    cappedMinterV3.mint(_nonMinter, _amount);
  }

  function testFuzz_RevertIf_AdminAttemptsToMintByDefault(address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    vm.expectRevert(_formatAccessControlError(cappedMinterAdmin, MINTER_ROLE));
    vm.prank(cappedMinterAdmin);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_NestedMintingContributesToParentCap(
    address _parentAdmin,
    address _childAdmin,
    address _minter,
    address _receiver,
    uint256 _parentCap,
    uint256 _childCap,
    uint256 _amount1,
    uint256 _amount2,
    uint48 _startTime,
    uint48 _expirationTime
  ) public {
    _parentCap = bound(_parentCap, 2, DEFAULT_CAP);
    _childCap = bound(_childCap, 2, _parentCap);
    uint256 maxAmount = _childCap / 2;
    _amount1 = bound(_amount1, 1, maxAmount);
    _amount2 = bound(_amount2, 1, maxAmount);
    vm.assume(_receiver != address(0));

    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV3 parentMinter =
      new ZkCappedMinterV3(IMintable(address(token)), _parentAdmin, _parentCap, _startTime, _expirationTime);
    ZkCappedMinterV3 childMinter =
      new ZkCappedMinterV3(IMintable(address(parentMinter)), _childAdmin, _childCap, _startTime, _expirationTime);

    vm.prank(_parentAdmin);
    parentMinter.grantRole(MINTER_ROLE, address(childMinter));
    vm.prank(_childAdmin);
    childMinter.grantRole(MINTER_ROLE, _minter);

    uint256 balanceBefore = token.balanceOf(_receiver);

    vm.prank(_minter);
    childMinter.mint(_receiver, _amount1);

    uint256 balanceAfter = token.balanceOf(_receiver);

    assertEq(childMinter.minted(), _amount1);
    assertEq(parentMinter.minted(), _amount1);
    assertEq(balanceAfter, balanceBefore + _amount1);

    vm.prank(_minter);
    childMinter.mint(_receiver, _amount2);

    balanceAfter = token.balanceOf(_receiver);

    assertEq(childMinter.minted(), _amount1 + _amount2);
    assertEq(parentMinter.minted(), _amount1 + _amount2);
    assertEq(balanceAfter, balanceBefore + _amount1 + _amount2);
  }

  function testFuzz_ParentMintDoesNotCountAgainstChildCap(
    address _parentAdmin,
    address _childAdmin,
    address _minter,
    address _receiver,
    uint256 _parentCap,
    uint256 _childCap,
    uint256 _amount,
    uint48 _startTime,
    uint48 _expirationTime
  ) public {
    vm.assume(_receiver != address(0));

    _parentCap = bound(_parentCap, 1, DEFAULT_CAP);
    _amount = bound(_amount, 1, _parentCap);

    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV3 parentMinter =
      new ZkCappedMinterV3(IMintable(address(token)), _parentAdmin, _parentCap, _startTime, _expirationTime);
    ZkCappedMinterV3 childMinter =
      new ZkCappedMinterV3(IMintable(address(parentMinter)), _childAdmin, _childCap, _startTime, _expirationTime);

    vm.prank(_parentAdmin);
    parentMinter.grantRole(MINTER_ROLE, _minter);

    vm.prank(_minter);
    parentMinter.mint(_receiver, _amount);

    assertEq(childMinter.minted(), 0);
    assertEq(parentMinter.minted(), _amount);
  }

  function testFuzz_RevertIf_ChildExceedsParentMintEvenThoughChildCapIsHigher(
    address _parentAdmin,
    address _childAdmin,
    address _minter,
    address _receiver,
    uint256 _parentCap,
    uint256 _childCap,
    uint256 _amount,
    uint48 _startTime,
    uint48 _expirationTime
  ) public {
    _parentCap = bound(_parentCap, 2, MAX_MINT_SUPPLY - 1);
    _childCap = bound(_childCap, _parentCap + 1, MAX_MINT_SUPPLY);
    _amount = bound(_amount, _parentCap + 1, _childCap);

    vm.assume(_parentAdmin != address(0));
    vm.assume(_childAdmin != address(0));
    vm.assume(_minter != address(0));
    vm.assume(_receiver != address(0));

    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV3 parentMinter =
      new ZkCappedMinterV3(IMintable(address(token)), _parentAdmin, _parentCap, _startTime, _expirationTime);
    ZkCappedMinterV3 childMinter =
      new ZkCappedMinterV3(IMintable(address(parentMinter)), _childAdmin, _childCap, _startTime, _expirationTime);

    vm.prank(_parentAdmin);
    parentMinter.grantRole(MINTER_ROLE, address(childMinter));

    vm.startPrank(address(childMinter));
    vm.expectRevert(
      abi.encodeWithSelector(ZkCappedMinterV3.ZkCappedMinterV3__CapExceeded.selector, address(childMinter), _amount)
    );
    parentMinter.mint(_receiver, _amount);
    vm.stopPrank();
  }
}

contract Pause is ZkCappedMinterV3Test {
  function testFuzz_CorrectlyPreventsNewMintsWhenPaused(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    uint256 balanceBefore = token.balanceOf(_receiver);

    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), balanceBefore + _amount);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.pause();

    vm.expectRevert("Pausable: paused");
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_CorrectlyPausesMintsWhenTogglingPause(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    vm.startPrank(cappedMinterAdmin);
    cappedMinterV3.pause();
    cappedMinterV3.unpause();
    cappedMinterV3.pause();
    vm.stopPrank();

    vm.expectRevert("Pausable: paused");
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_NotPauserRolePauses(uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.revokeRole(PAUSER_ROLE, cappedMinterAdmin);

    vm.expectRevert(_formatAccessControlError(cappedMinterAdmin, PAUSER_ROLE));
    vm.prank(cappedMinterAdmin);
    cappedMinterV3.pause();
  }
}

contract Unpause is ZkCappedMinterV3Test {
  function testFuzz_CorrectlyAllowsNewMintsWhenUnpaused(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.pause();

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.unpause();

    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_NotPauserRoleUnpauses(uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.pause();

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.revokeRole(PAUSER_ROLE, cappedMinterAdmin);

    vm.expectRevert(_formatAccessControlError(cappedMinterAdmin, PAUSER_ROLE));
    vm.prank(cappedMinterAdmin);
    cappedMinterV3.unpause();
  }
}

contract Close is ZkCappedMinterV3Test {
  function test_CorrectlyChangesClosedVarWhenCalledByAdmin() public {
    assertEq(cappedMinterV3.closed(), false);

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.close();
    assertEq(cappedMinterV3.closed(), true);
  }

  function testFuzz_EmitsClosedEvent() public {
    vm.prank(cappedMinterAdmin);
    vm.expectEmit();
    emit ZkMinterV1.Closed(cappedMinterAdmin);
    cappedMinterV3.close();
  }

  function testFuzz_RevertIf_NotAdminCloses(address _nonAdmin) public {
    vm.assume(_nonAdmin != cappedMinterAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    vm.prank(_nonAdmin);
    cappedMinterV3.close();
  }
}

contract SetMetadataURI is ZkCappedMinterV3Test {
  function testFuzz_InitialMetadataURIIsEmpty(address _admin, uint256 _cap, uint48 _startTime, uint48 _expirationTime)
    public
  {
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);

    ZkCappedMinterV3 v3 = new ZkCappedMinterV3(IMintable(address(token)), _admin, _cap, _startTime, _expirationTime);
    assertEq(v3.metadataURI(), "");
  }

  function testFuzz_AdminCanSetMetadataURI(string memory _uri) public {
    vm.prank(cappedMinterAdmin);
    cappedMinterV3.setMetadataURI(_uri);

    assertEq(cappedMinterV3.metadataURI(), _uri);
  }

  function testFuzz_EmitsMetadataURISetEvent(string memory _uri) public {
    vm.prank(cappedMinterAdmin);
    vm.expectEmit();
    emit ZkCappedMinterV3.MetadataURISet(_uri);
    cappedMinterV3.setMetadataURI(_uri);
  }

  function testFuzz_RevertIf_NonAdminSetsMetadataURI(address _nonAdmin, string memory _uri) public {
    vm.assume(cappedMinterAdmin != _nonAdmin);

    vm.prank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    cappedMinterV3.setMetadataURI(_uri);
  }
}

contract Constructor is ZkCappedMinterV3Test {
  function testFuzz_InitializesTheCappedMinterForAssociationAndFoundation(
    address _admin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime
  ) public {
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV3 v3 = new ZkCappedMinterV3(IMintable(address(token)), _admin, _cap, _startTime, _expirationTime);
    assertEq(address(v3.mintable()), address(token));
    assertEq(v3.CAP(), _cap);
    assertEq(v3.START_TIME(), _startTime);
    assertEq(v3.EXPIRATION_TIME(), _expirationTime);
  }

  function testFuzz_RevertIf_StartTimeAfterExpirationTime(
    address _admin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _invalidExpirationTime
  ) public {
    _startTime = uint48(bound(_startTime, 1, type(uint48).max));
    _invalidExpirationTime = uint48(bound(_invalidExpirationTime, 0, _startTime - 1));
    vm.expectRevert(ZkCappedMinterV3.ZkCappedMinterV3__InvalidTime.selector);
    new ZkCappedMinterV3(IMintable(address(token)), _admin, _cap, _startTime, _invalidExpirationTime);
  }

  function testFuzz_RevertIf_StartTimeInPast(address _admin, uint256 _cap, uint48 _startTime, uint48 _expirationTime)
    public
  {
    _startTime = uint48(bound(_startTime, 1, type(uint48).max));
    vm.warp(_startTime);

    _cap = bound(_cap, 1, DEFAULT_CAP);
    uint48 _pastStartTime = _startTime - 1;
    _expirationTime = uint48(bound(_expirationTime, _pastStartTime + 1, type(uint48).max));

    vm.expectRevert(ZkCappedMinterV3.ZkCappedMinterV3__InvalidTime.selector);
    new ZkCappedMinterV3(IMintable(address(token)), _admin, _cap, _pastStartTime, _expirationTime);
  }
}

contract GrantRole is ZkCappedMinterV3Test {
  function test_AdminCanGrantDefaultAdminRole(address _newAdmin) public {
    vm.assume(_newAdmin != address(0));

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);

    assertTrue(cappedMinterV3.hasRole(DEFAULT_ADMIN_ROLE, _newAdmin));
  }
}

contract UpdateMintable is ZkCappedMinterV3Test {
  function test_UpdateMintable_ByAdmin_RoutesMintsToNewTarget(address _minter, address _receiver, uint256 _amount)
    public
  {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 1, DEFAULT_CAP - 1);

    // Grant minter role
    vm.prank(cappedMinterAdmin);
    cappedMinterV3.grantRole(MINTER_ROLE, _minter);

    // Initial mint goes to original token
    uint256 balanceBeforeOld = token.balanceOf(_receiver);
    vm.warp(DEFAULT_START_TIME);
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), balanceBeforeOld + _amount);

    // Create a new mintable and update
    MockMintable newToken = new MockMintable();
    vm.prank(cappedMinterAdmin);
    cappedMinterV3.updateMintable(IMintable(address(newToken)));

    // Next mint should route to newToken (use small amount to avoid cap issues)
    uint256 balanceBeforeNew = newToken.balanceOf(_receiver);
    vm.prank(_minter);
    cappedMinterV3.mint(_receiver, 1);
    assertEq(newToken.balanceOf(_receiver), balanceBeforeNew + 1);
  }

  function test_UpdateMintable_RevertIf_NotAdmin(address _nonAdmin) public {
    vm.assume(_nonAdmin != cappedMinterAdmin);
    MockMintable newToken = new MockMintable();

    vm.prank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    cappedMinterV3.updateMintable(IMintable(address(newToken)));
  }

  function test_UpdateMintable_RevertIf_Closed() public {
    MockMintable newToken = new MockMintable();

    vm.prank(cappedMinterAdmin);
    cappedMinterV3.close();

    vm.prank(cappedMinterAdmin);
    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    cappedMinterV3.updateMintable(IMintable(address(newToken)));
  }
}
