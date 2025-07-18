// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkMinterDelayV1Factory} from "src/ZkMinterDelayV1Factory.sol";
import {ZkMinterDelayV1} from "src/ZkMinterDelayV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HashIsNonZero} from "era-contracts/system-contracts/contracts/SystemContractErrors.sol";

contract ZkMinterDelayV1FactoryTest is Test {
  bytes32 bytecodeHash;
  ZkMinterDelayV1Factory factory;

  function setUp() public virtual {
    // Read the bytecode hash from the JSON file
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/zkout/ZkMinterDelayV1.sol/ZkMinterDelayV1.json");
    string memory json = vm.readFile(path);
    bytecodeHash = bytes32(stdJson.readBytes(json, ".hash"));

    factory = new ZkMinterDelayV1Factory(bytecodeHash);
  }

  function _assumeValidAddress(address _addr) internal view {
    vm.assume(_addr != address(0) && _addr != address(factory));
  }

  function _assumeValidMintable(IMintable _mintable) internal pure {
    vm.assume(address(_mintable) != address(0));
  }

  function _assumeValidMintDelay(uint48 _mintDelay) internal pure {
    vm.assume(_mintDelay != 0);
  }
}

contract CreateMinterDelay is ZkMinterDelayV1FactoryTest {
  function testFuzz_CreatesNewMinterDelay(
    IMintable _mintable,
    address _minterAdmin,
    uint48 _mintDelay,
    uint256 _saltNonce
  ) public {
    _assumeValidMintable(_mintable);
    _assumeValidAddress(_minterAdmin);
    _assumeValidMintDelay(_mintDelay);

    address _minterAddress = factory.createMinter(_mintable, _minterAdmin, _mintDelay, _saltNonce);

    ZkMinterDelayV1 _minter = ZkMinterDelayV1(_minterAddress);

    assertEq(address(_minter.mintable()), address(_mintable));
    assertTrue(_minter.hasRole(_minter.DEFAULT_ADMIN_ROLE(), _minterAdmin));
    assertEq(_minter.mintDelay(), _mintDelay);
  }

  function testFuzz_EmitsMinterDelayCreatedEvent(
    IMintable _mintable,
    address _minterAdmin,
    uint48 _mintDelay,
    uint256 _saltNonce
  ) public {
    _assumeValidMintable(_mintable);
    _assumeValidAddress(_minterAdmin);
    _assumeValidMintDelay(_mintDelay);

    address _expectedMinterAddress = factory.getMinter(_mintable, _minterAdmin, _mintDelay, _saltNonce);

    vm.expectEmit();
    emit ZkMinterDelayV1Factory.MinterDelayCreated(_expectedMinterAddress, _mintable, _minterAdmin, _mintDelay);

    factory.createMinter(_mintable, _minterAdmin, _mintDelay, _saltNonce);
  }

  function testFuzz_CreatesNewMinterDelayWithBytesArgs(
    IMintable _mintable,
    address _minterAdmin,
    uint48 _mintDelay,
    uint256 _saltNonce
  ) public {
    _assumeValidMintable(_mintable);
    _assumeValidAddress(_minterAdmin);
    _assumeValidMintDelay(_mintDelay);

    address _minterAddress = factory.createMinter(_mintable, abi.encode(_minterAdmin, _mintDelay, _saltNonce));

    ZkMinterDelayV1 _minter = ZkMinterDelayV1(_minterAddress);

    assertEq(address(_minter.mintable()), address(_mintable));
    assertEq(_minter.hasRole(_minter.DEFAULT_ADMIN_ROLE(), _minterAdmin), true);
    assertEq(_minter.mintDelay(), _mintDelay);
  }

  function testFuzz_EmitsMinterDelayCreatedEventWithBytesArgs(
    IMintable _mintable,
    address _minterAdmin,
    uint48 _mintDelay,
    uint256 _saltNonce
  ) public {
    _assumeValidMintable(_mintable);
    _assumeValidAddress(_minterAdmin);
    _assumeValidMintDelay(_mintDelay);

    address _expectedMinterAddress = factory.getMinter(_mintable, _minterAdmin, _mintDelay, _saltNonce);

    vm.expectEmit();
    emit ZkMinterDelayV1Factory.MinterDelayCreated(_expectedMinterAddress, _mintable, _minterAdmin, _mintDelay);

    factory.createMinter(_mintable, abi.encode(_minterAdmin, _mintDelay, _saltNonce));
  }

  function testFuzz_RevertIf_CreatingDuplicateMinter(
    IMintable _mintable,
    address _minterAdmin,
    uint48 _mintDelay,
    uint256 _saltNonce
  ) public {
    _assumeValidMintable(_mintable);
    _assumeValidAddress(_minterAdmin);
    _assumeValidMintDelay(_mintDelay);

    factory.createMinter(_mintable, abi.encode(_minterAdmin, _mintDelay, _saltNonce));

    vm.expectRevert(abi.encodeWithSelector(HashIsNonZero.selector, bytecodeHash));
    factory.createMinter(_mintable, _minterAdmin, _mintDelay, _saltNonce);
  }

  function testFuzz_RevertIf_CreatingMinterWithZeroAdmin(IMintable _mintable, uint48 _mintDelay, uint256 _saltNonce)
    public
  {
    _assumeValidMintDelay(_mintDelay);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__InvalidZeroAddress.selector));
    factory.createMinter(_mintable, address(0), _mintDelay, _saltNonce);
  }

  function testFuzz_RevertIf_CreatingMinterWithZeroMintDelay(
    IMintable _mintable,
    address _minterAdmin,
    uint256 _saltNonce
  ) public {
    _assumeValidMintable(_mintable);
    _assumeValidAddress(_minterAdmin);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__InvalidMintDelay.selector));
    factory.createMinter(_mintable, _minterAdmin, 0, _saltNonce);
  }

  function testFuzz_RevertIf_CreatingMinterWithZeroMintable(address _minterAdmin, uint48 _mintDelay, uint256 _saltNonce)
    public
  {
    _assumeValidAddress(_minterAdmin);
    _assumeValidMintDelay(_mintDelay);
    vm.expectRevert(abi.encodeWithSelector(ZkMinterDelayV1.ZkMinterDelayV1__InvalidZeroAddress.selector));
    factory.createMinter(IMintable(address(0)), _minterAdmin, _mintDelay, _saltNonce);
  }
}

contract GetMinter is ZkMinterDelayV1FactoryTest {
  function testFuzz_ReturnsCorrectMinterAddress(
    IMintable _mintable,
    address _minterAdmin,
    uint48 _mintDelay,
    uint256 _saltNonce
  ) public {
    _assumeValidMintable(_mintable);
    _assumeValidAddress(_minterAdmin);
    _assumeValidMintDelay(_mintDelay);

    address _expectedMinterAddress = factory.getMinter(_mintable, _minterAdmin, _mintDelay, _saltNonce);
    address _minterAddress = factory.createMinter(_mintable, abi.encode(_minterAdmin, _mintDelay, _saltNonce));

    assertEq(_minterAddress, _expectedMinterAddress);
  }

  function testFuzz_GetMinterWithoutDeployment(
    IMintable _mintable,
    address _minterAdmin,
    uint48 _mintDelay,
    uint256 _saltNonce
  ) public {
    _assumeValidMintable(_mintable);
    _assumeValidAddress(_minterAdmin);
    _assumeValidMintDelay(_mintDelay);

    address _expectedMinterAddress = factory.getMinter(_mintable, _minterAdmin, _mintDelay, _saltNonce);

    uint256 _codeSize;
    assembly {
      _codeSize := extcodesize(_expectedMinterAddress)
    }
    assertEq(_codeSize, 0);

    factory.createMinter(_mintable, abi.encode(_minterAdmin, _mintDelay, _saltNonce));
  }
}
