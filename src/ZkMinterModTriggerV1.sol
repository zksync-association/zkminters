// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";

/// @title ZkMinterModTriggerV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract that enables minting tokens and triggering external function calls.
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterModTriggerV1 is ZkMinterV1 {
  /// @notice The target contracts to call when trigger is executed.
  address[] public targets;

  /// @notice The call data for the functions.
  bytes[] public callDatas;

  /// @notice Emitted when trigger is executed.
  event TriggerExecuted(address indexed caller, uint256 callsExecuted);

  /// @notice Error for when a function call fails.
  error ZkMinterModTriggerV1__TriggerCallFailed(uint256 index, address target);

  /// @notice Error for when the admin is the zero address.
  error ZkMinterModTriggerV1__InvalidAdmin();

  /// @notice Error for when the mintable is the zero address.
  error ZkMinterModTriggerV1__InvalidMintable();

  /// @notice Error for when array lengths don't match.
  error ZkMinterModTriggerV1__ArrayLengthMismatch();

  /// @notice Initializes the trigger contract with mintable, admin, and trigger parameters.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _targetAddresses The target contracts to call.
  /// @param _callDatas The call data for the functions.
  constructor(IMintable _mintable, address _admin, address[] memory _targetAddresses, bytes[] memory _callDatas) {
    if (address(_mintable) == address(0)) {
      revert ZkMinterModTriggerV1__InvalidMintable();
    }

    if (_admin == address(0)) {
      revert ZkMinterModTriggerV1__InvalidAdmin();
    }

    if (_targetAddresses.length != _callDatas.length) {
      revert ZkMinterModTriggerV1__ArrayLengthMismatch();
    }

    _updateMintable(_mintable);
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);

    targets = _targetAddresses;
    callDatas = _callDatas;
  }

  /// @notice Mints tokens to this contract address.
  /// @param _amount The quantity of tokens that will be minted.
  /// @dev Only callable by addresses with the MINTER_ROLE. Tokens are always minted to address(this).
  /// @dev The first parameter is kept for interface compliance but ignored.
  function mint(address, /* _to */ uint256 _amount) external {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);

    mintable.mint(address(this), _amount);
    emit Minted(msg.sender, address(this), _amount);
  }

  /// @notice Executes all configured trigger calls.
  /// @dev Only callable by addresses with the MINTER_ROLE.
  function trigger() external {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);

    for (uint256 i = 0; i < targets.length; i++) {
      (bool success,) = targets[i].call(callDatas[i]);
      if (!success) {
        revert ZkMinterModTriggerV1__TriggerCallFailed(i, targets[i]);
      }
    }

    emit TriggerExecuted(msg.sender, targets.length);
  }
}
