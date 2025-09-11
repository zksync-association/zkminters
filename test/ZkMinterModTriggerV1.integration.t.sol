// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterModTriggerV1} from "src/ZkMinterModTriggerV1.sol";
import {ZkMinterModTriggerV1Test} from "test/ZkMinterModTriggerV1.t.sol";

contract ZkMinterModTriggerV1Integration is ZkMinterModTriggerV1Test {
  function testFuzz_TokensSentToTargetWhenMintedAndTriggered(
    address _caller,
    address _recipient,
    uint256 _amount,
    uint256 _ethValue,
    uint256 _setValue
  ) public {
    _amount = bound(_amount, 1, cappedMinter.CAP());
    _ethValue = bound(_ethValue, 0, 1000 ether);
    vm.assume(_recipient != address(0));

    // Create a trigger that first transfers ERC20 tokens from the trigger to the mock target,
    // then calls the mock target's setValue with ETH.
    address[] memory _targets = new address[](2);
    _targets[0] = address(token);
    _targets[1] = address(mockTarget);

    bytes[] memory _calldatas = new bytes[](2);
    _calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount);
    _calldatas[1] = abi.encodeWithSelector(mockTarget.setValue.selector, _setValue);

    uint256[] memory _values = new uint256[](2);
    _values[0] = 0;
    _values[1] = _ethValue;

    ZkMinterModTriggerV1 _multiTrigger =
      new ZkMinterModTriggerV1(mintable, admin, _targets, _calldatas, _values, recoveryAddress);

    // Configure roles
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(_multiTrigger));
    vm.prank(admin);
    _multiTrigger.grantRole(MINTER_ROLE, _caller);

    // Mint tokens
    vm.prank(_caller);
    _multiTrigger.mint(address(_multiTrigger), _amount);
    assertEq(token.balanceOf(address(_multiTrigger)), _amount);

    // Call trigger
    vm.deal(address(_caller), _ethValue);
    vm.prank(_caller);
    _multiTrigger.trigger{value: _ethValue}();

    // Verify mock target call and ETH transfer
    assertEq(mockTarget.value(), _setValue);
    assertEq(mockTarget.called(), true);
    assertEq(mockTarget.lastCaller(), address(_multiTrigger));
    assertEq(address(mockTarget).balance, _ethValue);

    // Verify ERC20 tokens were transferred from the trigger to the mock target
    assertEq(token.balanceOf(address(_multiTrigger)), 0);
    assertEq(token.balanceOf(_recipient), _amount);
  }
}
