// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

/// @notice A struct that represents a mint request.
/// @param minter The address that requested the mint.
/// @param to The address that will receive the new tokens.
/// @param amount The quantity of tokens that will be minted.
/// @param createdAt The timestamp when the mint request was created.
/// @param executed Whether the mint request has been executed.
/// @param vetoed Whether the mint request has been vetoed.
struct MintRequest {
  address minter;
  address to;
  uint256 amount;
  uint48 createdAt;
  bool executed;
  bool vetoed;
}

/// @title ZkMinterDelayV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract that implements a delay mechanism for token minting. This contract allows authorized minters
/// to create mint requests that must wait for a configurable delay period before they can be executed. This provides
/// a time-based security mechanism where:
/// - Minters can create mint requests immediately
/// - Requests must wait for a specified delay period before execution
/// - Anyone can execute valid requests after the delay period
/// - Admins can veto pending requests before execution
/// - The delay period can be updated by admins (affects all pending requests)
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterDelayV1 is ZkMinterV1 {
  /*///////////////////////////////////////////////////////////////
                          Events
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when the mint delay is updated.
  event MintDelayUpdated(uint48 indexed previousMintDelay, uint48 indexed newMintDelay);

  /// @notice Emitted when a mint request is made.
  event MintRequested(uint256 indexed mintRequestId, address indexed to, uint256 amount, uint48 executableAt);


  /// @notice Emitted when a mint request is vetoed.
  event MintRequestVetoed(uint256 indexed mintRequestId);

  /// @notice The unique identifier constant used to represent the veto role. An address that has this role may call
  /// the `vetoMintRequest` method, vetoing pending mint requests. This role may be granted or revoked by the
  /// DEFAULT_ADMIN_ROLE.
  bytes32 public constant VETO_ROLE = keccak256("VETO_ROLE");

  /*///////////////////////////////////////////////////////////////
                          Errors
  //////////////////////////////////////////////////////////////*/

  /// @notice Error for when a zero address is provided where it's not allowed.
  error ZkMinterDelayV1__InvalidZeroAddress();

  /// @notice Error for when the mint delay is not set.
  error ZkMinterDelayV1__InvalidMintDelay();

  /// @notice Error for when the mint request is invalid.
  /// @param _mintRequestId The invalid mint request id.
  error ZkMinterDelayV1__InvalidMintRequest(uint256 _mintRequestId);

  /// @notice Error thrown when a mint request is executed before the required delay period has elapsed.
  /// @param _mintRequestId The mint request id.
  error ZkMinterDelayV1__MintRequestNotReady(uint256 _mintRequestId);

  /// @notice Error thrown when a mint request has already been executed.
  /// @param _mintRequestId The mint request id.
  error ZkMinterDelayV1__MintAlreadyExecuted(uint256 _mintRequestId);

  /// @notice Error thrown when a mint request has been vetoed.
  /// @param _mintRequestId The mint request id.
  error ZkMinterDelayV1__MintRequestVetoed(uint256 _mintRequestId);

  /*///////////////////////////////////////////////////////////////
                          State Variables
  //////////////////////////////////////////////////////////////*/

  /// @notice The next mint request id.
  uint256 public nextMintRequestId = 1;

  /// @notice The delay in seconds before minting can begin.
  uint48 public mintDelay;

  /// @notice A mapping of mint request id to the mint request.
  mapping(uint256 mintRequestId => MintRequest) internal mintRequests;

  /*///////////////////////////////////////////////////////////////
                          Constructor
  //////////////////////////////////////////////////////////////*/

  /// @notice Initializes the contract with the mintable contract, admin, and mint delay.
  /// @param _mintable A contract used as a target when calling mint. Any contract that conforms to the IMintable
  /// interface can be used, but in most cases this will be another `ZKMinter` extension or `ZKCappedMinter`.
  /// @param _admin The address that will have admin privileges.
  /// @param _mintDelay The delay in seconds before minting can begin.
  constructor(IMintable _mintable, address _admin, uint48 _mintDelay) {
    if (_admin == address(0)) {
      revert ZkMinterDelayV1__InvalidZeroAddress();
    }

    _updateMintable(_mintable);
    _updateMintDelay(_mintDelay);

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);
    _grantRole(VETO_ROLE, _admin);
  }

  /*///////////////////////////////////////////////////////////////
                          External Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Creates a new mint request.
  /// @dev The actual minting does not occur immediately; it must be executed separately.
  /// @param _to The address that will receive the new tokens.
  /// @param _amount The quantity of tokens that will be minted.
  function mint(address _to, uint256 _amount) external virtual {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);

    if (_to == address(0)) {
      revert ZkMinterDelayV1__InvalidZeroAddress();
    }

    uint48 _createdAt = uint48(block.timestamp);
    uint256 currentRequestId = nextMintRequestId++;

    mintRequests[currentRequestId] =
      MintRequest({minter: msg.sender, to: _to, amount: _amount, createdAt: _createdAt, executed: false, vetoed: false});

    emit MintRequested(currentRequestId, _to, _amount, _createdAt + mintDelay);
  }

  /// @notice Executes a mint request minting the amount of tokens specified in the request for the specified to
  /// address.
  /// @param _mintRequestId The id of the mint request to execute.
  /// @dev Callable by anyone post execution delay.
  function executeMint(uint256 _mintRequestId) external virtual {
    _revertIfClosed();
    _requireNotPaused();

    MintRequest storage mintRequest = mintRequests[_mintRequestId];

    // check if the mint request is valid
    if (mintRequest.createdAt == 0) {
      revert ZkMinterDelayV1__InvalidMintRequest(_mintRequestId);
    }

    // check if the mint request has already been executed
    if (mintRequest.executed) {
      revert ZkMinterDelayV1__MintAlreadyExecuted(_mintRequestId);
    }

    // check if the mint request has been vetoed
    if (mintRequest.vetoed) {
      revert ZkMinterDelayV1__MintRequestVetoed(_mintRequestId);
    }

    // check if the mint delay has elapsed
    if (block.timestamp < mintRequest.createdAt + mintDelay) {
      revert ZkMinterDelayV1__MintRequestNotReady(_mintRequestId);
    }

    mintRequest.executed = true;
    mintable.mint(mintRequest.to, mintRequest.amount);

    emit Minted(mintRequest.minter, mintRequest.to, mintRequest.amount);
  }

  /// @notice Updates the mint delay.
  /// @param _newMintDelay The new mint delay in seconds.
  function updateMintDelay(uint48 _newMintDelay) external virtual {
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _updateMintDelay(_newMintDelay);
  }

  /// @notice Returns the mint request for a given mint request id.
  /// @param _mintRequestId The id of the mint request to return.
  /// @return The mint request.
  function getMintRequest(uint256 _mintRequestId) external view virtual returns (MintRequest memory) {
    return mintRequests[_mintRequestId];
  }

  /// @notice Veto a mint request.
  /// @param _mintRequestId The id of the mint request to veto.
  /// @dev Callable by addresses with VETO_ROLE.
  function vetoMintRequest(uint256 _mintRequestId) external virtual {
    _checkRole(VETO_ROLE, msg.sender);

    MintRequest storage mintRequest = mintRequests[_mintRequestId];

    // check if the mint request is valid
    if (mintRequest.createdAt == 0) {
      revert ZkMinterDelayV1__InvalidMintRequest(_mintRequestId);
    }

    // revert if mint request has already been executed
    if (mintRequest.executed) {
      revert ZkMinterDelayV1__MintAlreadyExecuted(_mintRequestId);
    }

	
   // revert if mint request has already been vetoed
   if (mintRequest.vetoed) {
       revert ZkMinterDelayV1__MintRequestVetoed(_mintRequestId);
   }

    mintRequest.vetoed = true;

    emit MintRequestVetoed(_mintRequestId);
  }

  /*///////////////////////////////////////////////////////////////
                          Internal Functions
  //////////////////////////////////////////////////////////////*/

  /// @notice Updates the mint delay.
  /// @param _newMintDelay The new mint delay in seconds.
  /// @dev Updating this will affect any unexecuted mint requests.
  function _updateMintDelay(uint48 _newMintDelay) internal virtual {
    if (_newMintDelay == 0) {
      revert ZkMinterDelayV1__InvalidMintDelay();
    }
    emit MintDelayUpdated(mintDelay, _newMintDelay);
    mintDelay = _newMintDelay;
  }
}
