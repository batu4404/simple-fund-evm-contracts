# SimpleFund LLM Integration (llms style)

This file is a compact, agent-friendly integration spec for `src/SimpleFund.sol`.

## Contract purpose

`SimpleFund` is a multi-token custody and execution contract with nonce-based two-factor signature checks.

## Roles

- `admin`: can withdraw and manage roles.
- `operator`: can execute arbitrary batched calls.
- `passwordSigner`: second-factor signer for protected actions.

## Replay protection

- Global `nonce` is consumed on every successful protected call.
- Signed messages are bound to:
  - action name
  - nonce
  - contract address
  - chain id
  - function params

## Public functions

- `deposit(address token, uint256 amount)`
- `withdraw(address token, uint256 amount, address recipient, bytes passwordSig)`
- `withdrawRelay(address token, uint256 amount, address recipient, bytes adminSig, bytes passwordSig)`
- `execute(address[] targets, uint256[] values, bytes[] calldatas, bytes passwordSig)`
- `setOperator(address newOperator, bytes passwordSig)`
- `setOperatorRelay(address newOperator, bytes adminSig, bytes passwordSig)`
- `setPasswordSigner(address newPasswordSigner, bytes passwordSig)`
- `setPasswordSignerRelay(address newPasswordSigner, bytes adminSig, bytes passwordSig)`
- `setAdmin(address newAdmin, bytes passwordSig)`
- `setAdminRelay(address newAdmin, bytes adminSig, bytes passwordSig)`

## Action discriminators

- `withdraw`: `keccak256("withdraw")`
- `execute`: `keccak256("execute")`
- `setOperator`: `keccak256("setOperator")`
- `setPasswordSigner`: `keccak256("setPasswordSigner")`
- `setAdmin`: `keccak256("setAdmin")`

## Hash payload schemas

Use `abi.encode(...)` in the exact order.

- Withdraw / withdrawRelay:
  - `(WITHDRAW_ACTION, nonce, fundAddress, chainId, token, amount, recipient)`
- Execute:
  - `(EXECUTE_ACTION, nonce, fundAddress, chainId, targets, values, calldatas)`
- setOperator / setOperatorRelay:
  - `(SET_OPERATOR_ACTION, nonce, fundAddress, chainId, newOperator)`
- setPasswordSigner / setPasswordSignerRelay:
  - `(SET_PASSWORD_SIGNER_ACTION, nonce, fundAddress, chainId, newPasswordSigner)`
- setAdmin / setAdminRelay:
  - `(SET_ADMIN_ACTION, nonce, fundAddress, chainId, newAdmin)`

Then apply EIP-191 prefix and sign:

- `ethHash = MessageHashUtils.toEthSignedMessageHash(rawHash)`

## Execution model

`execute` runs a batch of low-level calls in order.

Validation rules:

- `targets.length == values.length`
- `targets.length == calldatas.length`
- `targets.length > 0`
- no zero target
- `sum(values) <= address(this).balance`

If a call fails, revert reason is bubbled when present.

## Error strings to match in tests/clients

- `Not admin`
- `Not operator`
- `Invalid password sig`
- `Invalid admin sig`
- `Input length mismatch`
- `Empty execute batch`
- `Zero target`
- `Insufficient native balance`
- `Zero token`
- `Invalid recipient`
- `Withdraw amount must be greater than zero`
- `Deposit amount must be greater than zero`
- `Insufficient token balance`
- `Invalid operator address`
- `Zero address`
- `Execute call failed`

## Quick agent checklist

1. Read current `nonce` from contract right before building signatures.
2. Build hash using exact field order and data types.
3. Sign with EIP-191 prefix.
4. Submit tx with matching params.
5. If tx reverts with signature error, re-read `nonce` and re-sign.
