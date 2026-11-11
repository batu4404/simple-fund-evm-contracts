// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { SimpleFund } from "../src/SimpleFund.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { CallTarget } from "./mocks/CallTarget.sol";

contract SimpleFundTest is Test {
    using MessageHashUtils for bytes32;

    uint256 constant ADMIN_KEY = 0xA11CE;
    uint256 constant PASSWORD_KEY = 0x5EC2E7;
    uint256 constant ATTACKER_KEY = 0xBAD;
    uint256 constant RELAYER_KEY = 0xCAFE;
    uint256 constant NEW_ADMIN_KEY = 0xBEEF;
    uint256 constant NEW_PASSWORD_KEY = 0xAA1122;

    address admin;
    address operator;
    address passwordSigner;
    address attacker;
    address relayer;

    SimpleFund fund;
    MockERC20 tokenA;
    MockERC20 tokenB;
    CallTarget target;

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

    function _setOperatorHash(address newOperator) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("setOperator"),
            fund.nonce(),
            address(fund),
            block.chainid,
            newOperator
        ));
    }

    function _setPasswordSignerHash(address newSigner) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("setPasswordSigner"),
            fund.nonce(),
            address(fund),
            block.chainid,
            newSigner
        ));
    }

    function _setAdminHash(address newAdmin) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("setAdmin"),
            fund.nonce(),
            address(fund),
            block.chainid,
            newAdmin
        ));
    }

    function _arr1(address a) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }

    function _arr2(address a, address b) internal pure returns (address[] memory r) {
        r = new address[](2);
        r[0] = a;
        r[1] = b;
    }

    function _vals1(uint256 a) internal pure returns (uint256[] memory r) {
        r = new uint256[](1);
        r[0] = a;
    }

    function _vals2(uint256 a, uint256 b) internal pure returns (uint256[] memory r) {
        r = new uint256[](2);
        r[0] = a;
        r[1] = b;
    }

    function _data1(bytes memory a) internal pure returns (bytes[] memory r) {
        r = new bytes[](1);
        r[0] = a;
    }

    function _data2(bytes memory a, bytes memory b) internal pure returns (bytes[] memory r) {
        r = new bytes[](2);
        r[0] = a;
        r[1] = b;
    }

    function setUp() public {
        admin = vm.addr(ADMIN_KEY);
        passwordSigner = vm.addr(PASSWORD_KEY);
        operator = makeAddr("operator");
        attacker = vm.addr(ATTACKER_KEY);
        relayer = vm.addr(RELAYER_KEY);

        tokenA = new MockERC20();
        tokenB = new MockERC20();
        target = new CallTarget();

        fund = new SimpleFund(admin, operator, passwordSigner);

        tokenA.mint(address(this), 1_000_000 ether);
        tokenB.mint(address(this), 1_000_000 ether);

        tokenA.mint(address(fund), 1_000 ether);
        tokenB.mint(address(fund), 500 ether);

        vm.deal(address(fund), 10 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    function testConstructor_ZeroAdmin_Reverts() public {
        vm.expectRevert("Zero admin");
        new SimpleFund(address(0), operator, passwordSigner);
    }

    function testConstructor_ZeroOperator_Reverts() public {
        vm.expectRevert("Zero operator");
        new SimpleFund(admin, address(0), passwordSigner);
    }

    function testConstructor_ZeroPasswordSigner_Reverts() public {
        vm.expectRevert("Zero passwordSigner");
        new SimpleFund(admin, operator, address(0));
    }

    function testConstructor_InitialState() public view {
        assertEq(fund.admin(), admin);
        assertEq(fund.operator(), operator);
        assertEq(fund.passwordSigner(), passwordSigner);
        assertEq(fund.nonce(), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  DEPOSIT
    // ═══════════════════════════════════════════════════════════════════════

    function testDeposit_AnyoneCanDeposit() public {
        uint256 amount = 50 ether;
        tokenA.approve(address(fund), amount);

        fund.deposit(address(tokenA), amount);

        assertEq(tokenA.balanceOf(address(fund)), 1_000 ether + amount);
    }

    function testDeposit_SupportsMultipleTokens() public {
        tokenA.approve(address(fund), 10 ether);
        tokenB.approve(address(fund), 20 ether);

        fund.deposit(address(tokenA), 10 ether);
        fund.deposit(address(tokenB), 20 ether);

        assertEq(tokenA.balanceOf(address(fund)), 1_010 ether);
        assertEq(tokenB.balanceOf(address(fund)), 520 ether);
    }

    function testDeposit_ZeroToken_Reverts() public {
        vm.expectRevert("Zero token");
        fund.deposit(address(0), 1 ether);
    }

    function testDeposit_ZeroAmount_Reverts() public {
        vm.expectRevert("Deposit amount must be greater than zero");
        fund.deposit(address(tokenA), 0);
    }

    function testDeposit_InsufficientAllowance_Reverts() public {
        vm.expectRevert("allowance");
        fund.deposit(address(tokenA), 1 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  WITHDRAW — DIRECT
    // ═══════════════════════════════════════════════════════════════════════

    function testWithdraw_Direct_Valid() public {
        bytes32 hash = _withdrawHash(address(tokenA), 100 ether, admin);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        uint256 before = tokenA.balanceOf(admin);
        vm.prank(admin);
        fund.withdraw(address(tokenA), 100 ether, admin, psig);

        assertEq(tokenA.balanceOf(admin), before + 100 ether);
        assertEq(tokenA.balanceOf(address(fund)), 900 ether);
        assertEq(fund.nonce(), 1);
    }

    function testWithdraw_Direct_NotAdmin_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 10 ether, attacker);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(attacker);
        vm.expectRevert("Not admin");
        fund.withdraw(address(tokenA), 10 ether, attacker, psig);
    }

    function testWithdraw_Direct_WrongPassword_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 10 ether, admin);
        bytes memory psig = _sign(ATTACKER_KEY, hash);

        vm.prank(admin);
        vm.expectRevert("Invalid password sig");
        fund.withdraw(address(tokenA), 10 ether, admin, psig);
    }

    function testWithdraw_Direct_ZeroToken_Reverts() public {
        bytes32 hash = _withdrawHash(address(0), 10 ether, admin);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(admin);
        vm.expectRevert("Zero token");
        fund.withdraw(address(0), 10 ether, admin, psig);
    }

    function testWithdraw_Direct_ZeroAmount_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 0, admin);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(admin);
        vm.expectRevert("Withdraw amount must be greater than zero");
        fund.withdraw(address(tokenA), 0, admin, psig);
    }

    function testWithdraw_Direct_ZeroRecipient_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 1 ether, address(0));
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(admin);
        vm.expectRevert("Invalid recipient");
        fund.withdraw(address(tokenA), 1 ether, address(0), psig);
    }

    function testWithdraw_Direct_InsufficientBalance_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 2_000 ether, admin);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(admin);
        vm.expectRevert("Insufficient token balance");
        fund.withdraw(address(tokenA), 2_000 ether, admin, psig);
    }

    function testWithdraw_Direct_ReplayAttack_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 100 ether, admin);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(admin);
        fund.withdraw(address(tokenA), 100 ether, admin, psig);

        vm.prank(admin);
        vm.expectRevert("Invalid password sig");
        fund.withdraw(address(tokenA), 100 ether, admin, psig);
    }

    function testWithdraw_Direct_WrongNonceInSig_Reverts() public {
        bytes32 hash = keccak256(abi.encode(
            keccak256("withdraw"),
            fund.nonce() + 1,
            address(fund),
            block.chainid,
            address(tokenA),
            uint256(10 ether),
            admin
        ));
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(admin);
        vm.expectRevert("Invalid password sig");
        fund.withdraw(address(tokenA), 10 ether, admin, psig);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  WITHDRAW — RELAY
    // ═══════════════════════════════════════════════════════════════════════

    function testWithdraw_Relay_Valid() public {
        bytes32 hash = _withdrawHash(address(tokenB), 100 ether, admin);
        bytes memory asig = _sign(ADMIN_KEY, hash);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(relayer);
        fund.withdrawRelay(address(tokenB), 100 ether, admin, asig, psig);

        assertEq(tokenB.balanceOf(admin), 100 ether);
        assertEq(fund.nonce(), 1);
    }

    function testWithdraw_Relay_AnyoneCanRelay() public {
        bytes32 hash = _withdrawHash(address(tokenA), 5 ether, admin);
        bytes memory asig = _sign(ADMIN_KEY, hash);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        fund.withdrawRelay(address(tokenA), 5 ether, admin, asig, psig);

        assertEq(tokenA.balanceOf(admin), 5 ether);
    }

    function testWithdraw_Relay_WrongAdminSig_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 5 ether, admin);
        bytes memory asig = _sign(ATTACKER_KEY, hash);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(relayer);
        vm.expectRevert("Invalid admin sig");
        fund.withdrawRelay(address(tokenA), 5 ether, admin, asig, psig);
    }

    function testWithdraw_Relay_WrongPasswordSig_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 5 ether, admin);
        bytes memory asig = _sign(ADMIN_KEY, hash);
        bytes memory psig = _sign(ATTACKER_KEY, hash);

        vm.prank(relayer);
        vm.expectRevert("Invalid password sig");
        fund.withdrawRelay(address(tokenA), 5 ether, admin, asig, psig);
    }

    function testWithdraw_Relay_ReplayAttack_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 5 ether, admin);
        bytes memory asig = _sign(ADMIN_KEY, hash);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(relayer);
        fund.withdrawRelay(address(tokenA), 5 ether, admin, asig, psig);

        vm.prank(relayer);
        vm.expectRevert("Invalid admin sig");
        fund.withdrawRelay(address(tokenA), 5 ether, admin, asig, psig);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  EXECUTE — OPERATOR + PASSWORD SIG
    // ═══════════════════════════════════════════════════════════════════════

    function testExecute_Valid_SingleCall() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.increment, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        fund.execute(targets, values, calldatas, psig);

        assertEq(target.counter(), 1);
        assertEq(fund.nonce(), 1);
    }

    function testExecute_Valid_BatchCalls() public {
        address[] memory targets = _arr2(address(target), address(target));
        uint256[] memory values = _vals2(0, 0);
        bytes[] memory calldatas = _data2(
            abi.encodeCall(CallTarget.increment, ()),
            abi.encodeCall(CallTarget.setCounter, (10))
        );
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        fund.execute(targets, values, calldatas, psig);

        assertEq(target.counter(), 10);
    }

    function testExecute_WithNativeValue_Success() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(2 ether);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.receiveValue, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        fund.execute(targets, values, calldatas, psig);

        assertEq(target.lastValue(), 2 ether);
        assertEq(address(target).balance, 2 ether);
    }

    function testExecute_WithFallbackCall_Success() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(1 ether);
        bytes[] memory calldatas = _data1(hex"1234");
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        fund.execute(targets, values, calldatas, psig);

        assertEq(target.fallbackCalls(), 1);
        assertEq(target.lastValue(), 1 ether);
    }

    function testExecute_OnlyOperator_Reverts() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.increment, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(attacker);
        vm.expectRevert("Not operator");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_WrongPasswordSig_Reverts() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.increment, ())); 
        bytes memory psig = _sign(ATTACKER_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        vm.expectRevert("Invalid password sig");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_LengthMismatch_TargetsValues_Reverts() public {
        address[] memory targets = _arr2(address(target), address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data2(
            abi.encodeCall(CallTarget.increment, ()),
            abi.encodeCall(CallTarget.increment, ())
        );
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(_arr2(address(target), address(target)), _vals2(0, 0), calldatas));

        vm.prank(operator);
        vm.expectRevert("Input length mismatch");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_LengthMismatch_TargetsCalldatas_Reverts() public {
        address[] memory targets = _arr2(address(target), address(target));
        uint256[] memory values = _vals2(0, 0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.increment, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, _data2(abi.encodeCall(CallTarget.increment, ()), abi.encodeCall(CallTarget.increment, ()) )));

        vm.prank(operator);
        vm.expectRevert("Input length mismatch");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_EmptyBatch_Reverts() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        vm.expectRevert("Empty execute batch");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_ZeroTarget_Reverts() public {
        address[] memory targets = _arr1(address(0));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(hex"");
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        vm.expectRevert("Zero target");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_InsufficientNativeBalance_Reverts() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(100 ether);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.receiveValue, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        vm.expectRevert("Insufficient native balance");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_TotalValueOverflow_Reverts() public {
        address[] memory targets = _arr2(address(target), address(target));
        uint256[] memory values = _vals2(type(uint256).max, 1);
        bytes[] memory calldatas = _data2(hex"", hex"");
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_CallRevertsWithReason_Bubbles() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.revertWithReason, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        vm.expectRevert("CallTarget: execution failed");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_CallRevertsWithoutReason_UsesDefaultMessage() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.revertWithoutReason, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        vm.expectRevert("Execute call failed");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_ReplayAttack_Reverts() public {
        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.increment, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.prank(operator);
        fund.execute(targets, values, calldatas, psig);

        vm.prank(operator);
        vm.expectRevert("Invalid password sig");
        fund.execute(targets, values, calldatas, psig);
    }

    function testExecute_CrossFunctionSigReuse_Reverts() public {
        bytes memory psig = _sign(PASSWORD_KEY, _withdrawHash(address(tokenA), 1 ether, admin));

        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.increment, ())); 

        vm.prank(operator);
        vm.expectRevert("Invalid password sig");
        fund.execute(targets, values, calldatas, psig);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  ADMIN ACTIONS (DIRECT + RELAY)
    // ═══════════════════════════════════════════════════════════════════════

    function testSetOperator_Direct_Valid() public {
        address newOperator = makeAddr("newOperator");
        bytes32 hash = _setOperatorHash(newOperator);

        vm.prank(admin);
        fund.setOperator(newOperator, _sign(PASSWORD_KEY, hash));

        assertEq(fund.operator(), newOperator);
    }

    function testSetOperator_Direct_ZeroAddress_Reverts() public {
        bytes32 hash = _setOperatorHash(address(0));

        vm.prank(admin);
        vm.expectRevert("Invalid operator address");
        fund.setOperator(address(0), _sign(PASSWORD_KEY, hash));
    }

    function testSetOperator_Direct_WrongPassword_Reverts() public {
        address newOperator = makeAddr("newOperator");
        bytes32 hash = _setOperatorHash(newOperator);

        vm.prank(admin);
        vm.expectRevert("Invalid password sig");
        fund.setOperator(newOperator, _sign(ATTACKER_KEY, hash));
    }

    function testSetOperator_Relay_Valid() public {
        address newOperator = makeAddr("newOperator");
        bytes32 hash = _setOperatorHash(newOperator);

        vm.prank(relayer);
        fund.setOperatorRelay(newOperator, _sign(ADMIN_KEY, hash), _sign(PASSWORD_KEY, hash));

        assertEq(fund.operator(), newOperator);
    }

    function testSetOperator_Relay_WrongAdmin_Reverts() public {
        address newOperator = makeAddr("newOperator");
        bytes32 hash = _setOperatorHash(newOperator);

        vm.prank(relayer);
        vm.expectRevert("Invalid admin sig");
        fund.setOperatorRelay(newOperator, _sign(ATTACKER_KEY, hash), _sign(PASSWORD_KEY, hash));
    }

    function testSetOperator_Relay_WrongPassword_Reverts() public {
        address newOperator = makeAddr("newOperator");
        bytes32 hash = _setOperatorHash(newOperator);

        vm.prank(relayer);
        vm.expectRevert("Invalid password sig");
        fund.setOperatorRelay(newOperator, _sign(ADMIN_KEY, hash), _sign(ATTACKER_KEY, hash));
    }

    function testSetOperator_Relay_ZeroAddress_Reverts() public {
        bytes32 hash = _setOperatorHash(address(0));

        vm.prank(relayer);
        vm.expectRevert("Invalid operator address");
        fund.setOperatorRelay(address(0), _sign(ADMIN_KEY, hash), _sign(PASSWORD_KEY, hash));
    }

    function testSetPasswordSigner_Direct_ValidAndOldSignerInvalid() public {
        address newSigner = vm.addr(NEW_PASSWORD_KEY);
        bytes32 hash = _setPasswordSignerHash(newSigner);

        vm.prank(admin);
        fund.setPasswordSigner(newSigner, _sign(PASSWORD_KEY, hash));
        assertEq(fund.passwordSigner(), newSigner);

        bytes32 whash = _withdrawHash(address(tokenA), 1 ether, admin);

        vm.prank(admin);
        vm.expectRevert("Invalid password sig");
        fund.withdraw(address(tokenA), 1 ether, admin, _sign(PASSWORD_KEY, whash));

        vm.prank(admin);
        fund.withdraw(address(tokenA), 1 ether, admin, _sign(NEW_PASSWORD_KEY, whash));
        assertEq(tokenA.balanceOf(admin), 1 ether);
    }

    function testSetPasswordSigner_Direct_ZeroAddress_Reverts() public {
        bytes32 hash = _setPasswordSignerHash(address(0));

        vm.prank(admin);
        vm.expectRevert("Zero address");
        fund.setPasswordSigner(address(0), _sign(PASSWORD_KEY, hash));
    }

    function testSetPasswordSigner_Relay_Valid() public {
        address newSigner = vm.addr(NEW_PASSWORD_KEY);
        bytes32 hash = _setPasswordSignerHash(newSigner);

        vm.prank(relayer);
        fund.setPasswordSignerRelay(newSigner, _sign(ADMIN_KEY, hash), _sign(PASSWORD_KEY, hash));

        assertEq(fund.passwordSigner(), newSigner);
    }

    function testSetPasswordSigner_Relay_WrongPassword_Reverts() public {
        address newSigner = vm.addr(NEW_PASSWORD_KEY);
        bytes32 hash = _setPasswordSignerHash(newSigner);

        vm.prank(relayer);
        vm.expectRevert("Invalid password sig");
        fund.setPasswordSignerRelay(newSigner, _sign(ADMIN_KEY, hash), _sign(ATTACKER_KEY, hash));
    }

    function testSetPasswordSigner_Relay_ZeroAddress_Reverts() public {
        bytes32 hash = _setPasswordSignerHash(address(0));

        vm.prank(relayer);
        vm.expectRevert("Zero address");
        fund.setPasswordSignerRelay(address(0), _sign(ADMIN_KEY, hash), _sign(PASSWORD_KEY, hash));
    }

    function testSetAdmin_Direct_ValidAndOldAdminLosesAccess() public {
        address newAdmin = vm.addr(NEW_ADMIN_KEY);
        bytes32 hash = _setAdminHash(newAdmin);

        vm.prank(admin);
        fund.setAdmin(newAdmin, _sign(PASSWORD_KEY, hash));
        assertEq(fund.admin(), newAdmin);

        address anotherOperator = makeAddr("anotherOperator");
        bytes32 opHash = _setOperatorHash(anotherOperator);

        vm.prank(admin);
        vm.expectRevert("Not admin");
        fund.setOperator(anotherOperator, _sign(PASSWORD_KEY, opHash));
    }

    function testSetAdmin_Direct_ZeroAddress_Reverts() public {
        bytes32 hash = _setAdminHash(address(0));

        vm.prank(admin);
        vm.expectRevert("Zero address");
        fund.setAdmin(address(0), _sign(PASSWORD_KEY, hash));
    }

    function testSetAdmin_Direct_WrongPassword_Reverts() public {
        address newAdmin = vm.addr(NEW_ADMIN_KEY);
        bytes32 hash = _setAdminHash(newAdmin);

        vm.prank(admin);
        vm.expectRevert("Invalid password sig");
        fund.setAdmin(newAdmin, _sign(ATTACKER_KEY, hash));
    }

    function testSetAdmin_Relay_Valid() public {
        address newAdmin = vm.addr(NEW_ADMIN_KEY);
        bytes32 hash = _setAdminHash(newAdmin);

        vm.prank(relayer);
        fund.setAdminRelay(newAdmin, _sign(ADMIN_KEY, hash), _sign(PASSWORD_KEY, hash));
        assertEq(fund.admin(), newAdmin);
    }

    function testSetAdmin_Relay_WrongAdmin_Reverts() public {
        address newAdmin = vm.addr(NEW_ADMIN_KEY);
        bytes32 hash = _setAdminHash(newAdmin);

        vm.prank(relayer);
        vm.expectRevert("Invalid admin sig");
        fund.setAdminRelay(newAdmin, _sign(ATTACKER_KEY, hash), _sign(PASSWORD_KEY, hash));
    }

    function testSetAdmin_Relay_WrongPassword_Reverts() public {
        address newAdmin = vm.addr(NEW_ADMIN_KEY);
        bytes32 hash = _setAdminHash(newAdmin);

        vm.prank(relayer);
        vm.expectRevert("Invalid password sig");
        fund.setAdminRelay(newAdmin, _sign(ADMIN_KEY, hash), _sign(ATTACKER_KEY, hash));
    }

    function testSetAdmin_Relay_ZeroAddress_Reverts() public {
        bytes32 hash = _setAdminHash(address(0));

        vm.prank(relayer);
        vm.expectRevert("Zero address");
        fund.setAdminRelay(address(0), _sign(ADMIN_KEY, hash), _sign(PASSWORD_KEY, hash));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SIGNATURE BINDING + NONCE
    // ═══════════════════════════════════════════════════════════════════════

    function testSignatures_BoundToChainId() public {
        uint256 originalChainId = block.chainid;

        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.increment, ())); 
        bytes memory psig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));

        vm.chainId(originalChainId + 1);

        vm.prank(operator);
        vm.expectRevert("Invalid password sig");
        fund.execute(targets, values, calldatas, psig);

        vm.chainId(originalChainId);
    }

    function testSignatures_BoundToContractAddress() public {
        SimpleFund fund2 = new SimpleFund(admin, operator, passwordSigner);

        bytes32 hash = _withdrawHash(address(tokenA), 10 ether, admin);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(admin);
        vm.expectRevert("Invalid password sig");
        fund2.withdraw(address(tokenA), 10 ether, admin, psig);
    }

    function testSignatures_ParamTampering_Reverts() public {
        bytes32 hash = _withdrawHash(address(tokenA), 10 ether, admin);
        bytes memory psig = _sign(PASSWORD_KEY, hash);

        vm.prank(admin);
        vm.expectRevert("Invalid password sig");
        fund.withdraw(address(tokenA), 11 ether, admin, psig);
    }

    function testNonce_SharedAcrossProtectedFunctions() public {
        assertEq(fund.nonce(), 0);

        bytes32 withdrawHash = _withdrawHash(address(tokenA), 1 ether, admin);
        bytes memory withdrawSig = _sign(PASSWORD_KEY, withdrawHash);
        vm.prank(admin);
        fund.withdraw(address(tokenA), 1 ether, admin, withdrawSig);
        assertEq(fund.nonce(), 1);

        address[] memory targets = _arr1(address(target));
        uint256[] memory values = _vals1(0);
        bytes[] memory calldatas = _data1(abi.encodeCall(CallTarget.increment, ())); 
        bytes memory executeSig = _sign(PASSWORD_KEY, _executeHash(targets, values, calldatas));
        vm.prank(operator);
        fund.execute(targets, values, calldatas, executeSig);
        assertEq(fund.nonce(), 2);

        address newOperator = makeAddr("newOp2");
        bytes memory setOperatorSig = _sign(PASSWORD_KEY, _setOperatorHash(newOperator));
        vm.prank(admin);
        fund.setOperator(newOperator, setOperatorSig);
        assertEq(fund.nonce(), 3);
    }

    function testReceive_AllowsNativeFunding() public {
        address donor = makeAddr("donor");
        vm.deal(donor, 1 ether);

        vm.prank(donor);
        (bool ok,) = address(fund).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(fund).balance, 11 ether);
    }
}
