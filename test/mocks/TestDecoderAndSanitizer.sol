// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract TestDecoderAndSanitizer {
	function increment() external pure returns (bytes memory addressesFound) {}

	function setCounter(uint256) external pure returns (bytes memory addressesFound) {}

	function receiveValue() external pure returns (bytes memory addressesFound) {}

	function revertWithReason() external pure returns (bytes memory addressesFound) {}

	function revertWithoutReason() external pure returns (bytes memory addressesFound) {}

	fallback(bytes calldata) external returns (bytes memory addressesFound) {
		addressesFound = "";
	}
}
