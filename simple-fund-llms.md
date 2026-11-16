# SimpleFund LLM Integration (llms style)

This file is a compact, agent-friendly integration spec for `src/SimpleFund.sol`.

## Contract purpose

`SimpleFund` is a multi-token custody and execution contract with nonce-based two-factor signature checks on admin actions. Operator `execute` is gated by a Merkle allowlist and does not use a password signature.

## Roles

- `admin`: can withdraw, manage roles, set `manageRoot`, set `lighterDecoder`, and call `executeByAdmin`.
- `operator`: can execute batched calls that prove inclusion in `manageRoot`.
- `passwordSigner`: second-factor signer for protected actions.

## Replay protection

- Global `nonce` is consumed on every successful password-signed call. Operator `execute` does not consume `nonce`.
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
- `execute(bytes32[][] proofs, address[] decoders, address[] targets, uint256[] values, bytes[] calldatas)`
- `executeByAdmin(address[] targets, uint256[] values, bytes[] calldatas, bytes passwordSig)`
- `setManageRoot(bytes32 root, bytes passwordSig)`
- `setManageRootRelay(bytes32 root, bytes adminSig, bytes passwordSig)`
- `setLighterDecoder(address decoder, bytes passwordSig)`
- `setLighterDecoderRelay(address decoder, bytes adminSig, bytes passwordSig)`
- `consumeDecoderPassword(bytes32 hash, bytes passwordSig)` (only `lighterDecoder`)
- `setOperator(address newOperator, bytes passwordSig)`
- `setOperatorRelay(address newOperator, bytes adminSig, bytes passwordSig)`
- `setPasswordSigner(address newPasswordSigner, bytes passwordSig)`
- `setPasswordSignerRelay(address newPasswordSigner, bytes adminSig, bytes passwordSig)`
- `setAdmin(address newAdmin, bytes passwordSig)`
- `setAdminRelay(address newAdmin, bytes adminSig, bytes passwordSig)`

## Action discriminators

- `withdraw`: `keccak256("withdraw")`
- `executeByAdmin`: `keccak256("executeByAdmin")`
- `setManageRoot`: `keccak256("setManageRoot")`
- `setLighterDecoder`: `keccak256("setLighterDecoder")`
- `setOperator`: `keccak256("setOperator")`
- `setPasswordSigner`: `keccak256("setPasswordSigner")`
- `setAdmin`: `keccak256("setAdmin")`

Lighter decoder setters use:

- `keccak256("setLighterDepositAssetAllowed")`
- `keccak256("setLighterWithdrawAssetAllowed")`
- `keccak256("setLighterWithdrawRouteAllowed")`

## Hash payload schemas

Use `abi.encode(...)` in the exact order.

- Withdraw / withdrawRelay:
  - `(WITHDRAW_ACTION, nonce, fundAddress, chainId, token, amount, recipient)`
- Execute by admin:
  - `(EXECUTE_BY_ADMIN_ACTION, nonce, fundAddress, chainId, targets, values, calldatas)`
- setManageRoot / setManageRootRelay:
  - `(SET_MANAGE_ROOT_ACTION, nonce, fundAddress, chainId, root)`
- setLighterDecoder / setLighterDecoderRelay:
  - `(SET_LIGHTER_DECODER_ACTION, nonce, fundAddress, chainId, decoder)`
- setOperator / setOperatorRelay:
  - `(SET_OPERATOR_ACTION, nonce, fundAddress, chainId, newOperator)`
- setPasswordSigner / setPasswordSignerRelay:
  - `(SET_PASSWORD_SIGNER_ACTION, nonce, fundAddress, chainId, newPasswordSigner)`
- setAdmin / setAdminRelay:
  - `(SET_ADMIN_ACTION, nonce, fundAddress, chainId, newAdmin)`
- Lighter `setDepositAssetAllowed`:
  - `(keccak256("setLighterDepositAssetAllowed"), nonce, fundAddress, chainId, assetIndex, allowed)`
- Lighter `setWithdrawAssetAllowed`:
  - `(keccak256("setLighterWithdrawAssetAllowed"), nonce, fundAddress, chainId, assetIndex, allowed)`
- Lighter `setWithdrawRouteAllowed`:
  - `(keccak256("setLighterWithdrawRouteAllowed"), nonce, fundAddress, chainId, assetIndex, routeType, allowed)`

`nonce`, `fundAddress`, and `chainId` always come from SimpleFund, including Lighter setter hashes.

Then apply EIP-191 prefix and sign:

- `ethHash = MessageHashUtils.toEthSignedMessageHash(rawHash)`

## Execution model

`execute` is operator-only, takes no password signature, and does not consume `nonce`. Each call must prove a Merkle leaf:

```text
keccak256(abi.encodePacked(decoder, target, valueNonZero, selector, packedAddresses))
```

`valueNonZero` is `value > 0`. The decoder is staticcalled with the calldata and must return packed address arguments. `target == address(this)` reverts. `manageRoot == bytes32(0)` reverts.

`executeByAdmin` is admin-only, uses the password signature, and skips the Merkle root.

## Decoder leaves (backend)

Build leaves off-chain to match `script/merkle/MerkleTreeLib.sol`. Do not include amounts in the digest. `valueNonZero` is `false` for all current protocol leaves (no ETH).

Digest:

```text
keccak256(abi.encodePacked(decoder, target, valueNonZero, selector, packedAddresses...))
```

- `selector = bytes4(keccak256(bytes(signature)))`
- `packedAddresses` is concatenated 20-byte addresses (`abi.encodePacked`), never `abi.encode`
- empty packed addresses means concatenate nothing after the selector

Tree (sorted pairing, same as OpenZeppelin `MerkleProof`):

1. Hash every leaf in order.
2. If a layer length is `> 1` and odd, duplicate the last node.
3. Pair `i` with `i+1` using `keccak256(min(a,b) || max(a,b))`.
4. Repeat until one root. Proof is the sibling at each layer.

Ethereum mainnet targets:

- USDC: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- Aave V3 pool: `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2`
- Nest predicate proxy: `0xfC0c4222B3A0c9B060C0B959DEc62442036b9035`
- Nest vault: `0xD258029cF5a177e3306E09Fbea63424543a505c0`
- Nest share: `0x119Dd7dAFf816f29D7eE47596ae5E4bdC4299165`
- Lighter: `0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7`

Leaves (`decoder` is the matching deployed decoder):

| decoder | target | signature | packed addresses |
| --- | --- | --- | --- |
| Aave | USDC | `approve(address,uint256)` | `[pool]` |
| Aave | pool | `supply(address,uint256,address,uint16)` | `[USDC, fund]` |
| Aave | pool | `withdraw(address,uint256,address)` | `[USDC, fund]` |
| Nest | USDC | `approve(address,uint256)` | `[predicate proxy]` |
| Nest | predicate proxy | `deposit(address,uint256,address,address,(string,uint256,address[],bytes[]))` | `[USDC, vault]` |
| Nest | share | `approve(address,uint256)` | `[vault]` |
| Nest | vault | `requestRedeem(uint256,address,address)` | `[]` |
| Nest | vault | `redeem(uint256,address,address)` | `[]` |
| Lighter | USDC | `approve(address,uint256)` | `[Lighter]` |
| Lighter | Lighter | `deposit(address,uint16,uint8,uint256)` | `[]` |
| Lighter | Lighter | `withdraw(uint48,uint16,uint8,uint64)` | `[]` |
| Lighter | Lighter | `cancelAllOrders(uint48)` | `[]` |
| Lighter | Lighter | `burnShares(uint48,uint48,uint64)` | `[]` |

Decoder checks that are not in the leaf (calldata still must pass them or `execute` reverts before proof verify):

- Aave `supply` / `withdraw`: `onBehalfOf` / `to` must be `fund`
- Nest `deposit`: `recipient` must be `fund`
- Nest `requestRedeem` / `redeem`: controller, owner, and receiver must be `fund`
- Lighter `deposit`: `_to` must be `fund`; `_assetIndex` must be allowed (constructor default `3`)
- Lighter `withdraw`: asset index and route must be allowed (constructor default asset `3`, route `(3, 1)`)
- Unknown selector: `FunctionNotImplemented`

`approve` is implemented on `BaseDecoderAndSanitizer` and packs the spender. Use the protocol decoder as the leaf decoder even for approve.

Reference generator: `script/CreateMerkleRoot.s.sol` (`make merkle-tree` writes `leafs/SimpleFundLeaves_<chainid>.json`).

## Admin decoder setup

Aave and Nest have no on-decoder config. Lighter whitelist lives on the Lighter decoder.

Setup order:

1. Deploy `SimpleFund`.
2. Deploy `AaveDecoderAndSanitizer`, `NestDecoderAndSanitizer`, `LighterDecoderAndSanitizer` with the fund address.
3. Admin + password: `setLighterDecoder(lighterDecoder, passwordSig)` (or relay). Required before Lighter whitelist setters work.
4. Optional Lighter whitelist, called on the decoder by `fund.admin()` with a password sig. Each call consumes fund `nonce`.
5. Build the leaf set (fund address is packed into Aave supply/withdraw). Generate root. Admin + password: `setManageRoot(root, passwordSig)`.

Lighter decoder functions (not on SimpleFund):

- `setDepositAssetAllowed(uint16 assetIndex, bool allowed, bytes passwordSig)`
- `setWithdrawAssetAllowed(uint16 assetIndex, bool allowed, bytes passwordSig)`
- `setWithdrawRouteAllowed(uint16 assetIndex, uint8 routeType, bool allowed, bytes passwordSig)`

There is no relay variant on the decoder. Do not call `consumeDecoderPassword` from the backend; the decoder calls it.

If the fund or a decoder address changes, rebuild the tree and `setManageRoot` again.

## Admin frontend: executeByAdmin

Use this path for an admin UI. Do not send proofs or decoder addresses. Decoders are not called, so sanitizer checks (`OnlyFund`, Lighter whitelist) do not run. Still encode `recipient` / `onBehalfOf` / `_to` as `fund` unless the admin intentionally sends elsewhere.

Call:

```text
executeByAdmin(targets, values, calldatas, passwordSig)
```

`msg.sender` must be `admin`. `values[i]` is `0` for these ERC20 protocol calls.

Sign immediately before submit (`nonce` is consumed):

```text
rawHash = keccak256(abi.encode(keccak256("executeByAdmin"), nonce, fund, chainId, targets, values, calldatas))
passwordSig = sign(toEthSignedMessageHash(rawHash))
```

Ethereum calldata (same targets as the leaf catalog). Batch approve + action in one tx when the protocol needs allowance.

Aave

- Supply: `targets = [USDC, pool]`, `calldatas = [approve(pool, amount), supply(USDC, amount, fund, 0)]`
- Withdraw: `targets = [pool]`, `calldatas = [withdraw(USDC, amount, fund)]`

Nest

- Deposit: `targets = [USDC, predicate proxy]`, `calldatas = [approve(proxy, amount), deposit(USDC, amount, fund, vault, predicateMessage)]`
- `predicateMessage = (string taskId, uint256 expireByTime, address[] signerAddresses, bytes[] signatures)`. Production must use a live Nest predicate; empty message is only for tests with a stubbed predicate manager.
- Request redeem: `targets = [share, vault]`, `calldatas = [approve(vault, shares), requestRedeem(shares, fund, fund)]`
- Redeem: `targets = [vault]`, `calldatas = [redeem(shares, fund, fund)]`

Lighter (USDC asset index `3`, spot route `1` unless whitelist was changed)

- Deposit: `targets = [USDC, Lighter]`, `calldatas = [approve(Lighter, amount), deposit(fund, 3, 1, amount)]`
- Withdraw: `targets = [Lighter]`, `calldatas = [withdraw(accountIndex, 3, 1, amount)]` (`accountIndex` is `uint48`, amount is `uint64`)
- Cancel all: `targets = [Lighter]`, `calldatas = [cancelAllOrders(accountIndex)]`
- Burn shares: `targets = [Lighter]`, `calldatas = [burnShares(accountIndex, poolIndex, shareAmount)]`

Lighter whitelist changes are not `executeByAdmin`. Call the decoder setters in Admin decoder setup.

## Frontend: display protocol amounts

Read these from chain (and Lighter's API) against `fund`. Do not use `hlp-internal-be` manager `balance-details` as-is: that API is keyed to the boring vault / Pendle sub-account, not SimpleFund. Reuse the same *contract calls* if you have a backend, or call RPC from the UI.

Holder is always `fund`.

Units: every on-chain read and every `calldatas` amount is **raw smallest units**. Keep that raw value for encoding and caps. Always **also show a human-readable figure beside it** (`raw / 10**decimals`, with the token symbol). User inputs are human; scale to raw before `executeByAdmin`.

| Token / field | decimals | Raw | Show beside it |
| --- | --- | --- | --- |
| USDC, aUSDC, Nest `maxWithdraw` / `convertToAssets` | 6 | `1000000` | `1.00 USDC` |
| Nest shares (`balanceOf`, pending, claimable, `requestRedeem` / `redeem`) | `share.decimals()` | raw uint256 | `1.00` + share symbol |
| ETH `values[i]` | 18 | `1000000000000000000` | `1.00 ETH` (protocol batches use `0`) |
| Lighter L1 `deposit` / `getPendingBalance` | 6 | `1000000` | `1.00 USDC` |
| Lighter L2 `withdraw` `uint64` / `burnShares` `uint64` | 6 | same raw | `1.00 USDC` (or share symbol) |
| Lighter REST `DetailedAccount` | already decimal strings | scale to 6-dec wei for calldata | show the API decimal as-is |

Do not send `"10"` USDC as `10`. Send `10000000` and label `10.00 USDC`. Prefer a fixed 2–6 dp for USDC; do not round the raw value used in calldata.

Idle USDC (max Aave supply, Nest deposit, Lighter deposit)

- `USDC.balanceOf(fund)` at `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`

Aave (max withdraw)

- `aUSDC.balanceOf(fund)` at `0x98c23e9d8f34fefb1b7bd6a91b7ff122f4e16f5c` (Aave V3 Ethereum aUSDC). This already includes accrued interest.
- Cap withdraw at that balance. Aave can revert on exact-all because of rounding; send `amount < aTokenBalance` or `type(uint256).max` to withdraw everything.
- Do not use idle USDC as the Aave position.

Nest (ERC-7540; `requestId` is always `0`). Three buckets are disjoint — do not add them into one number.

| Show as | Read | Use as max for |
| --- | --- | --- |
| Free shares | `share.balanceOf(fund)` | `requestRedeem` |
| Pending shares | `vault.pendingRedeemRequest(0, fund)` | (in flight; not actionable) |
| Claimable shares | `vault.claimableRedeemRequest(0, fund)` | `redeem` |
| Claimable USDC | `vault.maxWithdraw(fund)` | display only; `redeem` takes shares |
| USDC value of free shares | `vault.convertToAssets(freeShares)` | display / deposit preview inverse is `convertToShares(assets)` |

Share token `0x119Dd7dAFf816f29D7eE47596ae5E4bdC4299165`, vault `0xD258029cF5a177e3306E09Fbea63424543a505c0`.

Lighter — L2 balances are **not** on Ethereum. On-chain you only see the L1 bridge.

- L1 pending USDC after a Lighter withdraw: `Lighter.getPendingBalance(fund, uint16(3))` at `0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7`. Show as "claimable / in transit on L1". Not the L2 trading balance.
- L2 USDC available, `accountIndex`, LLP/staking/shares: Lighter REST `GET` account `by=l1_address`, `value=fund` (host used by hlp-internal-be: `https://mainnet.zklighter.elliot.ai`). Cap Lighter `withdraw` / `burnShares` from that snapshot, not from `USDC.balanceOf(fund)`.
- `hlp-internal-be` already does this for the boring vault (`DetailedAccount` + `getPendingBalance`) but does not expose SimpleFund, does not put `getPendingBalance` on manager `balance-details`, and manager Nest UI uses `maxWithdraw` rather than `claimableRedeemRequest`.

Refresh all of the above after every successful `execute` / `executeByAdmin`.

## Error strings to match in tests/clients

- `Not admin`
- `Not operator`
- `Not lighter decoder`
- `Invalid password sig`
- `Invalid admin sig`
- `Input length mismatch`
- `Empty execute batch`
- `Zero target`
- `Self call`
- `Manage root not set`
- `Invalid manage proof`
- `Insufficient native balance`
- `Zero token`
- `Invalid recipient`
- `Withdraw amount must be greater than zero`
- `Deposit amount must be greater than zero`
- `Insufficient token balance`
- `Invalid operator address`
- `Zero address`
- `Execute call failed`
- `FunctionNotImplemented`
- `AaveDecoderAndSanitizer_OnlyFund`
- `NestDecoderAndSanitizer_OnlyFund`
- `LighterDecoderAndSanitizer_OnlyFund`
- `LighterDecoderAndSanitizer_InvalidAssetIndex`
- `LighterDecoderAndSanitizer_InvalidRouteType`

## Quick agent checklist

1. Read current `nonce` from contract right before building signatures.
2. Build hash using exact field order and data types.
3. Sign with EIP-191 prefix.
4. For operator `execute`, include a Merkle proof and decoder per call. Do not sign or bump `nonce`.
5. For admin UI protocol actions, use `executeByAdmin` with the Aave / Nest / Lighter batches above. No proofs. Cap amounts from the display reads (idle USDC, aUSDC, Nest buckets, Lighter API).
6. For Lighter whitelist, call the decoder as admin with a password sig over the Lighter action hashes above.
7. Submit tx with matching params.
8. If a password-signed tx reverts with a signature error, re-read `nonce` and re-sign.
