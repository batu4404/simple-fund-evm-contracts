// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseDecoderAndSanitizer } from "./BaseDecoderAndSanitizer.sol";

contract AaveDecoderAndSanitizer is BaseDecoderAndSanitizer {
	error AaveDecoderAndSanitizer_OnlyFund();

	constructor(address _fund) BaseDecoderAndSanitizer(_fund) {}

	function supply(
		address asset,
		uint256,
		address onBehalfOf,
		uint16
	) external view returns (bytes memory addressesFound) {
		if (onBehalfOf != address(fund)) revert AaveDecoderAndSanitizer_OnlyFund();
		addressesFound = abi.encodePacked(asset, onBehalfOf);
	}

	function withdraw(
		address asset,
		uint256,
		address to
	) external view returns (bytes memory addressesFound) {
		if (to != address(fund)) revert AaveDecoderAndSanitizer_OnlyFund();
		addressesFound = abi.encodePacked(asset, to);
	}
}
