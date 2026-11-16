// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { MerkleTreeLib } from "./merkle/MerkleTreeLib.sol";

/// Writes leafs/SimpleFundLeaves_{chainid}.json. The operator backend reads only
/// the tree field and looks up proofs in those layers. It does not rebuild them.
contract CreateMerkleRoot is Script {
	address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
	address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
	address constant NEST_PREDICATE_PROXY = 0xfC0c4222B3A0c9B060C0B959DEc62442036b9035;
	address constant NEST_VAULT = 0xD258029cF5a177e3306E09Fbea63424543a505c0;
	address constant NEST_SHARE_TOKEN = 0x119Dd7dAFf816f29D7eE47596ae5E4bdC4299165;
	address constant ZK_LIGHTER = 0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7;

	struct Config {
		address fund;
		address aaveDecoder;
		address nestDecoder;
		address lighterDecoder;
	}

	function run() external {
		Config memory config = Config({
			fund: vm.envAddress("FUND"),
			aaveDecoder: vm.envAddress("AAVE_DECODER"),
			nestDecoder: vm.envAddress("NEST_DECODER"),
			lighterDecoder: vm.envAddress("LIGHTER_DECODER")
		});

		(MerkleTreeLib.ManageLeaf[] memory leaves, bytes32[][] memory tree) = generateMerkleTree(config);
		_writeJson(config, leaves, tree);
	}

	function generateMerkleTree(Config memory config)
		public
		pure
		returns (MerkleTreeLib.ManageLeaf[] memory leaves, bytes32[][] memory tree)
	{
		leaves = new MerkleTreeLib.ManageLeaf[](13);
		uint256 i;

		leaves[i++] = _makeLeaf(
			config.aaveDecoder,
			USDC,
			"approve(address,uint256)",
			_one(AAVE_POOL),
			"Approve USDC for Aave V3 Pool"
		);
		leaves[i++] = _makeLeaf(
			config.aaveDecoder,
			AAVE_POOL,
			"supply(address,uint256,address,uint16)",
			_two(USDC, config.fund),
			"Supply USDC to Aave V3 on behalf of the fund"
		);
		leaves[i++] = _makeLeaf(
			config.aaveDecoder,
			AAVE_POOL,
			"withdraw(address,uint256,address)",
			_two(USDC, config.fund),
			"Withdraw USDC from Aave V3 to the fund"
		);

		leaves[i++] = _makeLeaf(
			config.nestDecoder,
			USDC,
			"approve(address,uint256)",
			_one(NEST_PREDICATE_PROXY),
			"Approve USDC for Nest predicate proxy"
		);
		leaves[i++] = _makeLeaf(
			config.nestDecoder,
			NEST_PREDICATE_PROXY,
			"deposit(address,uint256,address,address,(string,uint256,address[],bytes[]))",
			_two(USDC, NEST_VAULT),
			"Deposit USDC into Nest vault via predicate proxy"
		);
		leaves[i++] = _makeLeaf(
			config.nestDecoder,
			NEST_SHARE_TOKEN,
			"approve(address,uint256)",
			_one(NEST_VAULT),
			"Approve Nest share token for Nest vault"
		);
		leaves[i++] = _makeLeaf(
			config.nestDecoder,
			NEST_VAULT,
			"requestRedeem(uint256,address,address)",
			_none(),
			"Request Nest redeem"
		);
		leaves[i++] = _makeLeaf(
			config.nestDecoder,
			NEST_VAULT,
			"redeem(uint256,address,address)",
			_none(),
			"Redeem Nest shares"
		);

		leaves[i++] = _makeLeaf(
			config.lighterDecoder,
			USDC,
			"approve(address,uint256)",
			_one(ZK_LIGHTER),
			"Approve USDC for Lighter"
		);
		leaves[i++] = _makeLeaf(
			config.lighterDecoder,
			ZK_LIGHTER,
			"deposit(address,uint16,uint8,uint256)",
			_none(),
			"Deposit USDC to Lighter"
		);
		leaves[i++] = _makeLeaf(
			config.lighterDecoder,
			ZK_LIGHTER,
			"withdraw(uint48,uint16,uint8,uint64)",
			_none(),
			"Withdraw from Lighter"
		);
		leaves[i++] = _makeLeaf(
			config.lighterDecoder,
			ZK_LIGHTER,
			"cancelAllOrders(uint48)",
			_none(),
			"Cancel all Lighter orders"
		);
		leaves[i++] = _makeLeaf(
			config.lighterDecoder,
			ZK_LIGHTER,
			"burnShares(uint48,uint48,uint64)",
			_none(),
			"Burn Lighter shares"
		);

		tree = MerkleTreeLib.generateTree(leaves);
	}

	function _makeLeaf(
		address decoder,
		address target,
		string memory signature,
		address[] memory argumentAddresses,
		string memory description
	) private pure returns (MerkleTreeLib.ManageLeaf memory leaf) {
		leaf.decoderAndSanitizer = decoder;
		leaf.target = target;
		leaf.valueNonZero = false;
		leaf.signature = signature;
		leaf.selector = bytes4(keccak256(bytes(signature)));
		leaf.argumentAddresses = argumentAddresses;
		leaf.description = description;
	}

	function _none() private pure returns (address[] memory a) {
		a = new address[](0);
	}

	function _one(address x) private pure returns (address[] memory a) {
		a = new address[](1);
		a[0] = x;
	}

	function _two(address x, address y) private pure returns (address[] memory a) {
		a = new address[](2);
		a[0] = x;
		a[1] = y;
	}

	function _writeJson(
		Config memory config,
		MerkleTreeLib.ManageLeaf[] memory leaves,
		bytes32[][] memory tree
	) private {
		string memory leafsJson = "[";
		for (uint256 i; i < leaves.length; ++i) {
			if (i > 0) leafsJson = string.concat(leafsJson, ",");
			leafsJson = string.concat(leafsJson, _leafJson(leaves[i]));
		}
		leafsJson = string.concat(leafsJson, "]");

		string memory json = string.concat(
			"{\n",
			'  "manageRoot": ',
			_b32(MerkleTreeLib.rootOf(tree)),
			",\n",
			'  "leafCount": ',
			vm.toString(leaves.length),
			",\n",
			'  "digestComposition": ["decoder", "target", "valueNonZero", "selector", "argumentAddresses"],\n',
			'  "fund": ',
			_addr(config.fund),
			",\n",
			'  "aaveDecoder": ',
			_addr(config.aaveDecoder),
			",\n",
			'  "nestDecoder": ',
			_addr(config.nestDecoder),
			",\n",
			'  "lighterDecoder": ',
			_addr(config.lighterDecoder),
			",\n",
			'  "leafs": ',
			leafsJson,
			",\n",
			'  "tree": ',
			_treeJson(tree),
			"\n}\n"
		);

		string memory dir = string.concat(vm.projectRoot(), "/leafs");
		vm.createDir(dir, true);
		string memory path = string.concat(
			dir,
			"/SimpleFundLeaves_",
			vm.toString(block.chainid),
			".json"
		);
		vm.writeFile(path, json);
		console.log("Wrote merkle tree to", path);
		console.logBytes32(MerkleTreeLib.rootOf(tree));
	}

	function _leafJson(MerkleTreeLib.ManageLeaf memory leaf) private pure returns (string memory) {
		return string.concat(
			"{",
			'"target":',
			_addr(leaf.target),
			",",
			'"decoder":',
			_addr(leaf.decoderAndSanitizer),
			",",
			'"valueNonZero":',
			leaf.valueNonZero ? "true" : "false",
			",",
			'"signature":',
			_quote(leaf.signature),
			",",
			'"selector":',
			_quote(_hex4(MerkleTreeLib.selectorOf(leaf))),
			",",
			'"argumentAddresses":',
			_addrArray(leaf.argumentAddresses),
			",",
			'"description":',
			_quote(leaf.description),
			",",
			'"leafDigest":',
			_b32(MerkleTreeLib.hashLeaf(leaf)),
			"}"
		);
	}

	function _treeJson(bytes32[][] memory tree) private pure returns (string memory out) {
		out = "[";
		for (uint256 i; i < tree.length; ++i) {
			if (i > 0) out = string.concat(out, ",");
			out = string.concat(out, "[");
			for (uint256 j; j < tree[i].length; ++j) {
				if (j > 0) out = string.concat(out, ",");
				out = string.concat(out, _b32(tree[i][j]));
			}
			out = string.concat(out, "]");
		}
		out = string.concat(out, "]");
	}

	function _addrArray(address[] memory addrs) private pure returns (string memory out) {
		out = "[";
		for (uint256 i; i < addrs.length; ++i) {
			if (i > 0) out = string.concat(out, ",");
			out = string.concat(out, _addr(addrs[i]));
		}
		out = string.concat(out, "]");
	}

	function _quote(string memory s) private pure returns (string memory) {
		return string.concat('"', s, '"');
	}

	function _addr(address a) private pure returns (string memory) {
		return _quote(vm.toString(a));
	}

	function _b32(bytes32 v) private pure returns (string memory) {
		return _quote(vm.toString(v));
	}

	function _hex4(bytes4 sel) private pure returns (string memory) {
		bytes16 hexChars = "0123456789abcdef";
		bytes memory s = new bytes(10);
		s[0] = "0";
		s[1] = "x";
		uint32 v = uint32(sel);
		for (uint256 i; i < 8; ++i) {
			s[9 - i] = hexChars[v & 0xf];
			v >>= 4;
		}
		return string(s);
	}
}
