// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseDecoderAndSanitizer } from "./BaseDecoderAndSanitizer.sol";

contract LighterDecoderAndSanitizer is BaseDecoderAndSanitizer {
	error LighterDecoderAndSanitizer_OnlyFund();
	error LighterDecoderAndSanitizer_InvalidAssetIndex();
	error LighterDecoderAndSanitizer_InvalidRouteType();

	mapping(uint16 => bool) public isDepositAssetAllowed;
	mapping(uint16 => bool) public isWithdrawAssetAllowed;
	mapping(uint16 => mapping(uint8 => bool)) public isWithdrawRouteAllowed;

	constructor(address _fund) BaseDecoderAndSanitizer(_fund) {
		isDepositAssetAllowed[3] = true;
		isWithdrawAssetAllowed[3] = true;
		isWithdrawRouteAllowed[3][1] = true;
	}

	function deposit(
		address _to,
		uint16 _assetIndex,
		uint8,
		uint256
	) external view returns (bytes memory addressesFound) {
		if (_to != address(fund)) revert LighterDecoderAndSanitizer_OnlyFund();
		if (!isDepositAssetAllowed[_assetIndex]) revert LighterDecoderAndSanitizer_InvalidAssetIndex();
		return addressesFound;
	}

	function withdraw(
		uint48,
		uint16 _assetIndex,
		uint8 _routeType,
		uint64
	) external view returns (bytes memory addressesFound) {
		if (!isWithdrawAssetAllowed[_assetIndex]) revert LighterDecoderAndSanitizer_InvalidAssetIndex();
		if (!isWithdrawRouteAllowed[_assetIndex][_routeType]) {
			revert LighterDecoderAndSanitizer_InvalidRouteType();
		}
		return addressesFound;
	}

	function cancelAllOrders(uint48) external pure returns (bytes memory addressesFound) {
		return addressesFound;
	}

	function burnShares(uint48, uint48, uint64) external pure returns (bytes memory addressesFound) {
		return addressesFound;
	}

	function setDepositAssetAllowed(
		uint16 assetIndex,
		bool allowed,
		bytes calldata passwordSig
	) external {
		require(msg.sender == fund.admin(), "Not admin");

		bytes32 hash = keccak256(abi.encode(
			keccak256("setLighterDepositAssetAllowed"),
			fund.nonce(),
			address(fund),
			block.chainid,
			assetIndex,
			allowed
		));
		fund.consumeDecoderPassword(hash, passwordSig);

		isDepositAssetAllowed[assetIndex] = allowed;
	}

	function setWithdrawAssetAllowed(
		uint16 assetIndex,
		bool allowed,
		bytes calldata passwordSig
	) external {
		require(msg.sender == fund.admin(), "Not admin");

		bytes32 hash = keccak256(abi.encode(
			keccak256("setLighterWithdrawAssetAllowed"),
			fund.nonce(),
			address(fund),
			block.chainid,
			assetIndex,
			allowed
		));
		fund.consumeDecoderPassword(hash, passwordSig);

		isWithdrawAssetAllowed[assetIndex] = allowed;
	}

	function setWithdrawRouteAllowed(
		uint16 assetIndex,
		uint8 routeType,
		bool allowed,
		bytes calldata passwordSig
	) external {
		require(msg.sender == fund.admin(), "Not admin");

		bytes32 hash = keccak256(abi.encode(
			keccak256("setLighterWithdrawRouteAllowed"),
			fund.nonce(),
			address(fund),
			block.chainid,
			assetIndex,
			routeType,
			allowed
		));
		fund.consumeDecoderPassword(hash, passwordSig);

		isWithdrawRouteAllowed[assetIndex][routeType] = allowed;
	}
}
