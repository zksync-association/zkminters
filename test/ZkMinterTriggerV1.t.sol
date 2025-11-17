// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterTriggerV1} from "src/ZkMinterTriggerV1.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {MockTargetContract} from "test/helpers/MockTargetContract.sol";
import {ZkBaseTest} from "test/helpers/ZkBaseTest.t.sol";

contract ZkMinterTriggerV1Test is ZkBaseTest {
  ZkMinterTriggerV1 public minterTrigger;
  IMintable public mintable;
  MockTargetContract public mockTarget;
  address public caller = makeAddr("caller");
  address public recoveryAddress;

  address[] public targets;
  bytes[] public calldatas;
  uint256[] public values;

  function setUp() public virtual override {
    super.setUp();
    mintable = IMintable(address(cappedMinter));
    mockTarget = new MockTargetContract();
    recoveryAddress = makeAddr("recovery");

    targets = new address[](1);
    targets[0] = address(mockTarget);

    calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);

    values = new uint256[](1);
    values[0] = 1e18;

    minterTrigger = new ZkMinterTriggerV1(mintable, admin, targets, calldatas, values, recoveryAddress);
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(minterTrigger));
  }

  function _grantTriggerMinterRole(address _minter) internal {
    vm.prank(admin);
    minterTrigger.grantRole(MINTER_ROLE, _minter);
  }

  function _grantCappedMinterRole(address _minter) internal {
    _grantMinterRole(cappedMinter, cappedMinterAdmin, _minter);
  }

  function _boundTriggerValue(uint256 _value) internal returns (uint256) {
    return bound(_value, 1e18, 10_000_000e18);
  }

  function test_InitializesMinterTriggerCorrectly() public view {
    assertTrue(minterTrigger.hasRole(minterTrigger.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(minterTrigger.hasRole(minterTrigger.PAUSER_ROLE(), admin));
    assertEq(address(minterTrigger.mintable()), address(mintable));
    assertEq(minterTrigger.targets(0), address(mockTarget));
    assertEq(minterTrigger.calldatas(0), abi.encodeWithSelector(mockTarget.setValue.selector, 42));
    assertEq(minterTrigger.RECOVERY_ADDRESS(), recoveryAddress);
  }
}

contract Constructor is ZkMinterTriggerV1Test {
  function testFuzz_InitializesMinterTriggerCorrectly(
    IMintable _mintable,
    address _admin,
    address _recovery,
    uint256 _setValue,
    uint256 _value,
    address _target2,
    bytes memory _calldatas2,
    uint256 _value2
  ) public {
    vm.assume(_admin != address(0) && _recovery != address(0));

    MockTargetContract _mockTarget = new MockTargetContract();
    address[] memory _targets = new address[](2);
    _targets[0] = address(_mockTarget);
    _targets[1] = _target2;

    bytes[] memory _calldatas = new bytes[](2);
    _calldatas[0] = abi.encodeWithSelector(_mockTarget.setValue.selector, _setValue);
    _calldatas[1] = _calldatas2;

    uint256[] memory _values = new uint256[](2);
    _values[0] = _value;
    _values[1] = _value2;

    ZkMinterTriggerV1 _minterTrigger =
      new ZkMinterTriggerV1(_mintable, _admin, _targets, _calldatas, _values, _recovery);

    assertEq(address(_minterTrigger.mintable()), address(_mintable));
    assertTrue(_minterTrigger.hasRole(_minterTrigger.DEFAULT_ADMIN_ROLE(), _admin));
    assertTrue(_minterTrigger.hasRole(_minterTrigger.PAUSER_ROLE(), _admin));
    assertEq(_minterTrigger.targets(0), address(_mockTarget));
    assertEq(_minterTrigger.targets(1), _target2);
    assertEq(_minterTrigger.calldatas(0), abi.encodeWithSelector(_mockTarget.setValue.selector, _setValue));
    assertEq(_minterTrigger.calldatas(1), _calldatas2);
    assertEq(_minterTrigger.values(0), _value);
    assertEq(_minterTrigger.values(1), _value2);
    assertEq(_minterTrigger.RECOVERY_ADDRESS(), _recovery);
  }

  function testFuzz_RevertIf_AdminIsZeroAddress(IMintable _mintable, uint256 _amount, uint256 _value) public {
    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, _value);

    uint256[] memory _values = new uint256[](1);
    _values[0] = _amount;

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__InvalidAdmin.selector);
    new ZkMinterTriggerV1(_mintable, address(0), _targets, _calldatas, _values, recoveryAddress);
  }

  function test_RevertIf_TargetsArrayLengthMismatch(uint256 _valueAmount, uint256 _calldataValue) public {
    address[] memory _targets = new address[](2);
    _targets[0] = address(mockTarget);
    _targets[1] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, _calldataValue);

    uint256[] memory _values = new uint256[](1);
    _values[0] = _valueAmount;

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__ArrayLengthMismatch.selector);
    new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);
  }

  function test_RevertIf_ValuesArrayLengthMismatch(uint256 _valueAmount, uint256 _mockValue) public {
    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, _mockValue);

    uint256[] memory _values = new uint256[](2);
    _values[0] = _valueAmount;
    _values[1] = _valueAmount;

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__ArrayLengthMismatch.selector);
    new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);
  }

  function test_RevertIf_CalldatasArrayLengthMismatch(uint256 _valueAmount, uint256 _mockValue) public {
    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](2);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, _mockValue);
    _calldatas[1] = abi.encodeWithSelector(mockTarget.setValue.selector, _mockValue);

    uint256[] memory _values = new uint256[](1);
    _values[0] = _valueAmount;

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__ArrayLengthMismatch.selector);
    new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);
  }

  function test_RevertIf_RecoveryAddressIsZero(uint256 _valueAmount, uint256 _mockValue) public {
    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _callDatas = new bytes[](1);
    _callDatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, _mockValue);

    uint256[] memory _values = new uint256[](1);
    _values[0] = _valueAmount;

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__InvalidRecoveryAddress.selector);
    new ZkMinterTriggerV1(mintable, admin, _targets, _callDatas, _values, address(0));
  }
}

contract Mint is ZkMinterTriggerV1Test {
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
        ZkMinterTriggerV1.ZkMinterTriggerV1__InvalidRecipient.selector, _to, address(minterTrigger)
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

contract Trigger is ZkMinterTriggerV1Test {
  function testFuzz_TriggersSuccessfully(uint256 _value, address _caller) public {
    _assumeSafeAddress(_caller);
    _value = _boundTriggerValue(_value);
    _grantTriggerMinterRole(_caller);

    assertEq(mockTarget.value(), 0);
    assertEq(mockTarget.called(), false);
    assertEq(address(mockTarget).balance, 0);

    vm.deal(_caller, _value);
    vm.prank(_caller);
    minterTrigger.trigger{value: _value}();

    assertEq(mockTarget.value(), 42);
    assertEq(mockTarget.called(), true);
    assertEq(mockTarget.lastCaller(), address(minterTrigger));
    assertEq(address(mockTarget).balance, 1e18);
  }

  function testFuzz_EmitsTriggerExecutedEvent(address _caller, uint256 _value) public {
    _assumeSafeAddress(_caller);
    _value = _boundTriggerValue(_value);
    deal(address(_caller), _value);
    _grantTriggerMinterRole(_caller);

    vm.expectEmit();
    emit ZkMinterTriggerV1.TriggerExecuted(_caller);
    vm.prank(_caller);
    minterTrigger.trigger{value: _value}();
  }

  function testFuzz_ExecutesMultipleTriggers(uint256 _value1, uint256 _value2) public {
    _value1 = _boundToRealisticAmount(_value1);
    _value2 = _boundToRealisticAmount(_value2);
    MockTargetContract secondTarget = new MockTargetContract();

    address[] memory _targets = new address[](2);
    _targets[0] = address(mockTarget);
    _targets[1] = address(secondTarget);

    bytes[] memory _calldatas = new bytes[](2);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.setValue.selector, 42);
    _calldatas[1] = abi.encodeWithSelector(secondTarget.setValue.selector, 100);

    uint256[] memory _values = new uint256[](2);
    _values[0] = _value1;
    _values[1] = _value2;

    vm.deal(address(caller), _value1 + _value2);

    ZkMinterTriggerV1 multiTrigger =
      new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);

    vm.prank(admin);
    multiTrigger.grantRole(MINTER_ROLE, caller);

    vm.deal(caller, _value1 + _value2);
    vm.prank(caller);
    multiTrigger.trigger{value: _value1 + _value2}();

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

    ZkMinterTriggerV1 failTrigger =
      new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);

    vm.prank(admin);
    failTrigger.grantRole(MINTER_ROLE, caller);

    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterTriggerV1.ZkMinterTriggerV1__TriggerCallFailed.selector, 0, address(mockTarget))
    );
    vm.prank(caller);
    failTrigger.trigger();
  }

  function testFuzz_RevertIf_TargetHasNoCode(address _noCodeTarget, address _caller) public {
    _assumeSafeAddress(_caller);
    vm.assume(_noCodeTarget.code.length == 0 && _noCodeTarget != address(0x000000000000000000000000000000000000800A));

    address[] memory _targets = new address[](1);
    _targets[0] = _noCodeTarget;
    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = bytes("");
    uint256[] memory _values = new uint256[](1);

    ZkMinterTriggerV1 _noCodeTrigger =
      new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);
    vm.prank(admin);
    _noCodeTrigger.grantRole(MINTER_ROLE, _caller);

    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterTriggerV1.ZkMinterTriggerV1__NoCodeAtTarget.selector, 0, _noCodeTarget)
    );
    vm.prank(_caller);
    _noCodeTrigger.trigger();
  }
}

contract MintAndTrigger is ZkMinterTriggerV1Test {
  function testFuzz_MintsAndTriggersSuccessfully(uint256 _amount, uint256 _value, address _caller) public {
    _amount = _boundToRealisticAmount(_amount);
    _value = _boundTriggerValue(_value);
    _grantTriggerMinterRole(_caller);

    assertEq(token.balanceOf(address(minterTrigger)), 0);
    assertEq(mockTarget.value(), 0);
    assertEq(mockTarget.called(), false);
    assertEq(address(mockTarget).balance, 0);

    vm.deal(_caller, _value);
    vm.prank(_caller);
    minterTrigger.mintAndTrigger{value: _value}(address(minterTrigger), _amount);

    // Minted to the trigger contract.
    assertEq(token.balanceOf(address(minterTrigger)), _amount);

    // Trigger executed against the configured target with 1 ether.
    assertEq(mockTarget.value(), 42);
    assertEq(mockTarget.called(), true);
    assertEq(mockTarget.lastCaller(), address(minterTrigger));
    assertEq(address(mockTarget).balance, 1 ether);
  }

  function testFuzz_EmitsEvents(address _caller, uint256 _amount, uint256 _value) public {
    _amount = _boundToRealisticAmount(_amount);
    _value = _boundTriggerValue(_value);
    _grantTriggerMinterRole(_caller);

    vm.deal(_caller, _value);

    vm.expectEmit();
    emit ZkMinterV1.Minted(_caller, address(minterTrigger), _amount);
    vm.expectEmit();
    emit ZkMinterTriggerV1.TriggerExecuted(_caller);

    vm.prank(_caller);
    minterTrigger.mintAndTrigger{value: _value}(address(minterTrigger), _amount);
  }

  function testFuzz_RevertIf_InvalidRecipient(address _to, uint256 _amount, uint256 _value, address _caller) public {
    vm.assume(_to != address(minterTrigger));
    _amount = _boundToRealisticAmount(_amount);
    _value = _boundTriggerValue(_value);
    _grantTriggerMinterRole(_caller);

    vm.deal(_caller, _value);
    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        ZkMinterTriggerV1.ZkMinterTriggerV1__InvalidRecipient.selector, _to, address(minterTrigger)
      )
    );
    minterTrigger.mintAndTrigger{value: _value}(_to, _amount);
  }

  function testFuzz_RevertIf_NotMinter(address _nonMinter, address _to, uint256 _amount, uint256 _value) public {
    _amount = _boundToRealisticAmount(_amount);
    _value = _boundTriggerValue(_value);

    vm.deal(_nonMinter, _value);
    vm.prank(_nonMinter);
    vm.expectRevert(_formatAccessControlError(_nonMinter, MINTER_ROLE));
    minterTrigger.mintAndTrigger{value: _value}(_to, _amount);
  }

  function testFuzz_RevertIf_Paused(address _to, uint256 _amount, uint256 _value, address _caller) public {
    _amount = _boundToRealisticAmount(_amount);
    _value = _boundTriggerValue(_value);
    _grantTriggerMinterRole(_caller);

    vm.prank(admin);
    minterTrigger.pause();

    vm.deal(_caller, _value);
    vm.prank(_caller);
    vm.expectRevert("Pausable: paused");
    minterTrigger.mintAndTrigger{value: _value}(_to, _amount);
  }

  function testFuzz_RevertIf_Closed(address _to, uint256 _amount, uint256 _value, address _caller) public {
    _amount = _boundToRealisticAmount(_amount);
    _value = _boundTriggerValue(_value);

    vm.prank(admin);
    minterTrigger.close();

    vm.deal(_caller, _value);
    vm.prank(_caller);
    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    minterTrigger.mintAndTrigger{value: _value}(_to, _amount);
  }

  function testFuzz_RevertIf_FunctionCallFails(uint256 _amount, uint256 _ethValue, address _caller) public {
    _amount = _boundToRealisticAmount(_amount);
    _ethValue = _boundTriggerValue(_ethValue);

    address[] memory _targets = new address[](1);
    _targets[0] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeWithSelector(mockTarget.revertFunction.selector);

    uint256[] memory _values = new uint256[](1);
    _values[0] = _ethValue;

    ZkMinterTriggerV1 failTrigger =
      new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);

    // Allow failTrigger to mint on the underlying cappedMinter and grant a caller minter role.
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(failTrigger));
    vm.prank(admin);
    failTrigger.grantRole(MINTER_ROLE, _caller);

    vm.deal(_caller, _ethValue);
    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterTriggerV1.ZkMinterTriggerV1__TriggerCallFailed.selector, 0, address(mockTarget))
    );
    vm.prank(_caller);
    failTrigger.mintAndTrigger{value: _ethValue}(address(failTrigger), _amount);
  }

  function testFuzz_RevertIf_TargetHasNoCode(
    address _noCodeTarget,
    uint256 _amount,
    uint256 _ethValue,
    address _caller
  ) public {
    _amount = _boundToRealisticAmount(_amount);
    _ethValue = _boundTriggerValue(_ethValue);
    _assumeSafeAddress(_caller);
    vm.assume(_noCodeTarget.code.length == 0);

    address[] memory _targets = new address[](1);
    _targets[0] = _noCodeTarget;
    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = bytes("");
    uint256[] memory _values = new uint256[](1);
    _values[0] = _ethValue;

    ZkMinterTriggerV1 _noCodeTrigger =
      new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(_noCodeTrigger));
    vm.prank(admin);
    _noCodeTrigger.grantRole(MINTER_ROLE, _caller);
    vm.deal(_caller, _ethValue);

    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterTriggerV1.ZkMinterTriggerV1__NoCodeAtTarget.selector, 0, _noCodeTarget)
    );
    vm.prank(_caller);
    _noCodeTrigger.mintAndTrigger{value: _ethValue}(address(_noCodeTrigger), _amount);
  }

  function testFuzz_TokensTransferredAndCallExecuted(
    address _recipient,
    uint256 _amount,
    uint256 _ethValue,
    uint256 _setValue,
    address _caller
  ) public {
    _amount = _boundToRealisticAmount(_amount);
    _ethValue = _boundTriggerValue(_ethValue);
    vm.assume(_recipient != address(0));
    uint256 _initialRecipientBalance = token.balanceOf(_recipient);

    // Configure multi-step trigger: ERC20 transfer then mock target call with ETH
    address[] memory _targets = new address[](2);
    _targets[0] = address(token);
    _targets[1] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](2);
    _calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount);
    _calldatas[1] = abi.encodeWithSelector(mockTarget.setValue.selector, _setValue);

    uint256[] memory _values = new uint256[](2);
    _values[0] = 0;
    _values[1] = _ethValue;

    ZkMinterTriggerV1 multiTrigger =
      new ZkMinterTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);

    // Set up role.
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(multiTrigger));
    vm.prank(admin);
    multiTrigger.grantRole(MINTER_ROLE, _caller);

    // Execute mint and trigger.
    vm.deal(_caller, _ethValue);
    vm.prank(_caller);
    multiTrigger.mintAndTrigger{value: _ethValue}(address(multiTrigger), _amount);

    // Verify call and ETH transfer.
    assertEq(mockTarget.value(), _setValue);
    assertEq(mockTarget.called(), true);
    assertEq(mockTarget.lastCaller(), address(multiTrigger));
    assertEq(address(mockTarget).balance, _ethValue);

    // Verify token transfer from trigger to recipient.
    assertEq(token.balanceOf(address(multiTrigger)), 0);
    assertEq(token.balanceOf(_recipient), _initialRecipientBalance + _amount);
  }
}

contract RecoverTokens is ZkMinterTriggerV1Test {
  address public ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

  function testFuzz_SendsTokensToRecoveryAddress(address _minter, uint256 _amount) public {
    _grantCappedMinterRole(_minter);
    _grantTriggerMinterRole(_minter);
    _amount = _boundToRealisticAmount(_amount);
    vm.prank(_minter);
    minterTrigger.mint(address(minterTrigger), _amount);

    vm.prank(admin);
    minterTrigger.recoverTokens(address(token), _amount);

    assertEq(token.balanceOf(address(minterTrigger)), 0);
    assertEq(token.balanceOf(recoveryAddress), _amount);
  }

  function testFuzz_SendsETHToRecoveryAddress(uint256 _amount) public {
    _amount = _boundToRealisticAmount(_amount);
    vm.deal(address(minterTrigger), _amount);

    vm.prank(admin);
    minterTrigger.recoverTokens(ETH, _amount);

    assertEq(address(minterTrigger).balance, 0);
    assertEq(address(recoveryAddress).balance, _amount);
  }

  function testFuzz_EmitsTokensRecoveredEvent(address _minter, uint256 _amount) public {
    _grantCappedMinterRole(_minter);
    _grantTriggerMinterRole(_minter);
    _amount = _boundToRealisticAmount(_amount);
    vm.prank(_minter);
    minterTrigger.mint(address(minterTrigger), _amount);

    vm.prank(admin);
    vm.expectEmit();
    emit ZkMinterTriggerV1.TokensRecovered(admin, address(token), _amount, recoveryAddress);
    minterTrigger.recoverTokens(address(token), _amount);
  }

  function testFuzz_EmitsTokensRecoveredEventForETH(uint256 _amount) public {
    _amount = _boundToRealisticAmount(_amount);
    vm.deal(address(minterTrigger), _amount);

    vm.prank(admin);
    vm.expectEmit();
    emit ZkMinterTriggerV1.TokensRecovered(admin, ETH, _amount, recoveryAddress);
    minterTrigger.recoverTokens(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), _amount);
  }

  function testFuzz_RevertIf_CallerIsNotAdmin(address _nonAdmin, address _minter, address _token, uint256 _amount)
    public
  {
    _grantCappedMinterRole(_minter);
    _grantTriggerMinterRole(_minter);
    vm.assume(_nonAdmin != admin);

    _amount = _boundToRealisticAmount(_amount);
    vm.prank(_minter);
    minterTrigger.mint(address(minterTrigger), _amount);

    vm.prank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    minterTrigger.recoverTokens(_token, _amount);
  }

  function testFuzz_RevertIf_CallerIsNotAdminWhenRecoveringETH(address _nonAdmin, uint256 _amount) public {
    _amount = _boundToRealisticAmount(_amount);
    vm.deal(address(minterTrigger), _amount);

    vm.prank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    minterTrigger.recoverTokens(ETH, _amount);
  }

  function testFuzz_CanRecoverTokensAfterPaused(address _minter, uint256 _amount) public {
    _grantCappedMinterRole(_minter);
    _grantTriggerMinterRole(_minter);
    _amount = _boundToRealisticAmount(_amount);
    vm.prank(_minter);
    minterTrigger.mint(address(minterTrigger), _amount);

    vm.prank(admin);
    minterTrigger.pause();

    vm.prank(admin);
    minterTrigger.recoverTokens(address(token), _amount);
    assertEq(token.balanceOf(address(minterTrigger)), 0);
    assertEq(token.balanceOf(recoveryAddress), _amount);
  }

  function testFuzz_CanRecoverTokensAfterPausedForETH(uint256 _amount) public {
    _amount = _boundToRealisticAmount(_amount);
    vm.deal(address(minterTrigger), _amount);

    vm.prank(admin);
    minterTrigger.pause();

    vm.prank(admin);
    minterTrigger.recoverTokens(ETH, _amount);
    assertEq(address(minterTrigger).balance, 0);
    assertEq(address(recoveryAddress).balance, _amount);
  }

  function testFuzz_CanRecoverTokensAfterClosed(address _minter, uint256 _amount) public {
    _grantCappedMinterRole(_minter);
    _grantTriggerMinterRole(_minter);
    _amount = _boundToRealisticAmount(_amount);
    vm.prank(_minter);
    minterTrigger.mint(address(minterTrigger), _amount);

    vm.prank(admin);
    minterTrigger.close();

    vm.prank(admin);
    minterTrigger.recoverTokens(address(token), _amount);
    assertEq(token.balanceOf(address(minterTrigger)), 0);
    assertEq(token.balanceOf(recoveryAddress), _amount);
  }

  function testFuzz_CanRecoverTokensAfterClosedForETH(uint256 _amount) public {
    _amount = _boundToRealisticAmount(_amount);
    vm.deal(address(minterTrigger), _amount);

    vm.prank(admin);
    minterTrigger.close();

    vm.prank(admin);
    minterTrigger.recoverTokens(ETH, _amount);
    assertEq(address(minterTrigger).balance, 0);
    assertEq(address(recoveryAddress).balance, _amount);
  }
}
