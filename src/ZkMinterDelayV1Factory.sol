// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2ContractHelper} from "src/lib/L2ContractHelper.sol";
import {ZkMinterDelayV1} from "src/ZkMinterDelayV1.sol";
import {IZkMinterV1Factory} from "src/interfaces/IZkMinterV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

/// @title ZkMinterDelayV1Factory
/// @author [ScopeLift](https://scopelift.co)
/// @notice Factory contract to deploy `ZkMinterDelayV1` contracts using CREATE2. This factory enables
/// deterministic deployment of delay-based minting contracts with predictable addresses. The factory
/// supports two deployment methods:
/// - Standard deployment with explicit parameters
/// - Unified deployment with encoded parameters for multi-factory compatibility
/// @dev ZkMinterDelayV1 deployment flow:
/// 1. Call createMinter() with mintable, admin, delay, and salt nonce
/// 2. Factory calculates salt using chain ID + nonce and creates a new ZkMinterDelayV1 contract using CREATE2
/// 3. Event emitted with deployment details
/// 4. Address can be predicted using getMinter() before deployment
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterDelayV1Factory is IZkMinterV1Factory {
  /* ///////////////////////////////////////////////////////////////
                  Immutable Variables
  //////////////////////////////////////////////////////////////*/

  /// @dev Bytecode hash is derived at deployment time from the compiled contract bytecode.
  bytes32 public immutable BYTECODE_HASH;

  /* ///////////////////////////////////////////////////////////////
                          Events
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a new `ZkMinterDelayV1` is created.
  /// @param minterDelay The address of the newly deployed `ZkMinterDelayV1`.
  /// @param mintable A contract used as a target when calling mint.
  /// @param admin The address that will have admin privileges.
  /// @param mintDelay The duration in seconds of the mint delay.
  event MinterDelayCreated(address indexed minterDelay, IMintable mintable, address admin, uint48 mintDelay);

  /* ///////////////////////////////////////////////////////////////
                          Constructor
  //////////////////////////////////////////////////////////////*/

  /// @notice Initializes the factory with the bytecode hash of the `ZkMinterDelayV1` contract.
  /// @param _bytecodeHash The bytecode hash of the `ZkMinterDelayV1` contract to be used for CREATE2 deployments.
  constructor(bytes32 _bytecodeHash) {
    BYTECODE_HASH = _bytecodeHash;
  }

  /* ///////////////////////////////////////////////////////////////
                          External Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploys a new `ZkMinterDelayV1` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _mintDelay The duration in seconds of the mint delay.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _minterDelayAddress The address of the newly deployed `ZkMinterDelayV1`.
  function createMinter(IMintable _mintable, address _admin, uint48 _mintDelay, uint256 _saltNonce)
    external
    returns (address _minterDelayAddress)
  {
    _minterDelayAddress = _createMinter(_mintable, _admin, _mintDelay, _saltNonce);
  }

  /// @notice Deploys a new `ZkMinterDelayV1` contract using `CREATE2`. This method takes a bytes argument
  /// and is meant to be used in a unified factory for all capped minter extensions.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _args The encoded args to deploy `ZkMinterDelayV1`.
  /// @return The address of the newly deployed `ZkMinterDelayV1`.
  function createMinter(IMintable _mintable, bytes memory _args) external returns (address) {
    (address _admin, uint48 _mintDelay, uint256 _saltNonce) = abi.decode(_args, (address, uint48, uint256));
    return _createMinter(_mintable, _admin, _mintDelay, _saltNonce);
  }

  /// @notice Computes the address of a `ZkMinterDelayV1` deployed via this factory.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _mintDelay The duration in seconds of the mint delay.
  /// @param _saltNonce The nonce used for salt calculation.
  /// @return _minterDelayAddress The address of the `ZkMinterDelayV1`.
  function getMinter(IMintable _mintable, address _admin, uint48 _mintDelay, uint256 _saltNonce)
    external
    view
    returns (address _minterDelayAddress)
  {
    bytes32 _salt = _calculateSalt(_saltNonce);
    _minterDelayAddress = L2ContractHelper.computeCreate2Address(
      address(this), _salt, BYTECODE_HASH, keccak256(abi.encode(_mintable, _admin, _mintDelay))
    );
  }

  /* ///////////////////////////////////////////////////////////////
                          Internal Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Calculates the salt for CREATE2 deployment.
  /// @param _saltNonce A user-provided nonce for additional uniqueness.
  /// @return The calculated salt as a bytes32 value.
  function _calculateSalt(uint256 _saltNonce) internal view returns (bytes32) {
    return keccak256(abi.encode(block.chainid, _saltNonce));
  }

  /// @notice Creates a new `ZkMinterDelayV1` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _mintDelay The duration in seconds of the mint delay.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _minterDelayAddress The address of the newly deployed `ZkMinterDelayV1`.
  function _createMinter(IMintable _mintable, address _admin, uint48 _mintDelay, uint256 _saltNonce)
    internal
    returns (address _minterDelayAddress)
  {
    bytes32 _salt = _calculateSalt(_saltNonce);

    ZkMinterDelayV1 instance = new ZkMinterDelayV1{salt: _salt}(_mintable, _admin, _mintDelay);
    _minterDelayAddress = address(instance);

    emit MinterDelayCreated(_minterDelayAddress, _mintable, _admin, _mintDelay);
  }
}
