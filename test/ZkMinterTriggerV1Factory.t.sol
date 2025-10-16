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
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/zkout/ZkMinterTriggerV1.sol/ZkMinterTriggerV1.json");
    string memory json = vm.readFile(path);
    bytecodeHash = bytes32(stdJson.readBytes(json, ".hash"));

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
    address[] memory targets = new address[](1);
    bytes[] memory calldatas = new bytes[](1);
    uint256[] memory values = new uint256[](1);

    targets[0] = _target;
    calldatas[0] = _calldata;
    values[0] = _value;

    return (targets, calldatas, values);
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

    (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address minterAddress = factory.createMinter(_mintable, _admin, targets, calldatas, values, _recovery, _saltNonce);

    ZkMinterTriggerV1 minter = ZkMinterTriggerV1(payable(minterAddress));

    assertEq(address(minter.mintable()), address(_mintable));
    assertTrue(minter.hasRole(minter.DEFAULT_ADMIN_ROLE(), _admin));
    assertTrue(minter.hasRole(minter.PAUSER_ROLE(), _admin));
    assertEq(minter.targets(0), _target);
    assertEq(minter.calldatas(0), _calldata);
    assertEq(minter.values(0), _value);
    assertEq(minter.RECOVERY_ADDRESS(), _recovery);
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

    (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address expectedAddress = factory.getMinter(_mintable, _admin, targets, calldatas, values, _recovery, _saltNonce);

    vm.expectEmit();
    emit ZkMinterTriggerV1Factory.MinterTriggerCreated(
      expectedAddress, _mintable, _admin, targets, calldatas, values, _recovery
    );

    factory.createMinter(_mintable, _admin, targets, calldatas, values, _recovery, _saltNonce);
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

    (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address minterAddress =
      factory.createMinter(_mintable, abi.encode(_admin, targets, calldatas, values, _recovery, _saltNonce));

    ZkMinterTriggerV1 minter = ZkMinterTriggerV1(payable(minterAddress));

    assertEq(address(minter.mintable()), address(_mintable));
    assertTrue(minter.hasRole(minter.DEFAULT_ADMIN_ROLE(), _admin));
    assertTrue(minter.hasRole(minter.PAUSER_ROLE(), _admin));
    assertEq(minter.targets(0), _target);
    assertEq(minter.calldatas(0), _calldata);
    assertEq(minter.values(0), _value);
    assertEq(minter.RECOVERY_ADDRESS(), _recovery);
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

    (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address expectedAddress = factory.getMinter(_mintable, _admin, targets, calldatas, values, _recovery, _saltNonce);

    vm.expectEmit();
    emit ZkMinterTriggerV1Factory.MinterTriggerCreated(
      expectedAddress, _mintable, _admin, targets, calldatas, values, _recovery
    );

    factory.createMinter(_mintable, abi.encode(_admin, targets, calldatas, values, _recovery, _saltNonce));
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

    (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    factory.createMinter(_mintable, _admin, targets, calldatas, values, _recovery, _saltNonce);

    vm.expectRevert(abi.encodeWithSelector(HashIsNonZero.selector, bytecodeHash));
    factory.createMinter(_mintable, _admin, targets, calldatas, values, _recovery, _saltNonce);
  }

  function test_RevertIf_ArrayLengthMismatch() public {
    address[] memory targets = new address[](2);
    targets[0] = address(0x1);
    targets[1] = address(0x2);

    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = hex"1234";

    uint256[] memory values = new uint256[](1);
    values[0] = 1 ether;

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__ArrayLengthMismatch.selector);
    factory.createMinter(IMintable(address(0x1234)), address(0x1), targets, calldatas, values, address(0x2), 1);
  }

  function test_RevertIf_CreatingMinterWithZeroAdmin() public {
    (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) =
      _buildSingleTriggerParams(address(0x1), hex"", 0);

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__InvalidAdmin.selector);
    factory.createMinter(IMintable(address(0x1234)), address(0), targets, calldatas, values, address(0x2), 1);
  }

  function test_RevertIf_CreatingMinterWithZeroRecovery() public {
    (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) =
      _buildSingleTriggerParams(address(0x1), hex"", 0);

    vm.expectRevert(ZkMinterTriggerV1.ZkMinterTriggerV1__InvalidRecoveryAddress.selector);
    factory.createMinter(IMintable(address(0x1234)), address(0x1), targets, calldatas, values, address(0), 1);
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

    (address[] memory targets, bytes[] memory calldatas, uint256[] memory values) =
      _buildSingleTriggerParams(_target, _calldata, _value);

    address expected = factory.getMinter(_mintable, _admin, targets, calldatas, values, _recovery, _saltNonce);

    address deployed = factory.createMinter(_mintable, _admin, targets, calldatas, values, _recovery, _saltNonce);

    assertEq(deployed, expected);
  }
}
