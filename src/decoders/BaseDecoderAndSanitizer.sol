// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { SimpleFund } from "../SimpleFund.sol";

contract BaseDecoderAndSanitizer {
	SimpleFund public immutable fund;

	error FunctionNotImplemented(bytes calldataData);

	constructor(address _fund) {
		require(_fund != address(0), "Zero fund");
		fund = SimpleFund(payable(_fund));
	}

	function approve(address spender, uint256) external pure returns (bytes memory addressesFound) {
		addressesFound = abi.encodePacked(spender);
	}

	fallback() external {
		revert FunctionNotImplemented(msg.data);
	}
}
