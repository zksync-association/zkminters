// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2ContractHelper} from "src/lib/L2ContractHelper.sol";
import {ZkMinterTriggerV1} from "src/ZkMinterTriggerV1.sol";
import {IZkMinterV1Factory} from "src/interfaces/IZkMinterV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

/// @title ZkMinterTriggerV1Factory
/// @author [ScopeLift](https://scopelift.co)
/// @notice Factory contract to deploy `ZkMinterTriggerV1` contracts using CREATE2. This factory enables
/// deterministic deployment of trigger-based minter contracts with predictable addresses. The factory offers two
/// deployment interfaces:
/// - `createMinter(IMintable,address,address[],bytes[],uint256[],address,uint256)` for strongly typed params
/// - `createMinter(IMintable,bytes)` for unified factory compatibility
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterTriggerV1Factory is IZkMinterV1Factory {
  /*///////////////////////////////////////////////////////////////
                  Immutable Variables
  //////////////////////////////////////////////////////////////*/

  /// @dev Bytecode hash is derived at deployment time from the compiled contract bytecode.
  bytes32 public immutable BYTECODE_HASH;

  /*///////////////////////////////////////////////////////////////
                          Events
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a new `ZkMinterTriggerV1` is created.
  /// @param minterTrigger The address of the newly deployed trigger minter.
  /// @param mintable A contract used as a target when calling mint.
  /// @param admin The address that will have admin privileges.
  /// @param targets The batch of target contracts executed by the trigger.
  /// @param calldatas Calldata forwarded to each target contract.
  /// @param values ETH values forwarded to each target contract.
  /// @param recovery The immutable recovery address for the trigger.
  event MinterTriggerCreated(
    address indexed minterTrigger,
    IMintable mintable,
    address admin,
    address[] targets,
    bytes[] calldatas,
    uint256[] values,
    address recovery
  );

  /*///////////////////////////////////////////////////////////////
                          Constructor
  //////////////////////////////////////////////////////////////*/

  /// @notice Initializes the factory with the bytecode hash of the `ZkMinterTriggerV1` contract.
  /// @param _bytecodeHash The bytecode hash of the `ZkMinterTriggerV1` contract to be used for CREATE2 deployments.
  constructor(bytes32 _bytecodeHash) {
    BYTECODE_HASH = _bytecodeHash;
  }

  /*///////////////////////////////////////////////////////////////
                          External Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploys a new `ZkMinterTriggerV1` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _targets Target contracts invoked when `trigger()` executes.
  /// @param _calldatas Calldata forwarded to each target contract.
  /// @param _values ETH values forwarded with each call.
  /// @param _recoveryAddress Immutable address that receives recovered funds.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _minterTriggerAddress The address of the newly deployed `ZkMinterTriggerV1`.
  function createMinter(
    IMintable _mintable,
    address _admin,
    address[] memory _targets,
    bytes[] memory _calldatas,
    uint256[] memory _values,
    address _recoveryAddress,
    uint256 _saltNonce
  ) external returns (address _minterTriggerAddress) {
    _minterTriggerAddress =
      _createMinter(_mintable, _admin, _targets, _calldatas, _values, _recoveryAddress, _saltNonce);
  }

  /// @notice Deploys a new `ZkMinterTriggerV1` contract using `CREATE2`. This overload accepts encoded args so it can be
  /// composed inside higher level factories.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _args Encoded args: `(address admin, address[] targets, bytes[] calldatas, uint256[] values,
  /// address recoveryAddress, uint256 saltNonce)`.
  /// @return The address of the newly deployed `ZkMinterTriggerV1`.
  function createMinter(IMintable _mintable, bytes memory _args) external returns (address) {
    (address _admin, address[] memory _targets, bytes[] memory _calldatas, uint256[] memory _values,
      address _recoveryAddress, uint256 _saltNonce) =
      abi.decode(_args, (address, address[], bytes[], uint256[], address, uint256));

    return _createMinter(_mintable, _admin, _targets, _calldatas, _values, _recoveryAddress, _saltNonce);
  }

  /// @notice Computes the address of a `ZkMinterTriggerV1` deployed via this factory.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _targets Target contracts invoked when `trigger()` executes.
  /// @param _calldatas Calldata forwarded to each target contract.
  /// @param _values ETH values forwarded with each call.
  /// @param _recoveryAddress Immutable address that receives recovered funds.
  /// @param _saltNonce The nonce used for salt calculation.
  /// @return _minterTriggerAddress The address of the `ZkMinterTriggerV1`.
  function getMinter(
    IMintable _mintable,
    address _admin,
    address[] memory _targets,
    bytes[] memory _calldatas,
    uint256[] memory _values,
    address _recoveryAddress,
    uint256 _saltNonce
  ) external view returns (address _minterTriggerAddress) {
    bytes32 _salt = _calculateSalt(_saltNonce);
    _minterTriggerAddress = L2ContractHelper.computeCreate2Address(
      address(this),
      _salt,
      BYTECODE_HASH,
      keccak256(abi.encode(_mintable, _admin, _targets, _calldatas, _values, _recoveryAddress))
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

  /// @notice Creates a new `ZkMinterTriggerV1` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _targets Target contracts invoked when `trigger()` executes.
  /// @param _calldatas Calldata forwarded to each target contract.
  /// @param _values ETH values forwarded with each call.
  /// @param _recoveryAddress Immutable address that receives recovered funds.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _minterTriggerAddress The address of the newly deployed `ZkMinterTriggerV1`.
  function _createMinter(
    IMintable _mintable,
    address _admin,
    address[] memory _targets,
    bytes[] memory _calldatas,
    uint256[] memory _values,
    address _recoveryAddress,
    uint256 _saltNonce
  ) internal returns (address _minterTriggerAddress) {
    bytes32 _salt = _calculateSalt(_saltNonce);

    ZkMinterTriggerV1 instance =
      new ZkMinterTriggerV1{salt: _salt}(_mintable, _admin, _targets, _calldatas, _values, _recoveryAddress);
    _minterTriggerAddress = address(instance);

    emit MinterTriggerCreated(_minterTriggerAddress, _mintable, _admin, _targets, _calldatas, _values, _recoveryAddress);
  }
}
