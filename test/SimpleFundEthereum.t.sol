// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SimpleFund } from "../src/SimpleFund.sol";
import { IMorpho, Id, MarketParams } from "../src/interfaces/IMorpho.sol";

contract SimpleFundEthereumTest is Test {
    using MessageHashUtils for bytes32;

    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 constant MID_0 = 0x4565ac05d38b19374ccbb04c17cca60ca9353cd41824f0803d0fc7704f60eaed;
    bytes32 constant MID_1 = 0x2a9a5c436719badcfadbad3ad8e8179a160ded758603eaa03a883f922a1790d3;

    uint256 constant ADMIN_KEY = 0xA11CE;
    uint256 constant PASSWORD_KEY = 0x5EC2E7;
    uint256 constant RELAYER_KEY = 0xCAFE;

    address admin;
    address operator;
    address passwordSigner;
    address relayer;

    SimpleFund fund;
    IMorpho morpho;

    function _sign(uint256 privKey, bytes32 rawHash) internal pure returns (bytes memory) {
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(rawHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _executeHash(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("execute"),
            fund.nonce(),
            address(fund),
            block.chainid,
            targets,
            values,
            calldatas
        ));
    }

    function _withdrawHash(address token, uint256 amount, address recipient) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("withdraw"),
            fund.nonce(),
            address(fund),
            block.chainid,
            token,
            amount,
            recipient
        ));
    }

    function _execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas) internal {
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));
        vm.prank(operator);
        fund.execute(targets, values, calldatas, psig);
    }

    function _supply(Id marketId, uint256 amount) internal {
        MarketParams memory params = morpho.idToMarketParams(marketId);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        targets[0] = USDC;
        calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, MORPHO, amount);

        targets[1] = MORPHO;
        calldatas[1] = abi.encodeWithSignature(
            "supply((address,address,address,address,uint256),uint256,uint256,address,bytes)",
            params,
            amount,
            0,
            address(fund),
            bytes("")
        );

        _execute(targets, values, calldatas);
    }

    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");

        admin = vm.addr(ADMIN_KEY);
        passwordSigner = vm.addr(PASSWORD_KEY);
        operator = makeAddr("operator");
        relayer = vm.addr(RELAYER_KEY);

        morpho = IMorpho(MORPHO);
        fund = new SimpleFund(admin, operator, passwordSigner);

        deal(USDC, address(fund), 100_000e6);
    }

    function testFork_Execute_SupplySingleMarket() public {
        Id marketId = Id.wrap(MID_0);
        uint256 sharesBefore = morpho.position(marketId, address(fund)).supplyShares;

        _supply(marketId, 10_000e6);

        uint256 sharesAfter = morpho.position(marketId, address(fund)).supplyShares;
        assertGt(sharesAfter, sharesBefore, "supply shares should increase");
    }

    function testFork_Execute_SupplyThenWithdrawSingleMarket() public {
        Id marketId = Id.wrap(MID_0);
        uint256 startBalance = IERC20(USDC).balanceOf(address(fund));

        _supply(marketId, 8_000e6);

        uint256 shares = morpho.position(marketId, address(fund)).supplyShares;
        assertGt(shares, 0, "shares should be positive after supply");

        MarketParams memory params = morpho.idToMarketParams(marketId);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = MORPHO;
        calldatas[0] = abi.encodeWithSignature(
            "withdraw((address,address,address,address,uint256),uint256,uint256,address,address)",
            params,
            0,
            shares,
            address(fund),
            address(fund)
        );

        _execute(targets, values, calldatas);

        uint256 endShares = morpho.position(marketId, address(fund)).supplyShares;
        assertEq(endShares, 0, "all shares should be withdrawn");

        uint256 endBalance = IERC20(USDC).balanceOf(address(fund));
        assertApproxEqAbs(endBalance, startBalance, 2, "fund should recover usdc after withdraw");
    }

    function testFork_Execute_MultiMarket_BatchFlow() public {
        Id market0 = Id.wrap(MID_0);
        Id market1 = Id.wrap(MID_1);

        _supply(market0, 3_000e6);
        _supply(market1, 4_000e6);

        assertGt(morpho.position(market0, address(fund)).supplyShares, 0, "market0 has shares");
        assertGt(morpho.position(market1, address(fund)).supplyShares, 0, "market1 has shares");

        MarketParams memory params0 = morpho.idToMarketParams(market0);
        MarketParams memory params1 = morpho.idToMarketParams(market1);

        uint256 shares0 = morpho.position(market0, address(fund)).supplyShares;
        uint256 shares1 = morpho.position(market1, address(fund)).supplyShares;

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        targets[0] = MORPHO;
        calldatas[0] = abi.encodeWithSignature(
            "withdraw((address,address,address,address,uint256),uint256,uint256,address,address)",
            params0,
            0,
            shares0,
            address(fund),
            address(fund)
        );

        targets[1] = MORPHO;
        calldatas[1] = abi.encodeWithSignature(
            "withdraw((address,address,address,address,uint256),uint256,uint256,address,address)",
            params1,
            0,
            shares1,
            address(fund),
            address(fund)
        );

        _execute(targets, values, calldatas);

        assertEq(morpho.position(market0, address(fund)).supplyShares, 0, "market0 shares cleared");
        assertEq(morpho.position(market1, address(fund)).supplyShares, 0, "market1 shares cleared");
    }

    function testFork_WithdrawRelay_Valid() public {
        uint256 withdrawAmount = 1_500e6;
        bytes32 hash = _withdrawHash(USDC, withdrawAmount, admin);

        bytes memory asig = _sign(ADMIN_KEY, hash);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        uint256 before = IERC20(USDC).balanceOf(admin);

        vm.prank(relayer);
        fund.withdrawRelay(USDC, withdrawAmount, admin, asig, psig);

        assertEq(IERC20(USDC).balanceOf(admin), before + withdrawAmount, "relay withdraw should transfer usdc");
    }
}
