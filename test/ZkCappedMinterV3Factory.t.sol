// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HashIsNonZero} from "era-contracts/system-contracts/contracts/SystemContractErrors.sol";

import {ZkCappedMinterV3Factory} from "src/ZkCappedMinterV3Factory.sol";
import {ZkCappedMinterV3} from "src/ZkCappedMinterV3.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

contract ZkCappedMinterV3FactoryTest is Test {
  using stdJson for string;

  bytes32 bytecodeHash;
  ZkCappedMinterV3Factory factory;

  function setUp() public virtual {
    string memory _root = vm.projectRoot();
    string memory _path = string.concat(_root, "/zkout/ZkCappedMinterV3.sol/ZkCappedMinterV3.json");
    string memory _json = vm.readFile(_path);
    bytecodeHash = bytes32(stdJson.readBytes(_json, ".hash"));

    factory = new ZkCappedMinterV3Factory(bytecodeHash);
  }

  function _assumeValidAddress(address _addr) internal view {
    vm.assume(_addr != address(0) && _addr != address(factory));
  }

  function _assumeValidTime(uint48 _startTime, uint48 _expirationTime) internal view {
    vm.assume(_startTime >= block.timestamp);
    vm.assume(_expirationTime > _startTime);
    vm.assume(_startTime < type(uint48).max - 1);
    vm.assume(_expirationTime < type(uint48).max);
  }
}

contract CreateCappedMinter is ZkCappedMinterV3FactoryTest {
  function testFuzz_CreatesNewCappedMinter(
    IMintable _mintable,
    address _minterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidTime(_startTime, _expirationTime);

    address _minterAddress =
      factory.createMinter(_mintable, _minterAdmin, _cap, _startTime, _expirationTime, _saltNonce);

    ZkCappedMinterV3 _minter = ZkCappedMinterV3(_minterAddress);

    assertEq(address(_minter.mintable()), address(_mintable));
    assertTrue(_minter.hasRole(_minter.DEFAULT_ADMIN_ROLE(), _minterAdmin));
    assertEq(_minter.CAP(), _cap);
    assertEq(_minter.START_TIME(), _startTime);
    assertEq(_minter.EXPIRATION_TIME(), _expirationTime);
  }

  function testFuzz_EmitsMinterCappedCreatedEvent(
    IMintable _mintable,
    address _minterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidTime(_startTime, _expirationTime);

    address _expectedMinterAddress =
      factory.getMinter(_mintable, _minterAdmin, _cap, _startTime, _expirationTime, _saltNonce);

    vm.expectEmit();
    emit ZkCappedMinterV3Factory.MinterCappedCreated(
      _expectedMinterAddress, _mintable, _minterAdmin, _cap, _startTime, _expirationTime
    );

    factory.createMinter(_mintable, _minterAdmin, _cap, _startTime, _expirationTime, _saltNonce);
  }

  function testFuzz_CreatesNewCappedMinterWithBytesArgs(
    IMintable _mintable,
    address _minterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidTime(_startTime, _expirationTime);

    address _minterAddress =
      factory.createMinter(_mintable, abi.encode(_minterAdmin, _cap, _startTime, _expirationTime, _saltNonce));

    ZkCappedMinterV3 _minter = ZkCappedMinterV3(_minterAddress);

    assertEq(address(_minter.mintable()), address(_mintable));
    assertEq(_minter.hasRole(_minter.DEFAULT_ADMIN_ROLE(), _minterAdmin), true);
    assertEq(_minter.CAP(), _cap);
    assertEq(_minter.START_TIME(), _startTime);
    assertEq(_minter.EXPIRATION_TIME(), _expirationTime);
  }

  function testFuzz_EmitsMinterCappedCreatedEventWithBytesArgs(
    IMintable _mintable,
    address _minterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidTime(_startTime, _expirationTime);

    address _expectedMinterAddress =
      factory.getMinter(_mintable, _minterAdmin, _cap, _startTime, _expirationTime, _saltNonce);

    vm.expectEmit();
    emit ZkCappedMinterV3Factory.MinterCappedCreated(
      _expectedMinterAddress, _mintable, _minterAdmin, _cap, _startTime, _expirationTime
    );

    factory.createMinter(_mintable, abi.encode(_minterAdmin, _cap, _startTime, _expirationTime, _saltNonce));
  }

  function testFuzz_RevertIf_CreatingDuplicateMinter(
    IMintable _mintable,
    address _minterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidTime(_startTime, _expirationTime);

    factory.createMinter(_mintable, abi.encode(_minterAdmin, _cap, _startTime, _expirationTime, _saltNonce));

    vm.expectRevert(abi.encodeWithSelector(HashIsNonZero.selector, bytecodeHash));
    factory.createMinter(_mintable, _minterAdmin, _cap, _startTime, _expirationTime, _saltNonce);
  }
}

contract GetMinter is ZkCappedMinterV3FactoryTest {
  function testFuzz_ReturnsCorrectMinterAddress(
    IMintable _mintable,
    address _minterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidTime(_startTime, _expirationTime);

    address _expectedMinterAddress =
      factory.getMinter(_mintable, _minterAdmin, _cap, _startTime, _expirationTime, _saltNonce);
    address _minterAddress =
      factory.createMinter(_mintable, abi.encode(_minterAdmin, _cap, _startTime, _expirationTime, _saltNonce));

    assertEq(_minterAddress, _expectedMinterAddress);
  }
}
