// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract MockLighter {
	address public lastDepositTo;
	uint16 public lastDepositAssetIndex;
	uint8 public lastDepositRouteType;
	uint256 public lastDepositAmount;

	uint48 public lastWithdrawAccountIndex;
	uint16 public lastWithdrawAssetIndex;
	uint8 public lastWithdrawRouteType;
	uint64 public lastWithdrawAmount;

	uint48 public lastCancelAccountIndex;

	uint48 public lastBurnAccountIndex;
	uint48 public lastBurnPoolIndex;
	uint64 public lastBurnShareAmount;

	function deposit(address _to, uint16 _assetIndex, uint8 _routeType, uint256 _amount) external {
		lastDepositTo = _to;
		lastDepositAssetIndex = _assetIndex;
		lastDepositRouteType = _routeType;
		lastDepositAmount = _amount;
	}

	function withdraw(uint48 _accountIndex, uint16 _assetIndex, uint8 _routeType, uint64 _baseAmount) external {
		lastWithdrawAccountIndex = _accountIndex;
		lastWithdrawAssetIndex = _assetIndex;
		lastWithdrawRouteType = _routeType;
		lastWithdrawAmount = _baseAmount;
	}

	function cancelAllOrders(uint48 _accountIndex) external {
		lastCancelAccountIndex = _accountIndex;
	}

	function burnShares(uint48 _accountIndex, uint48 _publicPoolIndex, uint64 _shareAmount) external {
		lastBurnAccountIndex = _accountIndex;
		lastBurnPoolIndex = _publicPoolIndex;
		lastBurnShareAmount = _shareAmount;
	}
}
