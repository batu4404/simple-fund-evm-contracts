// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";

import { AaveDecoderAndSanitizer } from "../src/decoders/AaveDecoderAndSanitizer.sol";
import { NestDecoderAndSanitizer, PredicateMessage } from "../src/decoders/NestDecoderAndSanitizer.sol";
import { LighterDecoderAndSanitizer } from "../src/decoders/LighterDecoderAndSanitizer.sol";
import { BaseDecoderAndSanitizer } from "../src/decoders/BaseDecoderAndSanitizer.sol";

contract DecodersTest is Test {
    address fund = makeAddr("fund");
    address stranger = makeAddr("stranger");
    address token = makeAddr("token");
    address vault = makeAddr("vault");

    AaveDecoderAndSanitizer aave;
    NestDecoderAndSanitizer nest;
    LighterDecoderAndSanitizer lighter;

    function setUp() public {
        aave = new AaveDecoderAndSanitizer(fund);
        nest = new NestDecoderAndSanitizer(fund);
        lighter = new LighterDecoderAndSanitizer(fund);
    }

    function testAave_Supply_PacksAddresses() public view {
        bytes memory packed = aave.supply(token, 1, fund, 0);
        assertEq(packed, abi.encodePacked(token, fund));
    }

    function testAave_Supply_NotFund_Reverts() public {
        vm.expectRevert(AaveDecoderAndSanitizer.AaveDecoderAndSanitizer_OnlyFund.selector);
        aave.supply(token, 1, stranger, 0);
    }

    function testAave_Withdraw_PacksAddresses() public view {
        bytes memory packed = aave.withdraw(token, 1, fund);
        assertEq(packed, abi.encodePacked(token, fund));
    }

    function testAave_Withdraw_NotFund_Reverts() public {
        vm.expectRevert(AaveDecoderAndSanitizer.AaveDecoderAndSanitizer_OnlyFund.selector);
        aave.withdraw(token, 1, stranger);
    }

    function testAave_Approve_PacksSpender() public view {
        bytes memory packed = aave.approve(vault, 1);
        assertEq(packed, abi.encodePacked(vault));
    }

    function testAave_UnknownSelector_Reverts() public {
        (bool ok, bytes memory ret) = address(aave).call(hex"deadbeef");
        assertFalse(ok);
        assertEq(
            ret,
            abi.encodeWithSelector(BaseDecoderAndSanitizer.FunctionNotImplemented.selector, hex"deadbeef")
        );
    }

    function testNest_Deposit_PacksAssetAndVault() public view {
        PredicateMessage memory message = PredicateMessage({
            taskId: "",
            expireByTime: 0,
            signerAddresses: new address[](0),
            signatures: new bytes[](0)
        });
        bytes memory packed = nest.deposit(token, 1, fund, vault, message);
        assertEq(packed, abi.encodePacked(token, vault));
    }

    function testNest_Deposit_NotFund_Reverts() public {
        PredicateMessage memory message = PredicateMessage({
            taskId: "",
            expireByTime: 0,
            signerAddresses: new address[](0),
            signatures: new bytes[](0)
        });
        vm.expectRevert(NestDecoderAndSanitizer.NestDecoderAndSanitizer_OnlyFund.selector);
        nest.deposit(token, 1, stranger, vault, message);
    }

    function testNest_RequestRedeem_NotFund_Reverts() public {
        vm.expectRevert(NestDecoderAndSanitizer.NestDecoderAndSanitizer_OnlyFund.selector);
        nest.requestRedeem(1, stranger, fund);
    }

    function testNest_Redeem_NotFund_Reverts() public {
        vm.expectRevert(NestDecoderAndSanitizer.NestDecoderAndSanitizer_OnlyFund.selector);
        nest.redeem(1, stranger, fund);
    }

    function testLighter_ConstructorDefaults() public view {
        assertTrue(lighter.isDepositAssetAllowed(3));
        assertTrue(lighter.isWithdrawAssetAllowed(3));
        assertTrue(lighter.isWithdrawRouteAllowed(3, 1));
        assertFalse(lighter.isDepositAssetAllowed(0));
    }

    function testLighter_Deposit_OnlyFund() public view {
        bytes memory packed = lighter.deposit(fund, 3, 1, 1);
        assertEq(packed.length, 0);
    }

    function testLighter_Deposit_WrongRecipient_Reverts() public {
        vm.expectRevert(LighterDecoderAndSanitizer.LighterDecoderAndSanitizer_OnlyFund.selector);
        lighter.deposit(stranger, 3, 1, 1);
    }

    function testLighter_Deposit_InvalidAssetIndex_Reverts() public {
        vm.expectRevert(LighterDecoderAndSanitizer.LighterDecoderAndSanitizer_InvalidAssetIndex.selector);
        lighter.deposit(fund, 0, 1, 1);
    }

    function testLighter_Withdraw_InvalidRoute_Reverts() public {
        vm.expectRevert(LighterDecoderAndSanitizer.LighterDecoderAndSanitizer_InvalidRouteType.selector);
        lighter.withdraw(1, 3, 2, 1);
    }
}
