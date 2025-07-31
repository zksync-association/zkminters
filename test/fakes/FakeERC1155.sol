// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract FakeERC1155 is IERC1155 {
  // Mapping from account to token ID to balance
  mapping(address => mapping(uint256 => uint256)) private _balances;

  /// @notice Sets the balance for a specific account and tokenId
  /// @param account The account to set balance for
  /// @param id The token ID
  /// @param amount The balance amount to set
  function setBalance(address account, uint256 id, uint256 amount) external {
    _balances[account][id] = amount;
  }

  /// @notice Returns the balance of an account for a specific token ID
  /// @param account The account to check balance for
  /// @param id The token ID
  /// @return The balance amount
  function balanceOf(address account, uint256 id) external view override returns (uint256) {
    return _balances[account][id];
  }

  /// @notice Returns the balances of an account for multiple token IDs
  /// @param accounts The accounts to check balances for
  /// @param ids The token IDs
  /// @return The balance amounts
  function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
    external
    view
    override
    returns (uint256[] memory)
  {
    require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");
    uint256[] memory batchBalances = new uint256[](accounts.length);

    for (uint256 i = 0; i < accounts.length; ++i) {
      batchBalances[i] = _balances[accounts[i]][ids[i]];
    }

    return batchBalances;
  }

  function setApprovalForAll(address operator, bool approved) external override {
    // Empty implementation for testing
  }

  function isApprovedForAll(address, address) external pure override returns (bool) {
    return false; // Always return false for simplicity in testing
  }

  function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data)
    external
    override
  {
    // Empty implementation for testing
  }

  function safeBatchTransferFrom(
    address from,
    address to,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes calldata data
  ) external override {
    // Empty implementation for testing
  }

  function uri(uint256) external pure returns (string memory) {
    return ""; // Return empty string for simplicity in testing
  }

  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return interfaceId == type(IERC1155).interfaceId;
  }
}
