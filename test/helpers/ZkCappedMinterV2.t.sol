// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/helpers/ZkTokenTest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkCappedMinterV2} from "lib/zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";

contract ZkCappedMinterV2Test is ZkTokenTest {
  ZkCappedMinterV2 public cappedMinter;
  uint256 constant DEFAULT_CAP = 100_000_000e18;
  uint48 DEFAULT_START_TIME;
  uint48 DEFAULT_EXPIRATION_TIME;

  address cappedMinterAdmin = makeAddr("cappedMinterAdmin");

  function setUp() public virtual override {
    super.setUp();

    DEFAULT_START_TIME = uint48(vm.getBlockTimestamp());
    DEFAULT_EXPIRATION_TIME = uint48(DEFAULT_START_TIME + 3 days);

    cappedMinter =
      _createCappedMinter(address(token), cappedMinterAdmin, DEFAULT_CAP, DEFAULT_START_TIME, DEFAULT_EXPIRATION_TIME);

    _grantMinterRoleToCappedMinter(address(cappedMinter));
  }

  function _grantMinterRoleToCappedMinter(address _cappedMinter) internal {
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_cappedMinter));
  }

  function _createCappedMinter(
    address _mintable,
    address _admin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime
  ) internal returns (ZkCappedMinterV2) {
    return new ZkCappedMinterV2(IMintable(_mintable), _admin, _cap, _startTime, _expirationTime);
  }

  function _boundToValidTimeControls(uint48 _startTime, uint48 _expirationTime) internal view returns (uint48, uint48) {
    // Using uint32 for time controls to prevent overflows in the ZkToken contract regarding block numbers needing to be
    // casted to uint32.
    _startTime = uint48(bound(_startTime, vm.getBlockTimestamp(), type(uint32).max - 1));
    _expirationTime = uint48(bound(_expirationTime, _startTime + 1, type(uint32).max));
    return (_startTime, _expirationTime);
  }

  function _grantMinterRole(ZkCappedMinterV2 _cappedMinter, address _cappedMinterAdmin, address _minter) internal {
    vm.prank(_cappedMinterAdmin);
    _cappedMinter.grantRole(MINTER_ROLE, _minter);
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
