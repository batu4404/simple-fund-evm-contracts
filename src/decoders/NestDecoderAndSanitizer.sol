// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseDecoderAndSanitizer } from "./BaseDecoderAndSanitizer.sol";

struct PredicateMessage {
	string taskId;
	uint256 expireByTime;
	address[] signerAddresses;
	bytes[] signatures;
}

contract NestDecoderAndSanitizer is BaseDecoderAndSanitizer {
	error NestDecoderAndSanitizer_OnlyFund();

	constructor(address _fund) BaseDecoderAndSanitizer(_fund) {}

	function deposit(
		address depositAsset,
		uint256,
		address recipient,
		address vault,
		PredicateMessage calldata
	) external view returns (bytes memory addressesFound) {
		if (recipient != address(fund)) revert NestDecoderAndSanitizer_OnlyFund();
		addressesFound = abi.encodePacked(depositAsset, vault);
	}

	function requestRedeem(
		uint256,
		address controller,
		address owner
	) external view returns (bytes memory addressesFound) {
		if (controller != address(fund) || owner != address(fund)) revert NestDecoderAndSanitizer_OnlyFund();
		return addressesFound;
	}

	function redeem(
		uint256,
		address receiver,
		address controller
	) external view returns (bytes memory addressesFound) {
		if (controller != address(fund) || receiver != address(fund)) revert NestDecoderAndSanitizer_OnlyFund();
		return addressesFound;
	}
}
