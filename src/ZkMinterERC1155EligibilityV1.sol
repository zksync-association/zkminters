// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title ZkMinterERC1155EligibilityV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract that extends `ZkMinterV1` to support ERC1155 gated minting. This contract allows minting
/// tokens to a specified address if they meet the ERC1155 balance threshold. The contract provides:
/// - ERC1155 balance verification for minting eligibility
/// - Configurable token ID and balance threshold requirements
/// - Admin controls for updating the token ID, and threshold
/// - Integration with the broader ZK Minter ecosystem
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterERC1155EligibilityV1 is ZkMinterV1 {
  /* ///////////////////////////////////////////////////////////////
                          Events
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when the token id is updated.
  event TokenIdUpdated(uint256 indexed previousTokenId, uint256 indexed newTokenId);

  /// @notice Emitted when the balance threshold is updated.
  event BalanceThresholdUpdated(uint256 indexed previousBalanceThreshold, uint256 indexed newBalanceThreshold);

  /* ///////////////////////////////////////////////////////////////
                          Errors
  //////////////////////////////////////////////////////////////*/

  /// @notice Error for when a zero address is provided where it's not allowed.
  error ZkMinterERC1155EligibilityV1__InvalidZeroAddress();

  /// @notice Error for when the balance threshold is zero.
  error ZkMinterERC1155EligibilityV1__InvalidBalanceThreshold();

  /// @notice Thrown when a contract does not support the ERC1155 interface.
  error ZkMinterERC1155EligibilityV1__InvalidERC1155Contract();

  /// @notice Error for when the caller has an insufficient balance.
  error ZkMinterERC1155EligibilityV1__InsufficientBalance();

  /* ///////////////////////////////////////////////////////////////
                          State Variables
  //////////////////////////////////////////////////////////////*/

  /// @notice The ERC1155 contract used to verify caller eligibility for minting.
  IERC1155 public ERC1155;

  /// @notice The specific token ID within the ERC1155 contract whose balance is checked.
  uint256 public tokenId;

  /// @notice The minimum balance of `tokenId` the caller must hold to mint.
  uint256 public balanceThreshold;

  /* ///////////////////////////////////////////////////////////////
                          Constructor
  //////////////////////////////////////////////////////////////*/

  /// @notice Initializes the contract with the mintable contract, admin, ERC1155 contract, token id, and balance
  /// threshold.
  /// @param _mintable A contract used as a target when calling mint. Any contract that conforms to the IMintable
  /// interface can be used, but in most cases this will be another `ZKMinter` extension or `ZKCappedMinter`.
  /// @param _admin The address that will have admin privileges.
  /// @param _erc1155 The ERC1155 contract to use for eligibility checks.
  /// @param _tokenId The token id for the ERC1155 contract.
  /// @param _balanceThreshold The balance threshold for the ERC1155 contract. Must be non-zero.
  constructor(IMintable _mintable, address _admin, address _erc1155, uint256 _tokenId, uint256 _balanceThreshold) {
    if (_admin == address(0)) {
      revert ZkMinterERC1155EligibilityV1__InvalidZeroAddress();
    }

    // Verify the provided address implements ERC1155
    if (!IERC165(_erc1155).supportsInterface(type(IERC1155).interfaceId)) {
      revert ZkMinterERC1155EligibilityV1__InvalidERC1155Contract();
    }

    ERC1155 = IERC1155(_erc1155);
    _updateMintable(_mintable);
    _updateTokenId(_tokenId);
    _updateBalanceThreshold(_balanceThreshold);

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);
  }

  /* ///////////////////////////////////////////////////////////////
                          External Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Allows a caller to mint tokens to a specified address if they meet the ERC1155 balance threshold.
  /// @param _to The address to mint the tokens to.
  /// @param _amount The amount of tokens to mint.
  /// @dev Caller must hold at least `balanceThreshold` of token `tokenId` in `erc1155`.
  /// @dev The minter role is not used for access control in this contract - eligibility is determined by ERC1155
  /// balance.
  function mint(address _to, uint256 _amount) external virtual {
    _revertIfClosed();
    _requireNotPaused();

    // revert if the caller has an insufficient balance
    if (!_isEligible(msg.sender)) {
      revert ZkMinterERC1155EligibilityV1__InsufficientBalance();
    }

    // mint the tokens
    mintable.mint(_to, _amount);

    emit Minted(msg.sender, _to, _amount);
  }

  /// @notice Updates the token id for the ERC1155 contract.
  /// @param _tokenId The new token id to set.
  /// @dev Used in `erc1155.balanceOf(_caller, tokenId)` for eligibility checks.
  function updateTokenId(uint256 _tokenId) external virtual {
    _revertIfClosed();
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _updateTokenId(_tokenId);
  }

  /// @notice Updates the balance threshold for the ERC1155 contract.
  /// @param _balanceThreshold The new balance threshold to set. Must be non-zero.
  /// @dev This is the minimum balance that must be held by the caller to mint.
  function updateBalanceThreshold(uint256 _balanceThreshold) external virtual {
    _revertIfClosed();
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _updateBalanceThreshold(_balanceThreshold);
  }

  /* ///////////////////////////////////////////////////////////////
                          Public Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Returns whether the given address is eligible to mint.
  /// @param _caller The address to check eligibility for.
  /// @return True if the caller has a balance greater than or equal to the balance threshold, false otherwise.
  function isEligible(address _caller) public view virtual returns (bool) {
    return _isEligible(_caller);
  }

  /* ///////////////////////////////////////////////////////////////
                          Internal Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Internal function to check if an address is eligible to mint.
  /// @param _caller The address to check eligibility for.
  /// @return True if the caller has sufficient balance, false otherwise.
  function _isEligible(address _caller) internal view virtual returns (bool) {
    return ERC1155.balanceOf(_caller, tokenId) >= balanceThreshold;
  }

  /// @notice Updates the token id for the ERC1155 contract.
  /// @param _newTokenId The new token id to set.
  function _updateTokenId(uint256 _newTokenId) internal virtual {
    emit TokenIdUpdated(tokenId, _newTokenId);
    tokenId = _newTokenId;
  }

  /// @notice Updates the balance threshold for the ERC1155 contract.
  /// @param _newBalanceThreshold The new balance threshold to set.
  function _updateBalanceThreshold(uint256 _newBalanceThreshold) internal virtual {
    if (_newBalanceThreshold == 0) {
      revert ZkMinterERC1155EligibilityV1__InvalidBalanceThreshold();
    }
    emit BalanceThresholdUpdated(balanceThreshold, _newBalanceThreshold);
    balanceThreshold = _newBalanceThreshold;
  }
}
