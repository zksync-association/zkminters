// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Mock Reverting Recovery Address
/// @notice Testing helper that models a recovery address unable to receive ETH.
/// @dev Reverts on every ETH transfer, allowing tests to exercise failure paths in recovery flows.
contract MockRevertingRecoveryAddress {
  /// @notice Always reverts when receiving ETH.
  /// @dev Reverts with a fixed string so tests can assert on the failure.
  receive() external payable {
    revert("MockRevertingRecoveryAddress: cannot receive ETH");
  }
}

