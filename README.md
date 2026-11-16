# evm-simple-yield (contract)

Smart contract workspace for:

- `SimpleFund`: general-purpose custody and execution contract with nonce-based 2FA.

## SimpleFund

Source: `src/SimpleFund.sol`

### Core features

- Multi-token support. The contract is not bound to a single ERC20.
- Role model:
	- `admin`: controls withdrawals, role updates, Merkle-root updates, and unrestricted `executeByAdmin`.
	- `operator`: executes batched calls that prove inclusion in `manageRoot`.
	- `passwordSigner`: second factor signer.
- Operator `execute` is Merkle-gated. Each call is verified against `manageRoot` using a decoder that extracts address arguments. It does not take a password signature and does not consume `nonce`.
- `executeByAdmin` skips the Merkle root and still requires a password signature.
- Global replay protection with `nonce` on password-signed actions.
- EIP-191 signature verification for protected admin actions.
- Native ETH support via `receive()` for value-forwarding in `execute`.

### Function list

- Public funds flow:
	- `deposit(address token, uint256 amount)`
	- `withdraw(address token, uint256 amount, address recipient, bytes passwordSig)`
	- `withdrawRelay(address token, uint256 amount, address recipient, bytes adminSig, bytes passwordSig)`
- Arbitrary execution:
	- `execute(bytes32[][] proofs, address[] decoders, address[] targets, uint256[] values, bytes[] calldatas)`
	- `executeByAdmin(address[] targets, uint256[] values, bytes[] calldatas, bytes passwordSig)`
- Admin and configuration:
	- `setManageRoot(bytes32 root, bytes passwordSig)`
	- `setManageRootRelay(bytes32 root, bytes adminSig, bytes passwordSig)`
	- `setLighterDecoder(address decoder, bytes passwordSig)`
	- `setLighterDecoderRelay(address decoder, bytes adminSig, bytes passwordSig)`
	- `setOperator(address newOperator, bytes passwordSig)`
	- `setOperatorRelay(address newOperator, bytes adminSig, bytes passwordSig)`
	- `setPasswordSigner(address newPasswordSigner, bytes passwordSig)`
	- `setPasswordSignerRelay(address newPasswordSigner, bytes adminSig, bytes passwordSig)`
	- `setAdmin(address newAdmin, bytes passwordSig)`
	- `setAdminRelay(address newAdmin, bytes adminSig, bytes passwordSig)`

### Signature schema

All signed payloads are built from:

1. Action discriminator.
2. Current `nonce`.
3. `address(this)`.
4. `block.chainid`.
5. Function parameters.

Actions:

- `keccak256("withdraw")`
- `keccak256("executeByAdmin")`
- `keccak256("setManageRoot")`
- `keccak256("setLighterDecoder")`
- `keccak256("setOperator")`
- `keccak256("setPasswordSigner")`
- `keccak256("setAdmin")`

Use EIP-191 signed message hash before signing:

```text
ethHash = toEthSignedMessageHash(rawHash)
```

## Deployment

Deploy script: `script/DeploySimpleFund.s.sol`

### Required env vars

- `DEPLOYER_PRIVATE_KEY`
- `ADMIN`
- `OPERATOR`
- `PASSWORD_SIGNER`
- `SALT`
- `RPC_URL`
- `CHAIN_ID`

### Make targets

```bash
make deploy-fund
make merkle-tree
```

### Merkle tree generation

Operator `execute` is gated by `manageRoot`. Generate the Aave / Nest / Lighter allowlist with `script/CreateMerkleRoot.s.sol` (no broadcast):

```bash
make merkle-tree
```

Required env vars (in addition to `RPC_URL` and `CHAIN_ID`):

- `FUND`
- `AAVE_DECODER`
- `NEST_DECODER`
- `LIGHTER_DECODER`

Output: `leafs/SimpleFundLeaves_<chainid>.json` (root, leaf metadata, and tree layers). Ethereum protocol addresses (USDC, Aave pool, Nest, Lighter) are hardcoded in the script. Fork tests call `generateMerkleTree(config)` in-process against freshly deployed decoders instead of reading that file.

## Tests

### Unit tests

```bash
forge test --match-contract SimpleFundTest -vv
```

### Fork tests (Ethereum)

```bash
forge test --match-contract SimpleFundEthereumTest -vv --fork-url https://ethereum-rpc.publicnode.com
```

### Coverage

```bash
forge coverage --match-contract SimpleFund --report summary
```

Current `SimpleFund` coverage target status:

- Lines: 100%
- Statements: 100%
- Branches: 100%
- Functions: 100%

## Coding agent integration docs

- Concise style: `simple-fund-llms.md` (includes decoder leaves, `executeByAdmin` batches, and protocol amount reads)
- Full style: `simple-fund-llms-full.md`

