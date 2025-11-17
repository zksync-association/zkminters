// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HashIsNonZero} from "era-contracts/system-contracts/contracts/SystemContractErrors.sol";

import {ZkMinterTriggerV1Factory} from "src/ZkMinterTriggerV1Factory.sol";
import {ZkMinterTriggerV1} from "src/ZkMinterTriggerV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

contract ZkMinterTriggerV1FactoryTest is Test {
  using stdJson for string;

  bytes32 bytecodeHash;
  ZkMinterTriggerV1Factory factory;

  function setUp() public virtual {
    string memory _root = vm.projectRoot();
    string memory _path = string.concat(_root, "/zkout/ZkMinterTriggerV1.sol/ZkMinterTriggerV1.json");
    string memory _json = vm.readFile(_path);
    bytecodeHash = bytes32(stdJson.readBytes(_json, ".hash"));

    factory = new ZkMinterTriggerV1Factory(bytecodeHash);
  }

  function _assumeValidAddresses(address _admin, address _recovery) internal view {
    vm.assume(_admin != address(0) && _admin != address(factory));
    vm.assume(_recovery != address(0) && _recovery != address(factory));
  }

  function _buildSingleTriggerParams(address _target, bytes memory _calldata, uint256 _value)
    internal
    pure
    returns (address[] memory, bytes[] memory, uint256[] memory)
  {
    address[] memory _targets = new address[](1);
    bytes[] memory _calldatas = new bytes[](1);
    uint256[] memory _values = new uint256[](1);

    _targets[0] = _target;
    _calldatas[0] = _calldata;
    _values[0] = _value;

    return (_targets, _calldatas, _values);
  }
}

contract CreateMinter is ZkMinterTriggerV1FactoryTest {
  function testFuzz_CreatesNewMinterTrigger(
    IMintable _mintable,
    address _admin,
    address _target,
    bytes memory _calldata,
    uint256 _value,
    address _recovery,
    uint256 _saltNonce
  ) public {
    _assumeValidAddresses(_admin, _recovery);

    (address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address _minterAddress =
      factory.createMinter(_mintable, _admin, _targets, _calldatas, _values, _recovery, _saltNonce);

    ZkMinterTriggerV1 _minter = ZkMinterTriggerV1(payable(_minterAddress));

    assertEq(address(_minter.mintable()), address(_mintable));
    assertTrue(_minter.hasRole(_minter.DEFAULT_ADMIN_ROLE(), _admin));
    assertTrue(_minter.hasRole(_minter.PAUSER_ROLE(), _admin));
    assertEq(_minter.targets(0), _target);
    assertEq(_minter.calldatas(0), _calldata);
    assertEq(_minter.values(0), _value);
    assertEq(_minter.RECOVERY_ADDRESS(), _recovery);
  }

  function testFuzz_EmitsMinterTriggerCreatedEvent(
    IMintable _mintable,
    address _admin,
    address _target,
    bytes memory _calldata,
    uint256 _value,
    address _recovery,
    uint256 _saltNonce
  ) public {
    _assumeValidAddresses(_admin, _recovery);

    (address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address _expectedAddress =
      factory.getMinter(_mintable, _admin, _targets, _calldatas, _values, _recovery, _saltNonce);

    vm.expectEmit();
    emit ZkMinterTriggerV1Factory.MinterTriggerCreated(
      _expectedAddress, _mintable, _admin, _targets, _calldatas, _values, _recovery
    );

    factory.createMinter(_mintable, _admin, _targets, _calldatas, _values, _recovery, _saltNonce);
  }

  function testFuzz_CreatesNewMinterTriggerWithBytesArgs(
    IMintable _mintable,
    address _admin,
    address _target,
    bytes memory _calldata,
    uint256 _value,
    address _recovery,
    uint256 _saltNonce
  ) public {
    _assumeValidAddresses(_admin, _recovery);

    (address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address _minterAddress =
      factory.createMinter(_mintable, abi.encode(_admin, _targets, _calldatas, _values, _recovery, _saltNonce));

    ZkMinterTriggerV1 _minter = ZkMinterTriggerV1(payable(_minterAddress));

    assertEq(address(_minter.mintable()), address(_mintable));
    assertTrue(_minter.hasRole(_minter.DEFAULT_ADMIN_ROLE(), _admin));
    assertTrue(_minter.hasRole(_minter.PAUSER_ROLE(), _admin));
    assertEq(_minter.targets(0), _target);
    assertEq(_minter.calldatas(0), _calldata);
    assertEq(_minter.values(0), _value);
    assertEq(_minter.RECOVERY_ADDRESS(), _recovery);
  }

  function testFuzz_EmitsMinterTriggerCreatedEventWithBytesArgs(
    IMintable _mintable,
    address _admin,
    address _target,
    bytes memory _calldata,
    uint256 _value,
    address _recovery,
    uint256 _saltNonce
  ) public {
    _assumeValidAddresses(_admin, _recovery);

    (address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address _expectedAddress =
      factory.getMinter(_mintable, _admin, _targets, _calldatas, _values, _recovery, _saltNonce);

    vm.expectEmit();
    emit ZkMinterTriggerV1Factory.MinterTriggerCreated(
      _expectedAddress, _mintable, _admin, _targets, _calldatas, _values, _recovery
    );

    factory.createMinter(_mintable, abi.encode(_admin, _targets, _calldatas, _values, _recovery, _saltNonce));
  }

  function testFuzz_RevertIf_CreatingDuplicateMinter(
    IMintable _mintable,
    address _admin,
    address _target,
    bytes memory _calldata,
    uint256 _value,
    address _recovery,
    uint256 _saltNonce
  ) public {
    _assumeValidAddresses(_admin, _recovery);

    (address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    factory.createMinter(_mintable, _admin, _targets, _calldatas, _values, _recovery, _saltNonce);

    vm.expectRevert(abi.encodeWithSelector(HashIsNonZero.selector, bytecodeHash));
    factory.createMinter(_mintable, _admin, _targets, _calldatas, _values, _recovery, _saltNonce);
  }

  function test_RevertIf_ArrayLengthMismatch() public {
    address[] memory _targets = new address[](2);
    _targets[0] = address(0x1);
    _targets[1] = address(0x2);

    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = hex"1234";

    uint256[] memory _values = new uint256[](1);
    _values[0] = 1 ether;

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__ArrayLengthMismatch.selector);
    factory.createMinter(IMintable(address(0x1234)), address(0x1), _targets, _calldatas, _values, address(0x2), 1);
  }

  function test_RevertIf_CreatingMinterWithZeroAdmin() public {
    (address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values) =
      _buildSingleTriggerParams(address(0x1), hex"", 0);

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__InvalidAdmin.selector);
    factory.createMinter(IMintable(address(0x1234)), address(0), _targets, _calldatas, _values, address(0x2), 1);
  }

  function test_RevertIf_CreatingMinterWithZeroRecovery() public {
    (address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values) =
      _buildSingleTriggerParams(address(0x1), hex"", 0);

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__InvalidRecoveryAddress.selector);
    factory.createMinter(IMintable(address(0x1234)), address(0x1), _targets, _calldatas, _values, address(0), 1);
  }
}

contract GetMinter is ZkMinterTriggerV1FactoryTest {
  function testFuzz_ReturnsCorrectMinterAddress(
    IMintable _mintable,
    address _admin,
    address _target,
    bytes memory _calldata,
    uint256 _value,
    address _recovery,
    uint256 _saltNonce
  ) public {
    _assumeValidAddresses(_admin, _recovery);

    (address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address _expected = factory.getMinter(_mintable, _admin, _targets, _calldatas, _values, _recovery, _saltNonce);

    address _deployed = factory.createMinter(_mintable, _admin, _targets, _calldatas, _values, _recovery, _saltNonce);

    assertEq(_deployed, _expected);
  }
}
