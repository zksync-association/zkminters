// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ZkMinterTriggerV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract that enables minting tokens and triggering external function calls.
/// @dev This contract should typically be placed at the beginning of the mint chain. Integrators must be aware that
/// trigger execution is intentionally decoupled from minting, allowing repeated trigger invocations without additional
/// mints. Design downstream targets accordingly to avoid unintended side effects from multiple executions.
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterTriggerV1 is ZkMinterV1 {
  using SafeERC20 for IERC20;

  /// @notice The target contracts to call when trigger is executed.
  address[] public targets;

  /// @notice The calldata for the functions.
  bytes[] public calldatas;

  /// @notice The values to send with the calls.
  uint256[] public values;

  /// @notice The immutable address where tokens are sent when recovered.
  address public immutable RECOVERY_ADDRESS;

  /// @notice Emitted when trigger is executed.
  event TriggerExecuted(address indexed caller);

  /// @notice Emitted when tokens are sent to the immutable recovery address.
  event TokensRecovered(address indexed admin, address indexed token, uint256 amount, address indexed recoveryAddress);

  /// @notice Error for when a function call fails.
  error ZkMinterTriggerV1__TriggerCallFailed(uint256 index, address target);

  /// @notice Error for when the recipient is not the expected recipient.
  error ZkMinterTriggerV1__InvalidRecipient(address recipient, address expectedRecipient);

  /// @notice Error for when the admin is the zero address.
  error ZkMinterTriggerV1__InvalidAdmin();

  /// @notice Error for when array lengths don't match.
  error ZkMinterTriggerV1__ArrayLengthMismatch();

  /// @notice Error for when the recovery address is the zero address.
  error ZkMinterTriggerV1__InvalidRecoveryAddress();

  /// @notice Initializes the trigger contract with mintable, admin, and trigger parameters.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _targetAddresses The target contracts to call.
  /// @param _calldatas The call data for the functions.
  /// @param _values The ETH values to send with the calls.
  /// @param _recoveryAddress The immutable address where minted tokens can be sent.
  constructor(
    IMintable _mintable,
    address _admin,
    address[] memory _targetAddresses,
    bytes[] memory _calldatas,
    uint256[] memory _values,
    address _recoveryAddress
  ) {
    if (_admin == address(0)) {
      revert ZkMinterTriggerV1__InvalidAdmin();
    }

    if (_targetAddresses.length != _calldatas.length || _calldatas.length != _values.length) {
      revert ZkMinterTriggerV1__ArrayLengthMismatch();
    }

    if (_recoveryAddress == address(0)) {
      revert ZkMinterTriggerV1__InvalidRecoveryAddress();
    }

    _updateMintable(_mintable);
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);

    targets = _targetAddresses;
    calldatas = _calldatas;
    values = _values;
    RECOVERY_ADDRESS = _recoveryAddress;
  }

  /// @notice Mints tokens to this contract address.
  /// @param _to The address that will receive the new tokens, must be address(this).
  /// @param _amount The quantity of tokens that will be minted.
  /// @dev Only callable by addresses with the `MINTER_ROLE`. Tokens are always minted to address(this).
  function mint(address _to, uint256 _amount) public virtual {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);

    if (_to != address(this)) {
      revert ZkMinterTriggerV1__InvalidRecipient(_to, address(this));
    }

    mintable.mint(_to, _amount);
    emit Minted(msg.sender, _to, _amount);
  }

  /// @notice Executes all configured trigger calls.
  /// @dev Only callable by addresses with the `MINTER_ROLE`. Trigger calls are intentionally decoupled from minting and
  /// can be executed multiple times without a preceding mint. Ensure configured targets tolerate repeated execution and
  /// do not assume a single-call lifecycle.
  function trigger() public payable virtual {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);

    for (uint256 i = 0; i < targets.length; i++) {
      (bool success,) = targets[i].call{value: values[i]}(calldatas[i]);
      if (!success) {
        revert ZkMinterTriggerV1__TriggerCallFailed(i, targets[i]);
      }
    }

    emit TriggerExecuted(msg.sender);
  }

  /// @notice Mints tokens to this contract address and then executes all configured trigger calls.
  /// @param _to The address that will receive the minted tokens, must be address(this).
  /// @param _amount The quantity of tokens to mint.
  /// @dev Only callable by addresses with the `MINTER_ROLE`. Combines `mint` and `trigger`, but does not restrict
  /// callers from later invoking `trigger` independently.
  function mintAndTrigger(address _to, uint256 _amount) public payable virtual {
    mint(_to, _amount);
    trigger();
  }

  /// @notice Sends minted tokens held by this contract to the immutable recovery address.
  /// @param _token Address of the token to send.
  /// @param _amount The amount of tokens to send.
  /// @dev Only callable by addresses with the DEFAULT_ADMIN_ROLE.
  function recoverTokens(address _token, uint256 _amount) external virtual {
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    if (_token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
      RECOVERY_ADDRESS.call{value: _amount}("");
    } else {
      IERC20(_token).safeTransfer(RECOVERY_ADDRESS, _amount);
    }
    emit TokensRecovered(msg.sender, _token, _amount, RECOVERY_ADDRESS);
  }

  /// @notice Receives ETH.
  receive() external payable {}
}
