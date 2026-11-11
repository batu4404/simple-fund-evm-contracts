// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import { Script } from "forge-std/Script.sol";
import { SimpleFund } from "../src/SimpleFund.sol";
import { console } from "forge-std/console.sol";

contract DeploySimpleFund is Script {
    address internal deployer;

    address internal admin;
    address internal operator;
    address internal passwordSigner;
    string internal saltString;

    constructor() {
        deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        admin = vm.envAddress("ADMIN");
        operator = vm.envAddress("OPERATOR");
        passwordSigner = vm.envAddress("PASSWORD_SIGNER");
        saltString = vm.envString("SALT");
    }

    function setUp() public {}

    function run() public {
        bytes32 salt = keccak256(bytes(saltString));
        bytes memory initCode = abi.encodePacked(
            type(SimpleFund).creationCode,
            abi.encode(admin, operator, passwordSigner)
        );
        address predictedAddress = vm.computeCreate2Address(salt, keccak256(initCode), CREATE2_FACTORY);

        vm.startBroadcast(deployer);

        SimpleFund fund = new SimpleFund{salt: salt}(
            admin,
            operator,
            passwordSigner
        );

        console.log("Salt string:", saltString);
        console.logBytes32(salt);
        console.log("CREATE2 factory:", CREATE2_FACTORY);
        console.log("Predicted fund address:", predictedAddress);
        console.log("Admin:", admin);
        console.log("Operator:", operator);
        console.log("Password signer:", passwordSigner);
        console.log("Fund deployed at:", address(fund));

        vm.stopBroadcast();
    }
}
