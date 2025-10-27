// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2ContractHelper} from "src/lib/L2ContractHelper.sol";
import {ZkCappedMinterV3} from "src/ZkCappedMinterV3.sol";
import {IZkMinterV1Factory} from "src/interfaces/IZkMinterV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

/// @title ZkCappedMinterV3Factory
/// @author [ScopeLift](https://scopelift.co)
/// @notice Factory contract to deploy `ZkCappedMinterV3` contracts using CREATE2. This factory enables
/// deterministic deployment of capped minter contracts with time-based restrictions and predictable addresses.
/// The factory supports two deployment methods:
/// - `createMinter(IMintable,address,uint256,uint48,uint48,uint256)` for strongly typed params
/// - `createMinter(IMintable,bytes)` for unified factory compatibility
/// @dev This factory is based off of ZkCappedMinterV2 which can be found
/// [here](https://github.com/zksync-association/zk-governance/blob/b1d1bdce1def3c036c06e449787a3763bf47e766/l2-contracts/test/ZkCappedMinterV2Factory.t.sol).
/// @custom:security-contact security@matterlabs.dev
contract ZkCappedMinterV3Factory is IZkMinterV1Factory {
  /* ///////////////////////////////////////////////////////////////
                  Immutable Variables
  //////////////////////////////////////////////////////////////*/

  /// @dev Bytecode hash is derived at deployment time from the compiled contract bytecode.
  bytes32 public immutable BYTECODE_HASH;

  /* ///////////////////////////////////////////////////////////////
                          Events
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a new `ZkCappedMinterV3` is created.
  /// @param cappedMinter The address of the newly deployed `ZkCappedMinterV3`.
  /// @param mintable A contract used as a target when calling mint.
  /// @param admin The address that will have admin privileges.
  /// @param cap The maximum number of tokens that may be minted.
  /// @param startTime The timestamp when minting can begin.
  /// @param expirationTime The timestamp after which minting is no longer allowed (inclusive).
  event MinterCappedCreated(
    address indexed cappedMinter,
    IMintable mintable,
    address admin,
    uint256 cap,
    uint48 startTime,
    uint48 expirationTime
  );

  /* ///////////////////////////////////////////////////////////////
                          Constructor
  //////////////////////////////////////////////////////////////*/

  /// @notice Initializes the factory with the bytecode hash of the `ZkCappedMinterV3` contract.
  /// @param _bytecodeHash The bytecode hash of the `ZkCappedMinterV3` contract to be used for CREATE2 deployments.
  constructor(bytes32 _bytecodeHash) {
    BYTECODE_HASH = _bytecodeHash;
  }

  /* ///////////////////////////////////////////////////////////////
                          External Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploys a new `ZkCappedMinterV3` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _cap The maximum number of tokens that may be minted.
  /// @param _startTime The timestamp when minting can begin.
  /// @param _expirationTime The timestamp after which minting is no longer allowed (inclusive).
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _cappedMinterAddress The address of the newly deployed `ZkCappedMinterV3`.
  function createMinter(
    IMintable _mintable,
    address _admin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) external returns (address _cappedMinterAddress) {
    _cappedMinterAddress = _createMinter(_mintable, _admin, _cap, _startTime, _expirationTime, _saltNonce);
  }

  /// @notice Deploys a new `ZkCappedMinterV3` contract using `CREATE2`. This method takes a bytes argument
  /// and is meant to be used in a unified factory for all capped minter extensions.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _args The encoded args to deploy `ZkCappedMinterV3`.
  /// @return The address of the newly deployed `ZkCappedMinterV3`.
  function createMinter(IMintable _mintable, bytes memory _args) external returns (address) {
    (address _admin, uint256 _cap, uint48 _startTime, uint48 _expirationTime, uint256 _saltNonce) =
      abi.decode(_args, (address, uint256, uint48, uint48, uint256));
    return _createMinter(_mintable, _admin, _cap, _startTime, _expirationTime, _saltNonce);
  }

  /// @notice Computes the address of a `ZkCappedMinterV3` deployed via this factory.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _cap The maximum number of tokens that may be minted.
  /// @param _startTime The timestamp when minting can begin.
  /// @param _expirationTime The timestamp after which minting is no longer allowed (inclusive).
  /// @param _saltNonce The nonce used for salt calculation.
  /// @return _cappedMinterAddress The address of the `ZkCappedMinterV3`.
  function getMinter(
    IMintable _mintable,
    address _admin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) external view returns (address _cappedMinterAddress) {
    bytes32 _salt = _calculateSalt(_saltNonce);
    _cappedMinterAddress = L2ContractHelper.computeCreate2Address(
      address(this), _salt, BYTECODE_HASH, keccak256(abi.encode(_mintable, _admin, _cap, _startTime, _expirationTime))
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

  /// @notice Creates a new `ZkCappedMinterV3` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _cap The maximum number of tokens that may be minted.
  /// @param _startTime The timestamp when minting can begin.
  /// @param _expirationTime The timestamp after which minting is no longer allowed (inclusive).
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _cappedMinterAddress The address of the newly deployed `ZkCappedMinterV3`.
  function _createMinter(
    IMintable _mintable,
    address _admin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) internal returns (address _cappedMinterAddress) {
    bytes32 _salt = _calculateSalt(_saltNonce);

    ZkCappedMinterV3 _instance = new ZkCappedMinterV3{salt: _salt}(_mintable, _admin, _cap, _startTime, _expirationTime);
    _cappedMinterAddress = address(_instance);

    emit MinterCappedCreated(_cappedMinterAddress, _mintable, _admin, _cap, _startTime, _expirationTime);
  }
}
