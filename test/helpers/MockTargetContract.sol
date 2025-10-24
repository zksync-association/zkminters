// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract MockTargetContract {
  uint256 public value;
  bool public called;
  address public lastCaller;

  function setValue(uint256 _value) external payable {
    value = _value;
    called = true;
    lastCaller = msg.sender;
  }

  function revertFunction() external pure {
    revert("Mock revert");
  }

  receive() external payable {}
}
