// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkMinterERC1155EligibilityV1Factory} from "src/ZkMinterERC1155EligibilityV1Factory.sol";
import {ZkMinterERC1155EligibilityV1} from "src/ZkMinterERC1155EligibilityV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HashIsNonZero} from "era-contracts/system-contracts/contracts/SystemContractErrors.sol";
import {FakeERC1155} from "test/fakes/FakeERC1155.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract ZkMinterERC1155EligibilityV1FactoryTest is Test {
  bytes32 bytecodeHash;
  ZkMinterERC1155EligibilityV1Factory factory;
  FakeERC1155 fakeERC1155;

  function setUp() public virtual {
    // Read the bytecode hash from the JSON file
    string memory root = vm.projectRoot();
    string memory path =
      string.concat(root, "/zkout/ZkMinterERC1155EligibilityV1.sol/ZkMinterERC1155EligibilityV1.json");
    string memory json = vm.readFile(path);
    bytecodeHash = bytes32(stdJson.readBytes(json, ".hash"));

    factory = new ZkMinterERC1155EligibilityV1Factory(bytecodeHash);
    fakeERC1155 = new FakeERC1155();
  }

  function _assumeValidAddress(address _addr) internal view {
    vm.assume(_addr != address(0) && _addr != address(factory));
  }

  function _assumeValidBalanceThreshold(uint256 _balanceThreshold) internal pure {
    vm.assume(_balanceThreshold != 0);
  }

  function _mockSupportsInterfaceCall(address _target, bool _isSupported) internal {
    vm.mockCall(
      _target,
      abi.encodeWithSelector(bytes4(keccak256("supportsInterface(bytes4)")), type(IERC1155).interfaceId),
      abi.encode(_isSupported)
    );
  }
}

contract CreateMinterERC1155 is ZkMinterERC1155EligibilityV1FactoryTest {
  function testFuzz_CreatesNewMinterERC1155(
    IMintable _mintable,
    address _minterAdmin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidBalanceThreshold(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    address _minterAddress =
      factory.createMinter(_mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);

    ZkMinterERC1155EligibilityV1 _minter = ZkMinterERC1155EligibilityV1(_minterAddress);

    assertEq(address(_minter.mintable()), address(_mintable));
    assertTrue(_minter.hasRole(_minter.DEFAULT_ADMIN_ROLE(), _minterAdmin));
    assertEq(address(_minter.ERC1155()), _erc1155);
    assertEq(_minter.tokenId(), _tokenId);
    assertEq(_minter.balanceThreshold(), _balanceThreshold);
  }

  function testFuzz_EmitsMinterERC1155EligibilityCreatedEvent(
    IMintable _mintable,
    address _minterAdmin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidBalanceThreshold(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    address _expectedMinterAddress =
      factory.getMinter(_mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);

    vm.expectEmit();
    emit ZkMinterERC1155EligibilityV1Factory.MinterERC1155EligibilityCreated(
      _expectedMinterAddress, _mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold
    );

    factory.createMinter(_mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);
  }

  function testFuzz_CreatesNewMinterERC1155WithBytesArgs(
    IMintable _mintable,
    address _minterAdmin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidBalanceThreshold(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    address _minterAddress =
      factory.createMinter(_mintable, abi.encode(_minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce));

    ZkMinterERC1155EligibilityV1 _minter = ZkMinterERC1155EligibilityV1(_minterAddress);

    assertEq(address(_minter.mintable()), address(_mintable));
    assertTrue(_minter.hasRole(_minter.DEFAULT_ADMIN_ROLE(), _minterAdmin));
    assertEq(address(_minter.ERC1155()), _erc1155);
    assertEq(_minter.tokenId(), _tokenId);
    assertEq(_minter.balanceThreshold(), _balanceThreshold);
  }

  function testFuzz_EmitsMinterERC1155EligibilityCreatedEventWithBytesArgs(
    IMintable _mintable,
    address _minterAdmin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidBalanceThreshold(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    address _expectedMinterAddress =
      factory.getMinter(_mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);

    vm.expectEmit();
    emit ZkMinterERC1155EligibilityV1Factory.MinterERC1155EligibilityCreated(
      _expectedMinterAddress, _mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold
    );

    factory.createMinter(_mintable, abi.encode(_minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce));
  }

  function testFuzz_RevertIf_CreatingDuplicateMinter(
    IMintable _mintable,
    address _minterAdmin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidBalanceThreshold(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    factory.createMinter(_mintable, abi.encode(_minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce));

    vm.expectRevert(abi.encodeWithSelector(HashIsNonZero.selector, bytecodeHash));
    factory.createMinter(_mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);
  }

  function testFuzz_RevertIf_CreatingMinterWithZeroAdmin(
    IMintable _mintable,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeValidBalanceThreshold(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    vm.expectRevert(
      abi.encodeWithSelector(ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InvalidZeroAddress.selector)
    );
    factory.createMinter(_mintable, address(0), _erc1155, _tokenId, _balanceThreshold, _saltNonce);
  }

  function testFuzz_RevertIf_CreatingMinterWithZeroBalanceThreshold(
    IMintable _mintable,
    address _minterAdmin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);

    _mockSupportsInterfaceCall(_erc1155, true);

    vm.expectRevert(
      abi.encodeWithSelector(
        ZkMinterERC1155EligibilityV1.ZkMinterERC1155EligibilityV1__InvalidBalanceThreshold.selector
      )
    );
    factory.createMinter(_mintable, _minterAdmin, _erc1155, _tokenId, 0, _saltNonce);
  }
}

contract GetMinter is ZkMinterERC1155EligibilityV1FactoryTest {
  function testFuzz_ReturnsCorrectMinterAddress(
    IMintable _mintable,
    address _minterAdmin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidBalanceThreshold(_balanceThreshold);

    _mockSupportsInterfaceCall(_erc1155, true);

    address _expectedMinterAddress =
      factory.getMinter(_mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);
    address _minterAddress =
      factory.createMinter(_mintable, abi.encode(_minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce));

    assertEq(_minterAddress, _expectedMinterAddress);
  }

  function testFuzz_GetMinterWithoutDeployment(
    IMintable _mintable,
    address _minterAdmin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) public {
    _assumeValidAddress(_minterAdmin);
    _assumeValidBalanceThreshold(_balanceThreshold);

    address _expectedMinterAddress =
      factory.getMinter(_mintable, _minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);

    uint256 _codeSize;
    assembly {
      _codeSize := extcodesize(_expectedMinterAddress)
    }
    assertEq(_codeSize, 0);

    _mockSupportsInterfaceCall(_erc1155, true);

    factory.createMinter(_mintable, abi.encode(_minterAdmin, _erc1155, _tokenId, _balanceThreshold, _saltNonce));
  }
}

contract BytecodeHash is ZkMinterERC1155EligibilityV1FactoryTest {
  function test_BytecodeHashIsSetCorrectly() public view {
    assertEq(factory.BYTECODE_HASH(), bytecodeHash);
  }
}
