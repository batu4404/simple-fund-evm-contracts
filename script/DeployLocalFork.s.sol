// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Vm } from "forge-std/Vm.sol";

import { SimpleFund } from "../src/SimpleFund.sol";
import { AaveDecoderAndSanitizer } from "../src/decoders/AaveDecoderAndSanitizer.sol";
import { NestDecoderAndSanitizer } from "../src/decoders/NestDecoderAndSanitizer.sol";
import { LighterDecoderAndSanitizer } from "../src/decoders/LighterDecoderAndSanitizer.sol";

/// Local Anvil mainnet-fork deploy. USDC `deal()` does not write Circle's packed
/// balance slot, so we impersonate a whale. Nest's predicate manager is etched
/// to a tiny always-true stub (`PUSH1 1 / RETURN 32`).
///
/// Run against Anvil with `--unlocked` so the whale can send:
/// `forge script script/DeployLocalFork.s.sol:DeployLocalFork --rpc-url http://127.0.0.1:8545 --broadcast --unlocked`
contract DeployLocalFork is Script {
	Vm internal constant VM_UNSAFE = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

	address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
	address constant USDC_WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;
	address constant PREDICATE_MANAGER = 0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2;
	// PUSH1 0x01; PUSH1 0x00; MSTORE; PUSH1 0x20; PUSH1 0x00; RETURN
	bytes constant ALWAYS_TRUE = hex"600160005260206000f3";

	function run() external {
		uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
		uint256 passwordKey = vm.envUint("PASSWORD_SIGNER_KEY");
		address admin = vm.envAddress("ADMIN");
		address operator = vm.envAddress("OPERATOR");
		address passwordSigner = vm.addr(passwordKey);

		SimpleFund fund;
		AaveDecoderAndSanitizer aaveDecoder;
		NestDecoderAndSanitizer nestDecoder;
		LighterDecoderAndSanitizer lighterDecoder;

		vm.startBroadcast(deployerKey);

		fund = new SimpleFund(admin, operator, passwordSigner);
		aaveDecoder = new AaveDecoderAndSanitizer(address(fund));
		nestDecoder = new NestDecoderAndSanitizer(address(fund));
		lighterDecoder = new LighterDecoderAndSanitizer(address(fund));

		bytes32 decoderHash = keccak256(abi.encode(
			keccak256("setLighterDecoder"),
			fund.nonce(),
			address(fund),
			block.chainid,
			address(lighterDecoder)
		));
		{
			(uint8 v, bytes32 r, bytes32 s) = vm.sign(
				passwordKey,
				MessageHashUtils.toEthSignedMessageHash(decoderHash)
			);
			fund.setLighterDecoder(address(lighterDecoder), abi.encodePacked(r, s, v));
		}

		vm.stopBroadcast();

		VM_UNSAFE.etch(PREDICATE_MANAGER, ALWAYS_TRUE);
		VM_UNSAFE.deal(USDC_WHALE, 1 ether);

		vm.startBroadcast(USDC_WHALE);
		require(IERC20(USDC).transfer(admin, 1_000_000e6), "USDC transfer to admin failed");
		require(IERC20(USDC).transfer(address(fund), 100_000e6), "USDC transfer to fund failed");
		vm.stopBroadcast();

		console.log("FUND", address(fund));
		console.log("AAVE_DECODER", address(aaveDecoder));
		console.log("NEST_DECODER", address(nestDecoder));
		console.log("LIGHTER_DECODER", address(lighterDecoder));
		console.log("ADMIN", admin);
		console.log("OPERATOR", operator);
		console.log("PASSWORD_SIGNER", passwordSigner);
		console.log("CHAIN_ID", block.chainid);
	}
}
