// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterModTriggerV1} from "src/ZkMinterModTriggerV1.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {ZkCappedMinterV2Test} from "test/helpers/ZkCappedMinterV2.t.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

contract MockTargetContract {
  uint256 public value;
  bool public called;
  address public lastCaller;

  function setValue(uint256 _value) external {
    value = _value;
    called = true;
    lastCaller = msg.sender;
  }

  function revertFunction() external pure {
    revert("Mock revert");
  }
}

contract ZkMinterModTriggerV1Test is ZkCappedMinterV2Test {
  ZkMinterModTriggerV1 public minterTrigger;
  IMintable public mintable;
  MockTargetContract public mockTarget;

  address[] public targets;
  bytes[] public callDatas;

  function setUp() public virtual override {
    super.setUp();
    mintable = IMintable(address(cappedMinter));
    mockTarget = new MockTargetContract();

    targets = new address[](1);
    targets[0] = address(mockTarget);

    callDatas = new bytes[](1);
    callDatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);

    minterTrigger = new ZkMinterModTriggerV1(mintable, admin, targets, callDatas);
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(minterTrigger));
  }

  function _grantTriggerMinterRole(address _minter) internal {
    vm.prank(admin);
    minterTrigger.grantRole(MINTER_ROLE, _minter);
  }

  function test_InitializesMinterTriggerCorrectly() public view {
    assertTrue(minterTrigger.hasRole(minterTrigger.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(minterTrigger.hasRole(minterTrigger.PAUSER_ROLE(), admin));
    assertEq(address(minterTrigger.mintable()), address(mintable));
    assertEq(minterTrigger.targets(0), address(mockTarget));
    assertEq(minterTrigger.callDatas(0), abi.encodeWithSelector(mockTarget.setValue.selector, 42));
  }
}

contract Constructor is ZkMinterModTriggerV1Test {
  function testFuzz_InitializesMinterTriggerCorrectly(IMintable _mintable, address _admin, uint256 _setValue) public {
    vm.assume(_admin != address(0) && address(_mintable) != address(0));

    MockTargetContract _mockTarget = new MockTargetContract();
    address[] memory _targets = new address[](1);
    _targets[0] = address(_mockTarget);

    bytes[] memory _callDatas = new bytes[](1);
    _callDatas[0] = abi.encodeWithSelector(_mockTarget.setValue.selector, _setValue);

    ZkMinterModTriggerV1 _minterTrigger = new ZkMinterModTriggerV1(_mintable, _admin, _targets, _callDatas);

    assertEq(address(_minterTrigger.mintable()), address(_mintable));
    assertTrue(_minterTrigger.hasRole(_minterTrigger.DEFAULT_ADMIN_ROLE(), _admin));
    assertEq(_minterTrigger.targets(0), address(_mockTarget));
    assertEq(_minterTrigger.callDatas(0), abi.encodeWithSelector(_mockTarget.setValue.selector, _setValue));
  }

  function testFuzz_RevertIf_AdminIsZeroAddress(IMintable _mintable) public {
    vm.assume(address(_mintable) != address(0));

    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _callDatas = new bytes[](1);
    _callDatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);

    vm.expectRevert(ZkMinterModTriggerV1.ZkMinterModTriggerV1__InvalidAdmin.selector);
    new ZkMinterModTriggerV1(_mintable, address(0), _targets, _callDatas);
  }

  function test_RevertIf_MintableIsZeroAddress() public {
    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _callDatas = new bytes[](1);
    _callDatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);

    vm.expectRevert(ZkMinterModTriggerV1.ZkMinterModTriggerV1__InvalidMintable.selector);
    new ZkMinterModTriggerV1(IMintable(address(0)), admin, _targets, _callDatas);
  }

  function test_RevertIf_ArrayLengthMismatch() public {
    address[] memory _targets = new address[](2);
    _targets[0] = address(mockTarget);
    _targets[1] = address(mockTarget);

    bytes[] memory _callDatas = new bytes[](1);
    _callDatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);

    vm.expectRevert(ZkMinterModTriggerV1.ZkMinterModTriggerV1__ArrayLengthMismatch.selector);
    new ZkMinterModTriggerV1(mintable, admin, _targets, _callDatas);
  }
}

contract Mint is ZkMinterModTriggerV1Test {
  address public minter = makeAddr("minter");

  function setUp() public override {
    super.setUp();
    vm.startPrank(admin);
    minterTrigger.grantRole(MINTER_ROLE, minter);
    vm.stopPrank();
  }

  function testFuzz_MintsSuccessfullyAsMinter(address _minter, address _to, uint256 _amount) public {
    vm.assume(_to != address(0));
    _amount = bound(_amount, 1, cappedMinter.CAP());
    _grantTriggerMinterRole(_minter);

    vm.prank(_minter);
    minterTrigger.mint(_to, _amount);
    assertEq(token.balanceOf(address(minterTrigger)), _amount);
  }

  function testFuzz_EmitsMintedEvent(address _to, uint256 _amount) public {
    vm.assume(_to != address(0));
    _amount = bound(_amount, 1, cappedMinter.CAP());

    vm.prank(minter);
    vm.expectEmit();
    emit ZkMinterV1.Minted(minter, address(minterTrigger), _amount);
    minterTrigger.mint(_to, _amount);
  }

  function testFuzz_RevertIf_CalledByNonMinter(address _nonMinter, address _to, uint256 _amount) public {
    vm.assume(_nonMinter != minter && _nonMinter != admin);

    vm.prank(_nonMinter);
    vm.expectRevert(_formatAccessControlError(_nonMinter, MINTER_ROLE));
    minterTrigger.mint(_to, _amount);
  }

  function testFuzz_RevertIf_MintAfterContractIsPaused(address _caller, address _to, uint256 _amount) public {
    vm.prank(admin);
    minterTrigger.pause();

    vm.prank(_caller);
    vm.expectRevert("Pausable: paused");
    minterTrigger.mint(_to, _amount);
  }

  function testFuzz_RevertIf_MintAfterContractIsClosed(address _caller, address _to, uint256 _amount) public {
    vm.prank(admin);
    minterTrigger.close();

    vm.prank(_caller);
    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    minterTrigger.mint(_to, _amount);
  }
}

contract Trigger is ZkMinterModTriggerV1Test {
  address public caller = makeAddr("caller");

  function setUp() public override {
    super.setUp();
    vm.startPrank(admin);
    minterTrigger.grantRole(MINTER_ROLE, caller);
    vm.stopPrank();
  }

  function test_ExecutesTriggersSuccessfully() public {
    assertEq(mockTarget.value(), 0);
    assertEq(mockTarget.called(), false);

    vm.prank(caller);
    minterTrigger.trigger();

    assertEq(mockTarget.value(), 42);
    assertEq(mockTarget.called(), true);
    assertEq(mockTarget.lastCaller(), address(minterTrigger));
  }

  function test_EmitsTriggerExecutedEvent() public {
    vm.expectEmit();
    emit ZkMinterModTriggerV1.TriggerExecuted(caller, 1);
    vm.prank(caller);
    minterTrigger.trigger();
  }

  function test_ExecutesMultipleTriggers() public {
    MockTargetContract secondTarget = new MockTargetContract();

    address[] memory _targets = new address[](2);
    _targets[0] = address(mockTarget);
    _targets[1] = address(secondTarget);

    bytes[] memory _callDatas = new bytes[](2);
    _callDatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);
    _callDatas[1] = abi.encodeWithSelector(secondTarget.setValue.selector, 100);

    ZkMinterModTriggerV1 multiTrigger = new ZkMinterModTriggerV1(mintable, admin, _targets, _callDatas);

    vm.prank(admin);
    multiTrigger.grantRole(MINTER_ROLE, caller);

    vm.prank(caller);
    multiTrigger.trigger();

    assertEq(mockTarget.value(), 42);
    assertEq(mockTarget.called(), true);
    assertEq(secondTarget.value(), 100);
    assertEq(secondTarget.called(), true);
  }

  function testFuzz_RevertIf_TriggerAfterContractIsPaused(address _caller) public {
    vm.prank(admin);
    minterTrigger.pause();

    vm.prank(_caller);
    vm.expectRevert("Pausable: paused");
    minterTrigger.trigger();
  }

  function testFuzz_RevertIf_TriggerAfterContractIsClosed(address _caller) public {
    vm.prank(admin);
    minterTrigger.close();

    vm.prank(_caller);
    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    minterTrigger.trigger();
  }

  function testFuzz_RevertIf_NotMinter(address _nonMinter) public {
    vm.assume(_nonMinter != caller && _nonMinter != admin);

    vm.prank(_nonMinter);
    vm.expectRevert(_formatAccessControlError(_nonMinter, MINTER_ROLE));
    minterTrigger.trigger();
  }

  function test_RevertIf_FunctionCallFails() public {
    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _callDatas = new bytes[](1);
    _callDatas[0] = abi.encodeWithSelector(mockTarget.revertFunction.selector);

    ZkMinterModTriggerV1 failTrigger = new ZkMinterModTriggerV1(mintable, admin, _targets, _callDatas);

    vm.prank(admin);
    failTrigger.grantRole(MINTER_ROLE, caller);

    vm.expectRevert(
      abi.encodeWithSelector(
        ZkMinterModTriggerV1.ZkMinterModTriggerV1__TriggerCallFailed.selector, 0, address(mockTarget)
      )
    );
    vm.prank(caller);
    failTrigger.trigger();
  }
}
