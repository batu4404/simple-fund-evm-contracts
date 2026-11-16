// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract SimpleFund {
	using SafeERC20 for IERC20;
	using Address for address;

	address public admin;
	address public operator;
	address public passwordSigner;
	address public lighterDecoder;

	uint256 public nonce;
	bytes32 public manageRoot;

	bytes32 private constant WITHDRAW_ACTION             = keccak256("withdraw");
	bytes32 private constant EXECUTE_BY_ADMIN_ACTION     = keccak256("executeByAdmin");
	bytes32 private constant SET_OPERATOR_ACTION         = keccak256("setOperator");
	bytes32 private constant SET_PASSWORD_SIGNER_ACTION  = keccak256("setPasswordSigner");
	bytes32 private constant SET_ADMIN_ACTION            = keccak256("setAdmin");
	bytes32 private constant SET_MANAGE_ROOT_ACTION      = keccak256("setManageRoot");
	bytes32 private constant SET_LIGHTER_DECODER_ACTION  = keccak256("setLighterDecoder");

	constructor(
		address _admin,
		address _operator,
		address _passwordSigner
	) {
		require(_admin != address(0), "Zero admin");
		require(_operator != address(0), "Zero operator");
		require(_passwordSigner != address(0), "Zero passwordSigner");

		admin = _admin;
		operator = _operator;
		passwordSigner = _passwordSigner;
	}

	modifier onlyAdmin() {
		_checkAdmin();
		_;
	}

	modifier onlyOperator() {
		_checkOperator();
		_;
	}

	function _checkAdmin() internal view {
		require(msg.sender == admin, "Not admin");
	}

	function _checkOperator() internal view {
		require(msg.sender == operator, "Not operator");
	}

	function _verifyPasswordOnly(bytes32 hash, bytes calldata passwordSig) internal {
		bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(hash);
		require(ECDSA.recover(ethHash, passwordSig) == passwordSigner, "Invalid password sig");
		nonce++;
	}

	function _verify2Fa(bytes32 hash, bytes calldata adminSig, bytes calldata passwordSig) internal {
		bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(hash);
		require(ECDSA.recover(ethHash, adminSig) == admin, "Invalid admin sig");
		require(ECDSA.recover(ethHash, passwordSig) == passwordSigner, "Invalid password sig");
		nonce++;
	}

	function deposit(address token, uint256 amount) external {
		require(token != address(0), "Zero token");
		require(amount > 0, "Deposit amount must be greater than zero");

		IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
	}

	function withdraw(
		address token,
		uint256 amount,
		address recipient,
		bytes calldata passwordSig
	) external onlyAdmin {
		bytes32 hash = keccak256(abi.encode(
			WITHDRAW_ACTION,
			nonce,
			address(this),
			block.chainid,
			token,
			amount,
			recipient
		));
		_verifyPasswordOnly(hash, passwordSig);

		_executeWithdraw(token, amount, recipient);
	}

	function withdrawRelay(
		address token,
		uint256 amount,
		address recipient,
		bytes calldata adminSig,
		bytes calldata passwordSig
	) external {
		bytes32 hash = keccak256(abi.encode(
			WITHDRAW_ACTION,
			nonce,
			address(this),
			block.chainid,
			token,
			amount,
			recipient
		));
		_verify2Fa(hash, adminSig, passwordSig);

		_executeWithdraw(token, amount, recipient);
	}

	function executeByAdmin(
		address[] calldata targets,
		uint256[] calldata values,
		bytes[] calldata calldatas,
		bytes calldata passwordSig
	) external payable onlyAdmin {
		_validateExecuteArrays(targets, values, calldatas);

		bytes32 hash = keccak256(abi.encode(
			EXECUTE_BY_ADMIN_ACTION,
			nonce,
			address(this),
			block.chainid,
			targets,
			values,
			calldatas
		));
		_verifyPasswordOnly(hash, passwordSig);

		_executeCalls(targets, values, calldatas, false);
	}

	function execute(
		bytes32[][] calldata proofs,
		address[] calldata decoders,
		address[] calldata targets,
		uint256[] calldata values,
		bytes[] calldata calldatas
	) external payable onlyOperator {
		_validateExecuteArrays(targets, values, calldatas);
		require(targets.length == proofs.length, "Input length mismatch");
		require(targets.length == decoders.length, "Input length mismatch");

		bytes32 currentRoot = manageRoot;
		require(currentRoot != bytes32(0), "Manage root not set");

		uint256 totalValue = 0;
		uint256 len = targets.length;
		for (uint256 i = 0; i < len; i++) {
			require(targets[i] != address(0), "Zero target");
			require(targets[i] != address(this), "Self call");
			totalValue += values[i];
			_verifyCall(currentRoot, proofs[i], decoders[i], targets[i], values[i], calldatas[i]);
		}

		require(address(this).balance >= totalValue, "Insufficient native balance");

		for (uint256 i = 0; i < len; i++) {
			(bool success, bytes memory returnData) = targets[i].call{value: values[i]}(calldatas[i]);
			if (!success) _revertWithReason(returnData);
		}
	}

	function consumeDecoderPassword(bytes32 hash, bytes calldata passwordSig) external {
		require(msg.sender == lighterDecoder, "Not lighter decoder");
		_verifyPasswordOnly(hash, passwordSig);
	}

	function setManageRoot(bytes32 _manageRoot, bytes calldata passwordSig) external onlyAdmin {
		bytes32 hash = keccak256(abi.encode(
			SET_MANAGE_ROOT_ACTION,
			nonce,
			address(this),
			block.chainid,
			_manageRoot
		));
		_verifyPasswordOnly(hash, passwordSig);

		manageRoot = _manageRoot;
	}

	function setManageRootRelay(
		bytes32 _manageRoot,
		bytes calldata adminSig,
		bytes calldata passwordSig
	) external {
		bytes32 hash = keccak256(abi.encode(
			SET_MANAGE_ROOT_ACTION,
			nonce,
			address(this),
			block.chainid,
			_manageRoot
		));
		_verify2Fa(hash, adminSig, passwordSig);

		manageRoot = _manageRoot;
	}

	function setLighterDecoder(address _lighterDecoder, bytes calldata passwordSig) external onlyAdmin {
		require(_lighterDecoder != address(0), "Zero address");

		bytes32 hash = keccak256(abi.encode(
			SET_LIGHTER_DECODER_ACTION,
			nonce,
			address(this),
			block.chainid,
			_lighterDecoder
		));
		_verifyPasswordOnly(hash, passwordSig);

		lighterDecoder = _lighterDecoder;
	}

	function setLighterDecoderRelay(
		address _lighterDecoder,
		bytes calldata adminSig,
		bytes calldata passwordSig
	) external {
		require(_lighterDecoder != address(0), "Zero address");

		bytes32 hash = keccak256(abi.encode(
			SET_LIGHTER_DECODER_ACTION,
			nonce,
			address(this),
			block.chainid,
			_lighterDecoder
		));
		_verify2Fa(hash, adminSig, passwordSig);

		lighterDecoder = _lighterDecoder;
	}

	function setOperator(address _operator, bytes calldata passwordSig) external onlyAdmin {
		require(_operator != address(0), "Invalid operator address");

		bytes32 hash = keccak256(abi.encode(
			SET_OPERATOR_ACTION,
			nonce,
			address(this),
			block.chainid,
			_operator
		));
		_verifyPasswordOnly(hash, passwordSig);

		operator = _operator;
	}

	function setOperatorRelay(
		address _operator,
		bytes calldata adminSig,
		bytes calldata passwordSig
	) external {
		require(_operator != address(0), "Invalid operator address");

		bytes32 hash = keccak256(abi.encode(
			SET_OPERATOR_ACTION,
			nonce,
			address(this),
			block.chainid,
			_operator
		));
		_verify2Fa(hash, adminSig, passwordSig);

		operator = _operator;
	}

	function setPasswordSigner(address _newPasswordSigner, bytes calldata passwordSig) external onlyAdmin {
		require(_newPasswordSigner != address(0), "Zero address");

		bytes32 hash = keccak256(abi.encode(
			SET_PASSWORD_SIGNER_ACTION,
			nonce,
			address(this),
			block.chainid,
			_newPasswordSigner
		));
		_verifyPasswordOnly(hash, passwordSig);

		passwordSigner = _newPasswordSigner;
	}

	function setPasswordSignerRelay(
		address _newPasswordSigner,
		bytes calldata adminSig,
		bytes calldata passwordSig
	) external {
		require(_newPasswordSigner != address(0), "Zero address");

		bytes32 hash = keccak256(abi.encode(
			SET_PASSWORD_SIGNER_ACTION,
			nonce,
			address(this),
			block.chainid,
			_newPasswordSigner
		));
		_verify2Fa(hash, adminSig, passwordSig);

		passwordSigner = _newPasswordSigner;
	}

	function setAdmin(address _newAdmin, bytes calldata passwordSig) external onlyAdmin {
		require(_newAdmin != address(0), "Zero address");

		bytes32 hash = keccak256(abi.encode(
			SET_ADMIN_ACTION,
			nonce,
			address(this),
			block.chainid,
			_newAdmin
		));
		_verifyPasswordOnly(hash, passwordSig);

		admin = _newAdmin;
	}

	function setAdminRelay(
		address _newAdmin,
		bytes calldata adminSig,
		bytes calldata passwordSig
	) external {
		require(_newAdmin != address(0), "Zero address");

		bytes32 hash = keccak256(abi.encode(
			SET_ADMIN_ACTION,
			nonce,
			address(this),
			block.chainid,
			_newAdmin
		));
		_verify2Fa(hash, adminSig, passwordSig);

		admin = _newAdmin;
	}

	function _validateExecuteArrays(
		address[] calldata targets,
		uint256[] calldata values,
		bytes[] calldata calldatas
	) internal pure {
		require(targets.length == values.length, "Input length mismatch");
		require(targets.length == calldatas.length, "Input length mismatch");
		require(targets.length > 0, "Empty execute batch");
	}

	function _executeCalls(
		address[] calldata targets,
		uint256[] calldata values,
		bytes[] calldata calldatas,
		bool rejectSelf
	) internal {
		uint256 totalValue = 0;
		uint256 len = targets.length;
		for (uint256 i = 0; i < len; i++) {
			require(targets[i] != address(0), "Zero target");
			if (rejectSelf) require(targets[i] != address(this), "Self call");
			totalValue += values[i];
		}

		require(address(this).balance >= totalValue, "Insufficient native balance");

		for (uint256 i = 0; i < len; i++) {
			(bool success, bytes memory returnData) = targets[i].call{value: values[i]}(calldatas[i]);
			if (!success) _revertWithReason(returnData);
		}
	}

	function _verifyCall(
		bytes32 currentRoot,
		bytes32[] calldata proof,
		address decoder,
		address target,
		uint256 value,
		bytes calldata targetData
	) internal view {
		bytes memory decoderReturn = decoder.functionStaticCall(targetData);
		bytes memory packedArgumentAddresses = decoderReturn.length == 0
			? bytes("")
			: abi.decode(decoderReturn, (bytes));

		bytes32 leaf = keccak256(
			abi.encodePacked(
				decoder,
				target,
				value > 0,
				bytes4(targetData),
				packedArgumentAddresses
			)
		);

		require(MerkleProof.verify(proof, currentRoot, leaf), "Invalid manage proof");
	}

	function _executeWithdraw(address token, uint256 amount, address recipient) internal {
		require(token != address(0), "Zero token");
		require(amount > 0, "Withdraw amount must be greater than zero");
		require(recipient != address(0), "Invalid recipient");

		IERC20 erc20 = IERC20(token);
		require(erc20.balanceOf(address(this)) >= amount, "Insufficient token balance");
		erc20.safeTransfer(recipient, amount);
	}

	function _revertWithReason(bytes memory returnData) internal pure {
		if (returnData.length == 0) revert("Execute call failed");

		assembly {
			revert(add(returnData, 32), mload(returnData))
		}
	}

	receive() external payable {}
}
