# evm-simple-yield (contract)

Smart contract workspace for:

- `SimpleFund`: general-purpose custody and execution contract with nonce-based 2FA.

## SimpleFund

Source: `src/SimpleFund.sol`

### Core features

- Multi-token support. The contract is not bound to a single ERC20.
- Role model:
	- `admin`: controls withdrawals and role updates.
	- `operator`: executes arbitrary batched calls.
	- `passwordSigner`: second factor signer.
- Global replay protection with `nonce`.
- EIP-191 signature verification for all protected actions.
- Native ETH support via `receive()` for value-forwarding in `execute`.

### Function list

- Public funds flow:
	- `deposit(address token, uint256 amount)`
	- `withdraw(address token, uint256 amount, address recipient, bytes passwordSig)`
	- `withdrawRelay(address token, uint256 amount, address recipient, bytes adminSig, bytes passwordSig)`
- Arbitrary execution:
	- `execute(address[] targets, uint256[] values, bytes[] calldatas, bytes passwordSig)`
- Admin and configuration:
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
- `keccak256("execute")`
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
```

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

- Concise style: `simple-fund-llms.md`
- Full style: `simple-fund-llms-full.md`

