// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";

/// @title ZkMinterModTriggerV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract that enables minting tokens and triggering external function calls.
/// @dev This contract should typically be placed at the beginning of the mint chain.
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterModTriggerV1 is ZkMinterV1 {
  /// @notice The target contracts to call when trigger is executed.
  address[] public targets;

  /// @notice The call data for the functions.
  bytes[] public calldatas;

  /// @notice The values to send with the calls.
  uint256[] public values;

  /// @notice Emitted when trigger is executed.
  event TriggerExecuted(address indexed caller);

  /// @notice Error for when a function call fails.
  error ZkMinterModTriggerV1__TriggerCallFailed(uint256 index, address target);

  /// @notice Error for when the recipient is not the expected recipient.
  error ZkMinterModTriggerV1__InvalidRecipient(address recipient, address expectedRecipient);

  /// @notice Error for when the admin is the zero address.
  error ZkMinterModTriggerV1__InvalidAdmin();

  /// @notice Error for when array lengths don't match.
  error ZkMinterModTriggerV1__ArrayLengthMismatch();

  /// @notice Initializes the trigger contract with mintable, admin, and trigger parameters.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _targetAddresses The target contracts to call.
  /// @param _calldatas The call data for the functions.
  constructor(
    IMintable _mintable,
    address _admin,
    address[] memory _targetAddresses,
    bytes[] memory _calldatas,
    uint256[] memory _values
  ) {
    if (_admin == address(0)) {
      revert ZkMinterModTriggerV1__InvalidAdmin();
    }

    if (_targetAddresses.length != _calldatas.length) {
      revert ZkMinterModTriggerV1__ArrayLengthMismatch();
    }

    _updateMintable(_mintable);
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);

    targets = _targetAddresses;
    calldatas = _calldatas;
    values = _values;
  }

  /// @notice Mints tokens to this contract address.
  /// @param _to The address that will receive the new tokens, must be address(this).
  /// @param _amount The quantity of tokens that will be minted.
  /// @dev Only callable by addresses with the MINTER_ROLE. Tokens are always minted to address(this).
  function mint(address _to, uint256 _amount) public {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);

    if (_to != address(this)) {
      revert ZkMinterModTriggerV1__InvalidRecipient(_to, address(this));
    }

    mintable.mint(_to, _amount);
    emit Minted(msg.sender, _to, _amount);
  }

  /// @notice Executes all configured trigger calls.
  /// @dev Only callable by addresses with the MINTER_ROLE.
  function trigger() public payable {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);

    for (uint256 i = 0; i < targets.length; i++) {
      (bool success,) = targets[i].call{value: values[i]}(calldatas[i]);
      if (!success) {
        revert ZkMinterModTriggerV1__TriggerCallFailed(i, targets[i]);
      }
    }

    emit TriggerExecuted(msg.sender);
  }

  /// @notice Mints tokens to this contract address and then executes all configured trigger calls.
  /// @param _to The address that will receive the minted tokens, must be address(this).
  /// @param _amount The quantity of tokens to mint.
  /// @dev Only callable by addresses with the MINTER_ROLE.
  function mintAndTrigger(address _to, uint256 _amount) public payable {
    mint(_to, _amount);
    trigger();
  }

  /// @notice Receives ETH.
  receive() external payable {}
}
