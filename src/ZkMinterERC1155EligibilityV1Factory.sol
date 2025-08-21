// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2ContractHelper} from "src/lib/L2ContractHelper.sol";
import {ZkMinterERC1155EligibilityV1} from "src/ZkMinterERC1155EligibilityV1.sol";
import {IZkMinterV1Factory} from "src/interfaces/IZkMinterV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

/// @title ZkMinterERC1155EligibilityV1Factory
/// @author [ScopeLift](https://scopelift.co)
/// @notice Factory contract to deploy `ZkMinterERC1155EligibilityV1` contracts using CREATE2. This factory enables
/// deterministic deployment of ERC1155-based minting contracts with predictable addresses. The factory
/// supports two deployment methods:
/// - Standard deployment with explicit parameters
/// - Unified deployment with encoded parameters for multi-factory compatibility
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterERC1155EligibilityV1Factory is IZkMinterV1Factory {
  /*///////////////////////////////////////////////////////////////
                  Immutable Variables
  //////////////////////////////////////////////////////////////*/

  /// @dev Bytecode hash is derived at deployment time from the compiled contract bytecode.
  bytes32 public immutable BYTECODE_HASH;

  /*///////////////////////////////////////////////////////////////
                          Events
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a new `ZkMinterERC1155EligibilityV1` is created.
  /// @param minterERC1155 The address of the newly deployed `ZkMinterERC1155EligibilityV1`.
  /// @param mintable A contract used as a target when calling mint.
  /// @param admin The address that will have admin privileges.
  /// @param erc1155 The ERC1155 contract to use for balance checks.
  /// @param tokenId The token ID within the ERC1155 contract.
  /// @param balanceThreshold The minimum balance required to mint.
  event MinterERC1155EligibilityCreated(
    address indexed minterERC1155,
    IMintable mintable,
    address admin,
    address erc1155,
    uint256 tokenId,
    uint256 balanceThreshold
  );

  /*///////////////////////////////////////////////////////////////
                          Constructor
  //////////////////////////////////////////////////////////////*/

  /// @notice Initializes the factory with the bytecode hash of the `ZkMinterERC1155EligibilityV1` contract.
  /// @param _bytecodeHash The bytecode hash of the `ZkMinterERC1155EligibilityV1` contract to be used for CREATE2
  /// deployments.
  constructor(bytes32 _bytecodeHash) {
    BYTECODE_HASH = _bytecodeHash;
  }

  /*///////////////////////////////////////////////////////////////
                          External Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploys a new `ZkMinterERC1155EligibilityV1` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _erc1155 The ERC1155 contract to use for balance checks.
  /// @param _tokenId The token ID within the ERC1155 contract.
  /// @param _balanceThreshold The minimum balance required to mint.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _minterERC1155Address The address of the newly deployed `ZkMinterERC1155EligibilityV1`.
  function createMinter(
    IMintable _mintable,
    address _admin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) external returns (address _minterERC1155Address) {
    _minterERC1155Address = _createMinter(_mintable, _admin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);
  }

  /// @notice Deploys a new `ZkMinterERC1155EligibilityV1` contract using `CREATE2`. This method takes a bytes argument
  /// and is meant to be used in a unified factory for all capped minter extensions.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _args The encoded args to deploy `ZkMinterERC1155EligibilityV1`.
  /// @return The address of the newly deployed `ZkMinterERC1155EligibilityV1`.
  function createMinter(IMintable _mintable, bytes memory _args) external returns (address) {
    (address _admin, address _erc1155, uint256 _tokenId, uint256 _balanceThreshold, uint256 _saltNonce) =
      abi.decode(_args, (address, address, uint256, uint256, uint256));
    return _createMinter(_mintable, _admin, _erc1155, _tokenId, _balanceThreshold, _saltNonce);
  }

  /// @notice Computes the address of a `ZkMinterERC1155EligibilityV1` deployed via this factory.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _erc1155 The ERC1155 contract to use for balance checks.
  /// @param _tokenId The token ID within the ERC1155 contract.
  /// @param _balanceThreshold The minimum balance required to mint.
  /// @param _saltNonce The nonce used for salt calculation.
  /// @return _minterERC1155Address The address of the `ZkMinterERC1155EligibilityV1`.
  function getMinter(
    IMintable _mintable,
    address _admin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) external view returns (address _minterERC1155Address) {
    bytes32 _salt = _calculateSalt(_saltNonce);
    _minterERC1155Address = L2ContractHelper.computeCreate2Address(
      address(this),
      _salt,
      BYTECODE_HASH,
      keccak256(abi.encode(_mintable, _admin, _erc1155, _tokenId, _balanceThreshold))
    );
  }

  /*///////////////////////////////////////////////////////////////
                          Internal Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Calculates the salt for CREATE2 deployment.
  /// @param _saltNonce A user-provided nonce for additional uniqueness.
  /// @return The calculated salt as a bytes32 value.
  function _calculateSalt(uint256 _saltNonce) internal view returns (bytes32) {
    return keccak256(abi.encode(block.chainid, _saltNonce));
  }

  /// @notice Creates a new `ZkMinterERC1155EligibilityV1` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _erc1155 The ERC1155 contract to use for balance checks.
  /// @param _tokenId The token ID within the ERC1155 contract.
  /// @param _balanceThreshold The minimum balance required to mint.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _minterERC1155Address The address of the newly deployed `ZkMinterERC1155EligibilityV1`.
  function _createMinter(
    IMintable _mintable,
    address _admin,
    address _erc1155,
    uint256 _tokenId,
    uint256 _balanceThreshold,
    uint256 _saltNonce
  ) internal returns (address _minterERC1155Address) {
    bytes32 _salt = _calculateSalt(_saltNonce);

    ZkMinterERC1155EligibilityV1 instance =
      new ZkMinterERC1155EligibilityV1{salt: _salt}(_mintable, _admin, _erc1155, _tokenId, _balanceThreshold);
    _minterERC1155Address = address(instance);

    emit MinterERC1155EligibilityCreated(
      _minterERC1155Address, _mintable, _admin, _erc1155, _tokenId, _balanceThreshold
    );
  }
}
