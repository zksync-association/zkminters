// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ZkMinterModTriggerV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract that enables minting tokens and triggering external function calls.
/// @dev This contract should typically be placed at the beginning of the mint chain.
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterModTriggerV1 is ZkMinterV1 {
  using SafeERC20 for IERC20;

  /// @notice The target contracts to call when trigger is executed.
  address[] public targets;

  /// @notice The calldata for the functions.
  bytes[] public calldatas;

  /// @notice The values to send with the calls.
  uint256[] public values;

  /// @notice The immutable address where tokens can be recovered to.
  address public immutable recoveryAddress;

  /// @notice Emitted when trigger is executed.
  event TriggerExecuted(address indexed caller);

  /// @notice Emitted when tokens are sent to the immutable recovery address.
  event TokensRecovered(address indexed admin, address indexed token, uint256 amount, address indexed recoveryAddress);

  /// @notice Error for when a function call fails.
  error ZkMinterModTriggerV1__TriggerCallFailed(uint256 index, address target);

  /// @notice Error for when the recipient is not the expected recipient.
  error ZkMinterModTriggerV1__InvalidRecipient(address recipient, address expectedRecipient);

  /// @notice Error for when the admin is the zero address.
  error ZkMinterModTriggerV1__InvalidAdmin();

  /// @notice Error for when array lengths don't match.
  error ZkMinterModTriggerV1__ArrayLengthMismatch();

  /// @notice Error for when the recovery address is the zero address.
  error ZkMinterModTriggerV1__InvalidRecoveryAddress();

  /// @notice Initializes the trigger contract with mintable, admin, and trigger parameters.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _targetAddresses The target contracts to call.
  /// @param _calldatas The call data for the functions.
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
      revert ZkMinterModTriggerV1__InvalidAdmin();
    }

    if (_targetAddresses.length != _calldatas.length) {
      revert ZkMinterModTriggerV1__ArrayLengthMismatch();
    }

    if (_recoveryAddress == address(0)) {
      revert ZkMinterModTriggerV1__InvalidRecoveryAddress();
    }

    _updateMintable(_mintable);
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);

    targets = _targetAddresses;
    calldatas = _calldatas;
    values = _values;
    recoveryAddress = _recoveryAddress;
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

  /// @notice Sends minted tokens held by this contract to the immutable recovery address.
  /// @param _amount The amount of tokens to send.
  /// @dev Only callable by addresses with the DEFAULT_ADMIN_ROLE.
  function recoverTokens(address _token, uint256 _amount) external {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);

    IERC20(_token).safeTransfer(recoveryAddress, _amount);
    emit TokensRecovered(msg.sender, _token, _amount, recoveryAddress);
  }

  /// @notice Receives ETH.
  receive() external payable {}
}
