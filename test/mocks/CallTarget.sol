// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract CallTarget {
    uint256 public counter;
    uint256 public fallbackCalls;
    uint256 public lastValue;

    function increment() external returns (uint256) {
        counter += 1;
        return counter;
    }

    function setCounter(uint256 newValue) external returns (uint256 oldValue) {
        oldValue = counter;
        counter = newValue;
    }

    function receiveValue() external payable returns (uint256) {
        lastValue = msg.value;
        return msg.value;
    }

    function revertWithReason() external pure {
        revert("CallTarget: execution failed");
    }

    function revertWithoutReason() external pure {
        revert();
    }

    fallback() external payable {
        fallbackCalls += 1;
        lastValue = msg.value;
    }

    receive() external payable {
        fallbackCalls += 1;
        lastValue = msg.value;
    }
}
