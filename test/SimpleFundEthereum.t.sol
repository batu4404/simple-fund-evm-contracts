// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SimpleFund } from "../src/SimpleFund.sol";
import { AaveDecoderAndSanitizer } from "../src/decoders/AaveDecoderAndSanitizer.sol";
import { NestDecoderAndSanitizer, PredicateMessage } from "../src/decoders/NestDecoderAndSanitizer.sol";
import { LighterDecoderAndSanitizer } from "../src/decoders/LighterDecoderAndSanitizer.sol";
import { CreateMerkleRoot } from "../script/CreateMerkleRoot.s.sol";
import { MerkleTreeLib } from "../script/merkle/MerkleTreeLib.sol";

interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

interface IZkLighter {
    function deposit(address _to, uint16 _assetIndex, uint8 _routeType, uint256 _amount) external;
}

interface INestVault {
    function owner() external view returns (address);
    function convertToShares(uint256 assets) external view returns (uint256);
    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256);
    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256);
    function fulfillRedeem(address controller, uint256 shares) external;
}

contract MockPredicateManager {
    fallback() external payable {
        assembly {
            mstore(0, 1)
            return(0, 32)
        }
    }
}

contract SimpleFundEthereumTest is Test {
    using MessageHashUtils for bytes32;

    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant NEST_PREDICATE_PROXY = 0xfC0c4222B3A0c9B060C0B959DEc62442036b9035;
    address constant NEST_VAULT = 0xD258029cF5a177e3306E09Fbea63424543a505c0;
    address constant NEST_SHARE_TOKEN = 0x119Dd7dAFf816f29D7eE47596ae5E4bdC4299165;
    address constant PREDICATE_MANAGER = 0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2;
    address constant ZK_LIGHTER = 0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7;

    uint256 constant ADMIN_KEY = 0xA11CE;
    uint256 constant PASSWORD_KEY = 0x5EC2E7;
    uint256 constant RELAYER_KEY = 0xCAFE;

    address admin;
    address operator;
    address passwordSigner;
    address relayer;

    SimpleFund fund;
    AaveDecoderAndSanitizer aaveDecoder;
    NestDecoderAndSanitizer nestDecoder;
    LighterDecoderAndSanitizer lighterDecoder;

    MerkleTreeLib.ManageLeaf[] internal leaves;
    bytes32[][] internal manageTree;

    function _sign(uint256 privKey, bytes32 rawHash) internal pure returns (bytes memory) {
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(rawHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, ethHash);
        return abi.encodePacked(r, s, v);
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

    function _setManageRootHash(bytes32 root) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("setManageRoot"),
            fund.nonce(),
            address(fund),
            block.chainid,
            root
        ));
    }

    function _emptyPredicate() internal pure returns (PredicateMessage memory message) {
        message.taskId = "";
        message.expireByTime = 0;
        message.signerAddresses = new address[](0);
        message.signatures = new bytes[](0);
    }

    function _setRoot(bytes32 root) internal {
        bytes memory psig = _sign(PASSWORD_KEY, _setManageRootHash(root));
        vm.prank(admin);
        fund.setManageRoot(root, psig);
    }

    function _select(
        address decoder,
        address target,
        string memory signature
    ) internal view returns (MerkleTreeLib.ManageLeaf memory) {
        bytes4 sel = bytes4(keccak256(bytes(signature)));
        uint256 n = leaves.length;
        for (uint256 i; i < n; ++i) {
            if (
                leaves[i].decoderAndSanitizer == decoder
                    && leaves[i].target == target
                    && MerkleTreeLib.selectorOf(leaves[i]) == sel
            ) {
                return leaves[i];
            }
        }
        revert("leaf not found");
    }

    function _execute(
        MerkleTreeLib.ManageLeaf[] memory selected,
        address[] memory decoders,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal {
        bytes32[][] memory proofs = MerkleTreeLib.getProofs(selected, manageTree);
        vm.prank(operator);
        fund.execute(proofs, decoders, targets, values, calldatas);
    }

    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");

        admin = vm.addr(ADMIN_KEY);
        passwordSigner = vm.addr(PASSWORD_KEY);
        operator = makeAddr("operator");
        relayer = vm.addr(RELAYER_KEY);

        fund = new SimpleFund(admin, operator, passwordSigner);
        aaveDecoder = new AaveDecoderAndSanitizer(address(fund));
        nestDecoder = new NestDecoderAndSanitizer(address(fund));
        lighterDecoder = new LighterDecoderAndSanitizer(address(fund));

        vm.etch(PREDICATE_MANAGER, address(new MockPredicateManager()).code);

        deal(USDC, address(fund), 100_000e6);

        CreateMerkleRoot generator = new CreateMerkleRoot();
        CreateMerkleRoot.Config memory config = CreateMerkleRoot.Config({
            fund: address(fund),
            aaveDecoder: address(aaveDecoder),
            nestDecoder: address(nestDecoder),
            lighterDecoder: address(lighterDecoder)
        });
        (MerkleTreeLib.ManageLeaf[] memory generated, bytes32[][] memory tree) =
            generator.generateMerkleTree(config);
        leaves = generated;
        manageTree = tree;
        _setRoot(manageTree[manageTree.length - 1][0]);
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

    function testFork_Aave_SupplyThenWithdraw() public {
        uint256 amount = 10_000e6;

        MerkleTreeLib.ManageLeaf[] memory selected = new MerkleTreeLib.ManageLeaf[](2);
        selected[0] = _select(address(aaveDecoder), USDC, "approve(address,uint256)");
        selected[1] = _select(address(aaveDecoder), AAVE_POOL, "supply(address,uint256,address,uint16)");

        address[] memory decoders = new address[](2);
        decoders[0] = address(aaveDecoder);
        decoders[1] = address(aaveDecoder);

        address[] memory targets = new address[](2);
        targets[0] = USDC;
        targets[1] = AAVE_POOL;

        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, AAVE_POOL, amount);
        calldatas[1] = abi.encodeWithSelector(IAavePool.supply.selector, USDC, amount, address(fund), uint16(0));

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(fund));
        _execute(selected, decoders, targets, values, calldatas);
        assertLt(IERC20(USDC).balanceOf(address(fund)), usdcBefore, "usdc should be supplied");

        uint256 withdrawAmount = amount / 2;
        MerkleTreeLib.ManageLeaf[] memory withdrawLeaves = new MerkleTreeLib.ManageLeaf[](1);
        withdrawLeaves[0] = _select(address(aaveDecoder), AAVE_POOL, "withdraw(address,uint256,address)");

        address[] memory withdrawDecoders = new address[](1);
        withdrawDecoders[0] = address(aaveDecoder);
        address[] memory withdrawTargets = new address[](1);
        withdrawTargets[0] = AAVE_POOL;
        uint256[] memory withdrawValues = new uint256[](1);
        bytes[] memory withdrawCalldatas = new bytes[](1);
        withdrawCalldatas[0] = abi.encodeWithSelector(
            IAavePool.withdraw.selector,
            USDC,
            withdrawAmount,
            address(fund)
        );

        uint256 usdcAfterSupply = IERC20(USDC).balanceOf(address(fund));
        _execute(withdrawLeaves, withdrawDecoders, withdrawTargets, withdrawValues, withdrawCalldatas);
        assertEq(
            IERC20(USDC).balanceOf(address(fund)),
            usdcAfterSupply + withdrawAmount,
            "fund should receive withdrawn usdc"
        );
    }

    function testFork_Nest_DepositRequestRedeemRedeem() public {
        uint256 amount = 100e6;

        bytes memory depositData = abi.encodeCall(
            NestDecoderAndSanitizer.deposit,
            (USDC, amount, address(fund), NEST_VAULT, _emptyPredicate())
        );

        MerkleTreeLib.ManageLeaf[] memory depositLeaves = new MerkleTreeLib.ManageLeaf[](2);
        depositLeaves[0] = _select(address(nestDecoder), USDC, "approve(address,uint256)");
        depositLeaves[1] = _select(
            address(nestDecoder),
            NEST_PREDICATE_PROXY,
            "deposit(address,uint256,address,address,(string,uint256,address[],bytes[]))"
        );

        address[] memory depositDecoders = new address[](2);
        depositDecoders[0] = address(nestDecoder);
        depositDecoders[1] = address(nestDecoder);
        address[] memory depositTargets = new address[](2);
        depositTargets[0] = USDC;
        depositTargets[1] = NEST_PREDICATE_PROXY;
        uint256[] memory depositValues = new uint256[](2);
        bytes[] memory depositCalldatas = new bytes[](2);
        depositCalldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, NEST_PREDICATE_PROXY, amount);
        depositCalldatas[1] = depositData;

        uint256 sharesBefore = IERC20(NEST_SHARE_TOKEN).balanceOf(address(fund));
        _execute(depositLeaves, depositDecoders, depositTargets, depositValues, depositCalldatas);
        uint256 shares = IERC20(NEST_SHARE_TOKEN).balanceOf(address(fund)) - sharesBefore;
        assertGt(shares, 0, "fund should receive nest shares");

        MerkleTreeLib.ManageLeaf[] memory requestLeaves = new MerkleTreeLib.ManageLeaf[](2);
        requestLeaves[0] = _select(address(nestDecoder), NEST_SHARE_TOKEN, "approve(address,uint256)");
        requestLeaves[1] = _select(address(nestDecoder), NEST_VAULT, "requestRedeem(uint256,address,address)");

        address[] memory requestDecoders = new address[](2);
        requestDecoders[0] = address(nestDecoder);
        requestDecoders[1] = address(nestDecoder);
        address[] memory requestTargets = new address[](2);
        requestTargets[0] = NEST_SHARE_TOKEN;
        requestTargets[1] = NEST_VAULT;
        uint256[] memory requestValues = new uint256[](2);
        bytes[] memory requestCalldatas = new bytes[](2);
        requestCalldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, NEST_VAULT, shares);
        requestCalldatas[1] = abi.encodeWithSelector(
            NestDecoderAndSanitizer.requestRedeem.selector,
            shares,
            address(fund),
            address(fund)
        );

        _execute(requestLeaves, requestDecoders, requestTargets, requestValues, requestCalldatas);
        assertEq(INestVault(NEST_VAULT).pendingRedeemRequest(0, address(fund)), shares);

        vm.prank(INestVault(NEST_VAULT).owner());
        INestVault(NEST_VAULT).fulfillRedeem(address(fund), shares);

        MerkleTreeLib.ManageLeaf[] memory redeemLeaves = new MerkleTreeLib.ManageLeaf[](1);
        redeemLeaves[0] = _select(address(nestDecoder), NEST_VAULT, "redeem(uint256,address,address)");

        address[] memory redeemDecoders = new address[](1);
        redeemDecoders[0] = address(nestDecoder);
        address[] memory redeemTargets = new address[](1);
        redeemTargets[0] = NEST_VAULT;
        uint256[] memory redeemValues = new uint256[](1);
        bytes[] memory redeemCalldatas = new bytes[](1);
        redeemCalldatas[0] = abi.encodeWithSelector(
            NestDecoderAndSanitizer.redeem.selector,
            shares,
            address(fund),
            address(fund)
        );

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(fund));
        _execute(redeemLeaves, redeemDecoders, redeemTargets, redeemValues, redeemCalldatas);
        assertGt(IERC20(USDC).balanceOf(address(fund)), usdcBefore, "fund should receive usdc from redeem");
    }

    function testFork_Lighter_ApproveAndDeposit() public {
        uint256 amount = 10e6;

        MerkleTreeLib.ManageLeaf[] memory selected = new MerkleTreeLib.ManageLeaf[](2);
        selected[0] = _select(address(lighterDecoder), USDC, "approve(address,uint256)");
        selected[1] = _select(address(lighterDecoder), ZK_LIGHTER, "deposit(address,uint16,uint8,uint256)");

        address[] memory decoders = new address[](2);
        decoders[0] = address(lighterDecoder);
        decoders[1] = address(lighterDecoder);
        address[] memory targets = new address[](2);
        targets[0] = USDC;
        targets[1] = ZK_LIGHTER;
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, ZK_LIGHTER, amount);
        calldatas[1] = abi.encodeWithSelector(IZkLighter.deposit.selector, address(fund), uint16(3), uint8(1), amount);

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(fund));
        _execute(selected, decoders, targets, values, calldatas);
        assertEq(IERC20(USDC).balanceOf(address(fund)), usdcBefore - amount, "usdc should be deposited to lighter");
    }

    function testFork_Lighter_WrongRecipient_Reverts() public {
        uint256 amount = 10e6;

        MerkleTreeLib.ManageLeaf[] memory selected = new MerkleTreeLib.ManageLeaf[](1);
        selected[0] = _select(address(lighterDecoder), ZK_LIGHTER, "deposit(address,uint16,uint8,uint256)");

        address[] memory decoders = new address[](1);
        decoders[0] = address(lighterDecoder);
        address[] memory targets = new address[](1);
        targets[0] = ZK_LIGHTER;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IZkLighter.deposit.selector, address(this), uint16(3), uint8(1), amount);

        bytes32[][] memory proofs = MerkleTreeLib.getProofs(selected, manageTree);

        vm.prank(operator);
        vm.expectRevert(LighterDecoderAndSanitizer.LighterDecoderAndSanitizer_OnlyFund.selector);
        fund.execute(proofs, decoders, targets, values, calldatas);
    }

    function testFork_Lighter_DisallowedAssetIndex_Reverts() public {
        uint256 amount = 10e6;

        MerkleTreeLib.ManageLeaf[] memory selected = new MerkleTreeLib.ManageLeaf[](1);
        selected[0] = _select(address(lighterDecoder), ZK_LIGHTER, "deposit(address,uint16,uint8,uint256)");

        address[] memory decoders = new address[](1);
        decoders[0] = address(lighterDecoder);
        address[] memory targets = new address[](1);
        targets[0] = ZK_LIGHTER;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IZkLighter.deposit.selector, address(fund), uint16(0), uint8(1), amount);

        bytes32[][] memory proofs = MerkleTreeLib.getProofs(selected, manageTree);

        vm.prank(operator);
        vm.expectRevert(LighterDecoderAndSanitizer.LighterDecoderAndSanitizer_InvalidAssetIndex.selector);
        fund.execute(proofs, decoders, targets, values, calldatas);
    }
}
