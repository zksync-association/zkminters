// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

/// @title ZkCappedMinterV3
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract to allow a permissioned entity to mint ZK tokens up to a given amount (the cap).
/// @dev V3 preserves the features of V2 while extending the ZkMinterV1 base and supporting multiple admins (no
/// restriction on granting DEFAULT_ADMIN_ROLE).
/// @custom:security-contact security@matterlabs.dev
contract ZkCappedMinterV3 is ZkMinterV1 {
  /// @notice The maximum number of tokens that may be minted by the ZkCappedMinter.
  uint256 public immutable CAP;

  /// @notice The cumulative number of tokens that have been minted by the ZkCappedMinter.
  uint256 public minted = 0;

  /// @notice The timestamp when minting can begin.
  uint48 public immutable START_TIME;

  /// @notice The timestamp after which minting is no longer allowed (inclusive).
  uint48 public immutable EXPIRATION_TIME;

  /// @notice The metadata URI for this minter.
  string public metadataURI;

  /// @notice Emitted when the metadata URI is set.
  event MetadataURISet(string uri);

  /// @notice Error for when the cap is exceeded.
  error ZkCappedMinterV3__CapExceeded(address minter, uint256 amount);

  /// @notice Error for when minting is attempted before the start time.
  error ZkCappedMinterV3__NotStarted();

  /// @notice Error for when minting is attempted after expiration.
  error ZkCappedMinterV3__Expired();

  /// @notice Error for when the start time is greater than or equal to expiration time, or start time is in the past.
  error ZkCappedMinterV3__InvalidTime();

  /// @notice Constructor for a new ZkCappedMinterV3 contract
  /// @param _mintable The contract where tokens will be minted.
  /// @param _admin The address that will be granted the initial admin and pauser roles.
  /// @param _cap The maximum number of tokens that may be minted by the ZkCappedMinter.
  /// @param _startTime The timestamp when minting can begin.
  /// @param _expirationTime The timestamp after which minting is no longer allowed (inclusive).
  constructor(IMintable _mintable, address _admin, uint256 _cap, uint48 _startTime, uint48 _expirationTime) {
    if (_startTime > _expirationTime) {
      revert ZkCappedMinterV3__InvalidTime();
    }
    if (_startTime < block.timestamp) {
      revert ZkCappedMinterV3__InvalidTime();
    }

    CAP = _cap;
    START_TIME = _startTime;
    EXPIRATION_TIME = _expirationTime;

    // Initialize the updatable mintable reference from the base contract to the same initial value.
    _updateMintable(_mintable);

    // Initial roles: support multiple admins by allowing DEFAULT_ADMIN_ROLE to be granted later as needed.
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);
  }

  /// @notice Mints a given amount of tokens to a given address, so long as the cap is not exceeded and timing allows.
  /// @param _to The address that will receive the new tokens.
  /// @param _amount The quantity of tokens, in raw decimals, that will be created.
  function mint(address _to, uint256 _amount) external {
    _revertIfClosed();

    if (block.timestamp < START_TIME) {
      revert ZkCappedMinterV3__NotStarted();
    }
    if (block.timestamp > EXPIRATION_TIME) {
      revert ZkCappedMinterV3__Expired();
    }
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);
    _revertIfCapExceeded(_amount);

    minted += _amount;

    // Use the updatable mintable reference from the base to allow composition.
    mintable.mint(_to, _amount);
    emit Minted(msg.sender, _to, _amount);
  }

  /// @notice Sets the metadata URI for this contract.
  /// @param _uri The new metadata URI.
  /// @dev Only callable by addresses with the DEFAULT_ADMIN_ROLE.
  function setMetadataURI(string memory _uri) external {
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    metadataURI = _uri;
    emit MetadataURISet(_uri);
  }

  /// @notice Reverts if the amount of new tokens will increase the minted tokens beyond the mint cap.
  /// @param _amount The quantity of tokens, in raw decimals, that will checked against the cap.
  function _revertIfCapExceeded(uint256 _amount) internal view {
    if (minted + _amount > CAP) {
      revert ZkCappedMinterV3__CapExceeded(msg.sender, _amount);
    }
  }
}
