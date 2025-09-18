// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterModTriggerV1} from "src/ZkMinterModTriggerV1.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {ZkCappedMinterV2Test} from "test/helpers/ZkCappedMinterV2.t.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {MockTargetContract} from "test/helpers/MockTargetContract.sol";

contract ZkMinterModTriggerV1Test is ZkCappedMinterV2Test {
  ZkMinterModTriggerV1 public minterTrigger;
  IMintable public mintable;
  MockTargetContract public mockTarget;
  address public caller = makeAddr("caller");

  address[] public targets;
  bytes[] public calldatas;
  uint256[] public values;

  function setUp() public virtual override {
    super.setUp();
    mintable = IMintable(address(cappedMinter));
    mockTarget = new MockTargetContract();

    targets = new address[](1);
    targets[0] = address(mockTarget);

    calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);

    values = new uint256[](1);
    values[0] = 100 ether;

    minterTrigger = new ZkMinterModTriggerV1(mintable, admin, targets, calldatas, values);
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
    assertEq(minterTrigger.calldatas(0), abi.encodeWithSelector(mockTarget.setValue.selector, 42));
    assertEq(minterTrigger.values(0), 100 ether);
  }
}

contract Constructor is ZkMinterModTriggerV1Test {
  function testFuzz_InitializesMinterTriggerCorrectly(
    IMintable _mintable,
    address _admin,
    uint256 _setValue,
    uint256 _value
  ) public {
    vm.assume(_admin != address(0) && address(_mintable) != address(0));

    MockTargetContract _mockTarget = new MockTargetContract();
    address[] memory _targets = new address[](1);
    _targets[0] = address(_mockTarget);

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeWithSelector(_mockTarget.setValue.selector, _setValue);

    uint256[] memory _values = new uint256[](1);
    _values[0] = _value;

    ZkMinterModTriggerV1 _minterTrigger = new ZkMinterModTriggerV1(_mintable, _admin, _targets, _calldatas, _values);

    assertEq(address(_minterTrigger.mintable()), address(_mintable));
    assertTrue(_minterTrigger.hasRole(_minterTrigger.DEFAULT_ADMIN_ROLE(), _admin));
    assertEq(_minterTrigger.targets(0), address(_mockTarget));
    assertEq(_minterTrigger.calldatas(0), abi.encodeWithSelector(_mockTarget.setValue.selector, _setValue));
    assertEq(_minterTrigger.values(0), _value);
  }

  function testFuzz_RevertIf_AdminIsZeroAddress(IMintable _mintable) public {
    vm.assume(address(_mintable) != address(0));

    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);

    uint256[] memory _values = new uint256[](1);
    _values[0] = 100 ether;

    vm.expectRevert(ZkMinterModTriggerV1.ZkMinterModTriggerV1__InvalidAdmin.selector);
    new ZkMinterModTriggerV1(_mintable, address(0), _targets, _calldatas, _values);
  }

  function test_RevertIf_ArrayLengthMismatch() public {
    address[] memory _targets = new address[](2);
    _targets[0] = address(mockTarget);
    _targets[1] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);

    uint256[] memory _values = new uint256[](1);
    _values[0] = 100 ether;

    vm.expectRevert(ZkMinterModTriggerV1.ZkMinterModTriggerV1__ArrayLengthMismatch.selector);
    new ZkMinterModTriggerV1(mintable, admin, _targets, _calldatas, _values);
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

  function testFuzz_MintsSuccessfullyAsMinter(address _minter, uint256 _amount) public {
    _amount = bound(_amount, 1, cappedMinter.CAP());
    _grantTriggerMinterRole(_minter);
    address _to = address(minterTrigger);

    vm.prank(_minter);
    minterTrigger.mint(_to, _amount);
    assertEq(token.balanceOf(_to), _amount);
  }

  function testFuzz_EmitsMintedEvent(uint256 _amount) public {
    _amount = bound(_amount, 1, cappedMinter.CAP());
    address _to = address(minterTrigger);

    vm.prank(minter);
    vm.expectEmit();
    emit ZkMinterV1.Minted(minter, _to, _amount);
    minterTrigger.mint(_to, _amount);
  }

  function testFuzz_RevertIf_InvalidRecipient(address _to, uint256 _amount) public {
    vm.assume(_to != address(minterTrigger));
    _amount = bound(_amount, 1, cappedMinter.CAP());

    vm.prank(minter);
    vm.expectRevert(
      abi.encodeWithSelector(
        ZkMinterModTriggerV1.ZkMinterModTriggerV1__InvalidRecipient.selector, _to, address(minterTrigger)
      )
    );
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
  function setUp() public override {
    super.setUp();
    vm.prank(admin);
    minterTrigger.grantRole(MINTER_ROLE, caller);
    vm.deal(address(caller), 100 ether);
  }

  function test_TriggersSuccessfully() public {
    assertEq(mockTarget.value(), 0);
    assertEq(mockTarget.called(), false);
    assertEq(address(minterTrigger).balance, 0);

    vm.prank(caller);
    minterTrigger.trigger{value: 100 ether}();

    assertEq(mockTarget.value(), 42);
    assertEq(mockTarget.called(), true);
    assertEq(mockTarget.lastCaller(), address(minterTrigger));
    assertEq(address(mockTarget).balance, 100 ether);
  }

  function testFuzz_EmitsTriggerExecutedEvent(address _caller) public {
    deal(address(_caller), 100 ether);
    _grantTriggerMinterRole(_caller);

    vm.expectEmit();
    emit ZkMinterModTriggerV1.TriggerExecuted(_caller, 1);
    vm.prank(_caller);
    minterTrigger.trigger{value: 100 ether}();
  }

  function test_ExecutesMultipleTriggers() public {
    MockTargetContract secondTarget = new MockTargetContract();

    address[] memory _targets = new address[](2);
    _targets[0] = address(mockTarget);
    _targets[1] = address(secondTarget);

    bytes[] memory _calldatas = new bytes[](2);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);
    _calldatas[1] = abi.encodeWithSelector(secondTarget.setValue.selector, 100);

    uint256[] memory _values = new uint256[](2);
    _values[0] = 100 ether;
    _values[1] = 100 ether;

    vm.deal(address(caller), 200 ether);

    ZkMinterModTriggerV1 multiTrigger = new ZkMinterModTriggerV1(mintable, admin, _targets, _calldatas, _values);

    vm.prank(admin);
    multiTrigger.grantRole(MINTER_ROLE, caller);

    vm.prank(caller);
    multiTrigger.trigger{value: 200 ether}();

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

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.revertFunction.selector);

    uint256[] memory _values = new uint256[](1);
    _values[0] = 100 ether;

    ZkMinterModTriggerV1 failTrigger = new ZkMinterModTriggerV1(mintable, admin, _targets, _calldatas, _values);

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

contract IntegrationTest is ZkMinterModTriggerV1Test {
  function testFuzz_MintsThenTriggers_MintedTokensEndUpAtTarget(
    address _caller,
    address _recipient,
    uint256 _amount,
    uint256 _ethValue,
    uint256 _setValue
  ) public {
    _amount = bound(_amount, 1, cappedMinter.CAP());
    _ethValue = bound(_ethValue, 0, 1000 ether);
    vm.assume(_recipient != address(0));

    // Create a trigger that first transfers ERC20 tokens from the trigger to the mock target,
    // then calls the mock target's setValue with ETH.
    address[] memory _targets = new address[](2);
    _targets[0] = address(token);
    _targets[1] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](2);
    _calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount);
    _calldatas[1] = abi.encodeWithSelector(mockTarget.setValue.selector, _setValue);

    uint256[] memory _values = new uint256[](2);
    _values[0] = 0;
    _values[1] = _ethValue;

    ZkMinterModTriggerV1 _multiTrigger = new ZkMinterModTriggerV1(mintable, admin, _targets, _calldatas, _values);

    // Configure roles
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(_multiTrigger));
    vm.prank(admin);
    _multiTrigger.grantRole(MINTER_ROLE, _caller);

    // Mint tokens
    vm.prank(_caller);
    _multiTrigger.mint(address(_multiTrigger), _amount);
    assertEq(token.balanceOf(address(_multiTrigger)), _amount);

    // Call trigger
    vm.deal(address(_caller), _ethValue);
    vm.prank(_caller);
    _multiTrigger.trigger{value: _ethValue}();

    // Verify mock target call and ETH transfer
    assertEq(mockTarget.value(), _setValue);
    assertEq(mockTarget.called(), true);
    assertEq(mockTarget.lastCaller(), address(_multiTrigger));
    assertEq(address(mockTarget).balance, _ethValue);

    // Verify ERC20 tokens were transferred from the trigger to the mock target
    assertEq(token.balanceOf(address(_multiTrigger)), 0);
    assertEq(token.balanceOf(_recipient), _amount);
  }
}
