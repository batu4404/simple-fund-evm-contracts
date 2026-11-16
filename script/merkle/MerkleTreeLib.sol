// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library MerkleTreeLib {
	struct ManageLeaf {
		address decoderAndSanitizer;
		address target;
		bool valueNonZero;
		bytes4 selector;
		address[] argumentAddresses;
		string signature;
		string description;
	}

	function selectorOf(ManageLeaf memory leaf) internal pure returns (bytes4) {
		if (bytes(leaf.signature).length > 0) {
			return bytes4(keccak256(bytes(leaf.signature)));
		}
		return leaf.selector;
	}

	function hashLeaf(ManageLeaf memory leaf) internal pure returns (bytes32) {
		bytes memory packed = abi.encodePacked(
			leaf.decoderAndSanitizer,
			leaf.target,
			leaf.valueNonZero,
			selectorOf(leaf)
		);
		uint256 len = leaf.argumentAddresses.length;
		for (uint256 i; i < len; ++i) {
			packed = abi.encodePacked(packed, leaf.argumentAddresses[i]);
		}
		return keccak256(packed);
	}

	function generateTree(ManageLeaf[] memory leaves) internal pure returns (bytes32[][] memory tree) {
		uint256 n = leaves.length;
		require(n > 0, "Empty leaves");

		bytes32[] memory hashed = new bytes32[](n);
		for (uint256 i; i < n; ++i) {
			hashed[i] = hashLeaf(leaves[i]);
		}

		bytes32[][] memory layers = new bytes32[][](32);
		bytes32[] memory layer = hashed;
		if (layer.length > 1 && layer.length % 2 == 1) {
			layer = _pad(layer);
		}
		layers[0] = layer;
		uint256 height = 1;

		while (layer.length > 1) {
			uint256 nextLen = layer.length / 2;
			bytes32[] memory next = new bytes32[](nextLen);
			for (uint256 i; i < nextLen; ++i) {
				next[i] = _hashPair(layer[2 * i], layer[2 * i + 1]);
			}
			if (next.length > 1 && next.length % 2 == 1) {
				next = _pad(next);
			}
			layers[height] = next;
			layer = next;
			height++;
		}

		tree = new bytes32[][](height);
		for (uint256 i; i < height; ++i) {
			tree[i] = layers[i];
		}
	}

	function getProofs(
		ManageLeaf[] memory leaves,
		bytes32[][] memory tree
	) internal pure returns (bytes32[][] memory proofs) {
		proofs = new bytes32[][](leaves.length);
		uint256 height = tree.length - 1;
		for (uint256 i; i < leaves.length; ++i) {
			proofs[i] = _proofByDigest(hashLeaf(leaves[i]), height, tree);
		}
	}

	function getProofsUsingTree(
		ManageLeaf[] memory leaves,
		bytes32[][] memory tree
	) internal pure returns (bytes32[][] memory proofs) {
		return getProofs(leaves, tree);
	}

	function rootOf(bytes32[][] memory tree) internal pure returns (bytes32) {
		return tree[tree.length - 1][0];
	}

	function proofsAndRoot(
		ManageLeaf[] memory leaves
	) internal pure returns (bytes32[][] memory proofs, bytes32 root) {
		bytes32[][] memory tree = generateTree(leaves);
		proofs = getProofs(leaves, tree);
		root = rootOf(tree);
	}

	function leafFromCall(
		address decoderAndSanitizer,
		address target,
		uint256 value,
		bytes memory data,
		address[] memory argumentAddresses
	) internal pure returns (ManageLeaf memory leaf) {
		leaf.decoderAndSanitizer = decoderAndSanitizer;
		leaf.target = target;
		leaf.valueNonZero = value > 0;
		leaf.selector = bytes4(data);
		leaf.argumentAddresses = argumentAddresses;
	}

	function _proofByDigest(
		bytes32 leaf,
		uint256 height,
		bytes32[][] memory tree
	) private pure returns (bytes32[] memory proof) {
		uint256 idx;
		bool found;
		uint256 layer0Len = tree[0].length;
		for (uint256 j; j < layer0Len; ++j) {
			if (tree[0][j] == leaf) {
				idx = j;
				found = true;
				break;
			}
		}
		require(found, "Leaf not in tree");

		proof = new bytes32[](height);
		for (uint256 i; i < height; ++i) {
			uint256 sibling = idx % 2 == 0 ? idx + 1 : idx - 1;
			proof[i] = tree[i][sibling];
			idx = idx / 2;
		}
	}

	function _pad(bytes32[] memory layer) private pure returns (bytes32[] memory padded) {
		padded = new bytes32[](layer.length + 1);
		for (uint256 i; i < layer.length; ++i) {
			padded[i] = layer[i];
		}
		padded[layer.length] = layer[layer.length - 1];
	}

	function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
		return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
	}
}
