// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/helpers/ZkTokenTest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkCappedMinterV2} from "lib/zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";

contract ZkBaseTest is ZkTokenTest {
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

  // Generic assume helpers for common validation patterns
  function _assumeSafeAddress(address _address) internal pure {
    vm.assume(_address != address(0));
  }

  function _assumeValidAddress(address _addr) internal view {
    vm.assume(_addr != address(0) && _addr != address(this));
  }

  function _assumeSafeMintable(IMintable _mintable) internal pure {
    vm.assume(address(_mintable) != address(0));
  }

  function _assumeSafeUint(uint256 _value) internal pure {
    vm.assume(_value != 0);
  }

  function _boundToRealisticAmount(uint256 _amount) internal pure returns (uint256) {
    return bound(_amount, 1, DEFAULT_CAP);
  }

  /// @notice Internal function to get fork configuration with default values
  /// @return rpcUrl The RPC URL to use for forking
  /// @return forkBlock The block number to fork from
  function _getForkConfig() internal view returns (string memory rpcUrl, uint256 forkBlock) {
    // Get RPC URL with default fallback
    try vm.envString("RPC_URL") returns (string memory envRpcUrl) {
      rpcUrl = envRpcUrl;
    } catch {
      rpcUrl = "https://sepolia.era.zksync.dev/";
    }

    // Get fork block with default fallback
    try vm.envUint("FORK_BLOCK") returns (uint256 envForkBlock) {
      forkBlock = envForkBlock;
    } catch {
      forkBlock = 5_573_532;
    }
  }
}
