# SimpleFund LLM Integration (llms-full style)

This document is a full operational reference for coding agents integrating with `src/SimpleFund.sol`.

## 1) System overview

`SimpleFund` is a general-purpose on-chain execution wallet with:

- multi-token custody (any ERC20 address)
- role-based access control
- nonce-based replay protection
- dual-signature relay support for sensitive admin actions
- batched arbitrary calls with optional ETH value forwarding

The contract is intentionally protocol-agnostic. Protocol-specific behavior (for example Morpho, DEX, staking) is encoded by callers through `execute` calldata.

## 2) Role and trust model

### Roles

- `admin`
  - direct withdraw path
  - direct role rotation path
- `operator`
  - direct batch execution path
- `passwordSigner`
  - second factor signer for all protected actions

### Direct path

- Caller is role-checked (`onlyAdmin` or `onlyOperator`)
- Password signature is required

### Relay path

Only for:

- `withdrawRelay`
- `setOperatorRelay`
- `setPasswordSignerRelay`
- `setAdminRelay`

No role modifier on caller; transaction sender can be anyone. Contract enforces both:

- valid admin signature
- valid password signature

## 3) Replay and domain separation

All protected actions include these anti-replay fields in hash payloads:

- action discriminator
- `nonce`
- `address(this)`
- `block.chainid`
- function parameters

Nonce rules:

- nonce increments only after successful signature verification
- nonce is global across all protected functions
- old signatures become invalid after any protected call succeeds

## 4) Function reference

### `deposit(address token, uint256 amount)`

- callable by anyone
- transfers ERC20 from caller to fund
- requires token non-zero and amount > 0

### `withdraw(address token, uint256 amount, address recipient, bytes passwordSig)`

- callable by admin only
- validates password signature
- transfers token from fund to recipient

### `withdrawRelay(address token, uint256 amount, address recipient, bytes adminSig, bytes passwordSig)`

- callable by anyone
- requires both signatures

### `execute(address[] targets, uint256[] values, bytes[] calldatas, bytes passwordSig)`

- callable by operator only
- validates password signature
- executes batch in-order using low-level call
- forwards ETH `values[i]` with each call

Validation:

- arrays must have equal length
- length must be > 0
- each target non-zero
- sum of values must not exceed contract ETH balance

Failure semantics:

- call revert reason is bubbled when present
- if empty revert data, contract throws `Execute call failed`

### Admin config (direct + relay)

- `setOperator`
- `setOperatorRelay`
- `setPasswordSigner`
- `setPasswordSignerRelay`
- `setAdmin`
- `setAdminRelay`

Zero-address updates are blocked.

## 5) Signature payload specifications

Use exact field order and types with `abi.encode`.

### 5.1 Withdraw

Action constant:

- `WITHDRAW_ACTION = keccak256("withdraw")`

Payload:

- `WITHDRAW_ACTION`
- `nonce`
- `fundAddress`
- `chainId`
- `token`
- `amount`
- `recipient`

Raw hash:

```solidity
bytes32 rawHash = keccak256(abi.encode(
    keccak256("withdraw"),
    nonce,
    fundAddress,
    chainId,
    token,
    amount,
    recipient
));
```

### 5.2 Execute

Action constant:

- `EXECUTE_ACTION = keccak256("execute")`

Payload:

- `EXECUTE_ACTION`
- `nonce`
- `fundAddress`
- `chainId`
- `targets`
- `values`
- `calldatas`

Raw hash:

```solidity
bytes32 rawHash = keccak256(abi.encode(
    keccak256("execute"),
    nonce,
    fundAddress,
    chainId,
    targets,
    values,
    calldatas
));
```

### 5.3 setOperator

Action constant:

- `SET_OPERATOR_ACTION = keccak256("setOperator")`

Payload:

- action
- nonce
- fundAddress
- chainId
- newOperator

### 5.4 setPasswordSigner

Action constant:

- `SET_PASSWORD_SIGNER_ACTION = keccak256("setPasswordSigner")`

Payload:

- action
- nonce
- fundAddress
- chainId
- newPasswordSigner

### 5.5 setAdmin

Action constant:

- `SET_ADMIN_ACTION = keccak256("setAdmin")`

Payload:

- action
- nonce
- fundAddress
- chainId
- newAdmin

### 5.6 Signature encoding

Apply EIP-191 prefix before recovering/signing:

```solidity
bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(rawHash);
```

Expected signature encoding in calldata:

- `abi.encodePacked(r, s, v)`

## 6) Integration recipes

### 6.1 Deposit token

1. Approve fund as spender on token.
2. Call `deposit(token, amount)` from depositor account.

### 6.2 Direct withdraw by admin

1. Read `nonce`.
2. Build withdraw raw hash.
3. Sign with password key.
4. Admin sends `withdraw(...)` with password sig.

### 6.3 Relay withdraw

1. Read `nonce`.
2. Build withdraw raw hash.
3. Admin signs hash.
4. Password key signs same hash.
5. Any relayer sends `withdrawRelay(...)` with both signatures.

### 6.4 Operator execute against external protocol

1. Build arrays `targets`, `values`, `calldatas` in final execution order.
2. Read `nonce`.
3. Build execute hash.
4. Sign with password key.
5. Operator sends `execute(...)`.

### 6.5 Morpho-style call through execute

You can supply and withdraw on Morpho by passing encoded Morpho calls in `calldatas`.

Typical sequence:

1. `targets[0] = tokenAddress`, `calldatas[0] = approve(morpho, amount)`
2. `targets[1] = morphoAddress`, `calldatas[1] = supply(...)`
3. sign execute payload
4. operator submits execute

## 7) Error handling strategy for agents

### Common reverts and actions

- `Invalid password sig`
  - Re-read nonce, rebuild hash, re-sign.
- `Invalid admin sig`
  - Ensure admin signed same payload and current nonce.
- `Input length mismatch`
  - Repair execute arrays to equal lengths.
- `Insufficient native balance`
  - Reduce `values` sum or fund contract with ETH first.
- `Insufficient token balance`
  - Verify fund token balance before withdraw.

### Safe retry pattern

1. Read fresh on-chain nonce.
2. Reconstruct payload from intended final params.
3. Re-sign.
4. Re-submit once.

Do not blindly retry with stale signatures.

## 8) Agent implementation notes

- Do not pre-sign too early; nonce can change from any protected call.
- Serialize signing and submission steps when possible.
- Keep payload builders centralized per action to avoid field-order bugs.
- For execute batches, pre-simulate each target call where possible.
- Prefer deterministic ordering of calls in arrays for reproducibility.

## 9) Security notes

- Operator is powerful and can call arbitrary targets via execute.
- Keep operator key operationally separated from admin and password keys.
- Store password key material in hardened signer infrastructure.
- For relay operations, verify both signatures are from expected identities.
- Cross-chain and cross-contract replay is mitigated by chain id and contract address in signed payload.

## 10) Project references

- Contract: `src/SimpleFund.sol`
- Unit tests: `test/SimpleFund.t.sol`
- Fork tests: `test/SimpleFundEthereum.t.sol`
- Deploy script: `script/DeploySimpleFund.s.sol`
- Make target: `Makefile` (`deploy-fund`)
