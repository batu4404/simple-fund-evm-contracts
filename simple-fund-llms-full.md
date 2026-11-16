# SimpleFund LLM Integration (llms-full style)

This document is a full operational reference for coding agents integrating with `src/SimpleFund.sol`.

## 1) System overview

`SimpleFund` is a general-purpose on-chain execution wallet with:

- multi-token custody (any ERC20 address)
- role-based access control
- nonce-based replay protection
- dual-signature relay support for sensitive admin actions
- Merkle-gated operator execution
- unrestricted admin execution via `executeByAdmin`
- batched calls with optional ETH value forwarding

Protocol-specific behavior (Aave, Nest, Lighter) is encoded by callers through `execute` calldata and attested by decoder contracts in the Merkle leaf.

## 2) Role and trust model

### Roles

- `admin`
  - direct withdraw path
  - direct role rotation path
  - `setManageRoot` / `setLighterDecoder`
  - unrestricted `executeByAdmin` (no Merkle proof)
- `operator`
  - Merkle-gated batch execution path (no password signature)
- `passwordSigner`
  - second factor signer for password-signed admin actions

### Direct path

- Admin actions: caller is `onlyAdmin` and a password signature is required
- Operator `execute`: caller is `onlyOperator` and each call must prove inclusion in `manageRoot`

### Relay path

Only for:

- `withdrawRelay`
- `setManageRootRelay`
- `setLighterDecoderRelay`
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
- nonce is global across password-signed functions
- operator `execute` does not consume nonce; Merkle leaves are reusable until `manageRoot` changes
- old signatures become invalid after any password-signed call succeeds

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

### `execute(bytes32[][] proofs, address[] decoders, address[] targets, uint256[] values, bytes[] calldatas)`

- callable by operator only
- no password signature and does not increment `nonce`
- each call must prove a Merkle leaf against `manageRoot`
- `target == address(this)` reverts
- `manageRoot == bytes32(0)` reverts
- executes batch in-order using low-level call
- forwards ETH `values[i]` with each call

Leaf:

```solidity
keccak256(abi.encodePacked(decoder, target, value > 0, bytes4(calldata), packedAddresses))
```

The decoder is staticcalled with the calldata and must return packed address arguments.

Validation:

- arrays must have equal length
- length must be > 0
- each target non-zero and not the fund
- sum of values must not exceed contract ETH balance

Failure semantics:

- decoder revert is bubbled
- call revert reason is bubbled when present
- if empty revert data, contract throws `Execute call failed`

### `executeByAdmin(address[] targets, uint256[] values, bytes[] calldatas, bytes passwordSig)`

- callable by admin only
- validates password signature
- does not check `manageRoot`
- same batch validation and call loop as operator execute, without the self-call ban

### Admin config (direct + relay)

- `setManageRoot` / `setManageRootRelay`
- `setLighterDecoder` / `setLighterDecoderRelay`
- `setOperator` / `setOperatorRelay`
- `setPasswordSigner` / `setPasswordSignerRelay`
- `setAdmin` / `setAdminRelay`

Zero-address updates are blocked except `setManageRoot`, which may be set to `bytes32(0)` to reject operator execute.

### `consumeDecoderPassword(bytes32 hash, bytes passwordSig)`

- callable only by `lighterDecoder`
- verifies the password signature and increments `nonce`
- used by Lighter decoder whitelist setters

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

### 5.2 Execute by admin

Action constant:

- `EXECUTE_BY_ADMIN_ACTION = keccak256("executeByAdmin")`

Payload:

```solidity
bytes32 rawHash = keccak256(abi.encode(
    keccak256("executeByAdmin"),
    nonce,
    fundAddress,
    chainId,
    targets,
    values,
    calldatas
));
```

### 5.3 setManageRoot

- `SET_MANAGE_ROOT_ACTION = keccak256("setManageRoot")`
- payload: action, nonce, fundAddress, chainId, root

### 5.4 setLighterDecoder

- `SET_LIGHTER_DECODER_ACTION = keccak256("setLighterDecoder")`
- payload: action, nonce, fundAddress, chainId, decoder

### 5.5 setOperator

- `SET_OPERATOR_ACTION = keccak256("setOperator")`
- payload: action, nonce, fundAddress, chainId, newOperator

### 5.6 setPasswordSigner

- `SET_PASSWORD_SIGNER_ACTION = keccak256("setPasswordSigner")`
- payload: action, nonce, fundAddress, chainId, newPasswordSigner

### 5.7 setAdmin

- `SET_ADMIN_ACTION = keccak256("setAdmin")`
- payload: action, nonce, fundAddress, chainId, newAdmin

### 5.8 Lighter decoder whitelist

These hashes are signed over SimpleFund `nonce`, `address(fund)`, and `block.chainid`. The admin then calls the **Lighter decoder**, not SimpleFund. The decoder requires `msg.sender == fund.admin()` and forwards the sig to `fund.consumeDecoderPassword`.

`setDepositAssetAllowed(uint16 assetIndex, bool allowed, bytes passwordSig)`:

```solidity
bytes32 rawHash = keccak256(abi.encode(
    keccak256("setLighterDepositAssetAllowed"),
    nonce,
    fundAddress,
    chainId,
    assetIndex,
    allowed
));
```

`setWithdrawAssetAllowed(uint16 assetIndex, bool allowed, bytes passwordSig)`:

```solidity
bytes32 rawHash = keccak256(abi.encode(
    keccak256("setLighterWithdrawAssetAllowed"),
    nonce,
    fundAddress,
    chainId,
    assetIndex,
    allowed
));
```

`setWithdrawRouteAllowed(uint16 assetIndex, uint8 routeType, bool allowed, bytes passwordSig)`:

```solidity
bytes32 rawHash = keccak256(abi.encode(
    keccak256("setLighterWithdrawRouteAllowed"),
    nonce,
    fundAddress,
    chainId,
    assetIndex,
    routeType,
    allowed
));
```

### 5.9 Signature encoding

Apply EIP-191 prefix before recovering/signing:

```solidity
bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(rawHash);
```

Expected signature encoding in calldata:

- `abi.encodePacked(r, s, v)`

## 6) Decoder leaves (backend)

Match `script/merkle/MerkleTreeLib.sol`. Amounts and non-address args are not in the digest. Current protocol leaves use `valueNonZero = false`.

### 6.1 Digest

```solidity
bytes32 leaf = keccak256(abi.encodePacked(
    decoder,
    target,
    valueNonZero,          // bool, value > 0 at execute time
    bytes4(keccak256(bytes(signature))),
    packedAddresses        // 0..n addresses, each 20 bytes, abi.encodePacked
));
```

Empty packed addresses: hash only decoder, target, valueNonZero, selector.

On execute, SimpleFund staticcalls the decoder with the real calldata. The decoder must return those packed addresses (or empty `bytes`). An empty decoder return is treated as empty packed addresses. A decoder revert bubbles before proof verification.

### 6.2 Tree

1. Hash leaves in the order they will be stored.
2. If a layer has length `> 1` and is odd, duplicate the last hash.
3. Parent = `keccak256(abi.encodePacked(min(a,b), max(a,b)))`.
4. Repeat, padding odd layers the same way, until one root.
5. Proof for a leaf is the sibling at each layer. OpenZeppelin `MerkleProof.verify` is commutative, so proof order of each pair does not matter.

`make merkle-tree` writes `leafs/SimpleFundLeaves_<chainid>.json` from `script/CreateMerkleRoot.s.sol`. Tests call `generateMerkleTree(config)` in-process. A backend may either parse that JSON or reimplement the hasher above.

### 6.3 Ethereum mainnet catalog

Targets:

- USDC `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- Aave V3 pool `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2`
- Nest predicate proxy `0xfC0c4222B3A0c9B060C0B959DEc62442036b9035`
- Nest vault `0xD258029cF5a177e3306E09Fbea63424543a505c0`
- Nest share `0x119Dd7dAFf816f29D7eE47596ae5E4bdC4299165`
- Lighter `0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7`

Use the protocol decoder as `decoder` even for `approve`. Packed addresses must match what the decoder returns:

- Aave approve USDC: `[pool]`
- Aave supply pool: `[USDC, fund]`. Calldata `onBehalfOf` must be `fund`.
- Aave withdraw pool: `[USDC, fund]`. Calldata `to` must be `fund`.
- Nest approve USDC: `[predicate proxy]`
- Nest deposit proxy: `[USDC, vault]`. Signature is `deposit(address,uint256,address,address,(string,uint256,address[],bytes[]))`. Calldata `recipient` must be `fund`.
- Nest approve share: `[vault]`
- Nest requestRedeem / redeem vault: `[]`. Controller, owner, and receiver must be `fund`.
- Lighter approve USDC: `[Lighter]`
- Lighter deposit / withdraw / cancelAllOrders / burnShares: `[]`. Deposit `_to` must be `fund`. Deposit asset default `3`. Withdraw asset default `3`, route default `(3, 1)`.

If `fund` in Aave packed addresses changes, rebuild the tree.

## 7) Integration recipes

### 7.1 Deposit token

1. Approve fund as spender on token.
2. Call `deposit(token, amount)` from depositor account.

### 7.2 Direct withdraw by admin

1. Read `nonce`.
2. Build withdraw raw hash.
3. Sign with password key.
4. Admin sends `withdraw(...)` with password sig.

### 7.3 Relay withdraw

1. Read `nonce`.
2. Build withdraw raw hash.
3. Admin signs hash.
4. Password key signs same hash.
5. Any relayer sends `withdrawRelay(...)` with both signatures.

### 7.4 Operator execute against an allowed protocol

1. Build arrays `targets`, `values`, `calldatas` in final execution order.
2. For each call, choose the decoder and argument addresses that match that decoder.
3. Build Merkle proofs against the current `manageRoot`.
4. Operator sends `execute(...)`. No password signature and no nonce bump.

### 7.5 Aave supply through execute

Typical sequence:

1. `targets[0] = tokenAddress`, `calldatas[0] = approve(pool, amount)`, decoder returns spender
2. `targets[1] = pool`, `calldatas[1] = supply(asset, amount, fund, 0)`, decoder returns asset and onBehalfOf
3. prove both leaves
4. operator submits execute

### 7.6 Admin frontend: executeByAdmin for Aave, Nest, Lighter

Admin UI uses `executeByAdmin`, not operator `execute`. No Merkle proofs, no decoder array. `onlyAdmin` plus a password signature. `nonce` is consumed. Decoders are not staticcalled, so `OnlyFund` and Lighter whitelist are not enforced. Encode recipients as `fund` unless the admin means to send elsewhere.

```solidity
function executeByAdmin(
    address[] targets,
    uint256[] values,
    bytes[] calldatas,
    bytes passwordSig
) external payable; // onlyAdmin
```

Sign the exact arrays that will be submitted:

```solidity
bytes32 rawHash = keccak256(abi.encode(
    keccak256("executeByAdmin"),
    nonce,
    fundAddress,
    chainId,
    targets,
    values,
    calldatas
));
bytes passwordSig = sign(MessageHashUtils.toEthSignedMessageHash(rawHash));
```

`values` is all zeros for these calls. `approve` is IERC20 `approve(address,uint256)`. Addresses are in 6.3.

Aave supply:

```text
targets   = [USDC, Aave pool]
calldatas = [
  approve(pool, amount),
  supply(USDC, amount, fund, uint16(0))
]
```

Aave withdraw (prefer `amount / 2` or less than aToken balance to avoid pool rounding):

```text
targets   = [Aave pool]
calldatas = [withdraw(USDC, amount, fund)]
```

Nest deposit. `PredicateMessage` ABI is `(string taskId, uint256 expireByTime, address[] signerAddresses, bytes[] signatures)`. Production must fetch a valid Nest predicate; an empty message only works if the predicate manager is stubbed.

```text
targets   = [USDC, Nest predicate proxy]
calldatas = [
  approve(proxy, amount),
  deposit(USDC, amount, fund, vault, predicateMessage)
]
```

Nest request redeem, then after the vault owner fulfills, Nest redeem:

```text
targets   = [Nest share, Nest vault]
calldatas = [
  approve(vault, shares),
  requestRedeem(shares, fund, fund)
]

targets   = [Nest vault]
calldatas = [redeem(shares, fund, fund)]
```

Lighter defaults: deposit/withdraw asset index `3` (USDC), withdraw route type `1`. `accountIndex` / `poolIndex` are Lighter account ids, not in the Merkle leaf.

```text
deposit:
  targets   = [USDC, Lighter]
  calldatas = [approve(Lighter, amount), deposit(fund, uint16(3), uint8(1), amount)]

withdraw:
  targets   = [Lighter]
  calldatas = [withdraw(uint48 accountIndex, uint16(3), uint8(1), uint64 amount)]

cancelAllOrders:
  targets   = [Lighter]
  calldatas = [cancelAllOrders(uint48 accountIndex)]

burnShares:
  targets   = [Lighter]
  calldatas = [burnShares(uint48 accountIndex, uint48 poolIndex, uint64 shareAmount)]
```

Lighter asset/route whitelist is not an `executeByAdmin` batch. Use 7.7 decoder setters.

Do not target `address(fund)` unless intended; admin path allows self-calls. Do not pass decoder addresses; that parameter does not exist on `executeByAdmin`.

#### Display amounts (admin UI)

`hlp-internal-be` (`GET /api/v1/manager/balance-details`) is for the boring vault / Pendle sub-account. Do not point a SimpleFund frontend at it. Copy the same RPC reads, with `controller` / `holder` = SimpleFund.

Units: RPC returns and `executeByAdmin` amounts are **wei-style smallest units**. Encode = `userInput * 10**decimals`. Never pass a human `10` as USDC amount (`10` is 0.00001 USDC).

Show **both** on every balance, cap, and confirm screen: raw integer (for debug / what will be encoded) **beside** human-readable `raw / 10**decimals` with symbol, e.g. `1000000` · `1.00 USDC`. User-facing inputs are human; keep the raw copy for the tx. Do not round the raw value. USDC display: 2–6 fractional digits. Nest shares: use `share.decimals()` and the share symbol. Lighter REST is already a decimal string — show it as-is and convert to 6-dec wei only for calldata.

- USDC / aUSDC / Nest asset amounts (`maxWithdraw`, `convertToAssets`): 6 decimals. `1e6` = 1 USDC.
- Nest share amounts: `share.decimals()` (read it; do not hardcode). `requestRedeem` / `redeem` take that raw share wei.
- `values[i]` is wei ETH (18). These protocol batches use `0`.
- Lighter L1 `deposit` / `getPendingBalance`: USDC 6-dec wei (`uint256`).
- Lighter L2 `withdraw` / `burnShares` amounts: same 6-dec wei, typed `uint64`.
- Lighter REST balances are **decimal strings**. Scale to 6-dec wei before calldata.

Idle USDC — max for Aave supply, Nest deposit, Lighter L1 deposit:

```text
USDC.balanceOf(fund)   // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 6 decimals
```

Aave supplied (includes interest) — max for Aave withdraw:

```text
aUSDC.balanceOf(fund)  // 0x98c23e9d8f34fefb1b7bd6a91b7ff122f4e16f5c
```

Exact-all `withdraw(aTokenBalance)` can fail Aave rounding (`0x47bc4b2c`). Use a haircut or `type(uint256).max`.

Nest — three disjoint buckets (`requestId = 0`). `requestRedeem` moves free → pending; fulfillment moves pending → claimable.

```text
freeShares       = share.balanceOf(fund)                         // max requestRedeem
pendingShares    = vault.pendingRedeemRequest(0, fund)             // not actionable
claimableShares  = vault.claimableRedeemRequest(0, fund)           // max redeem
claimableUsdc    = vault.maxWithdraw(fund)                       // display; redeem still takes shares
freeSharesInUsdc = vault.convertToAssets(freeShares)
previewDeposit   = vault.convertToShares(assets)
```

Share `0x119Dd7dAFf816f29D7eE47596ae5E4bdC4299165`, vault `0xD258029cF5a177e3306E09Fbea63424543a505c0`.

Lighter — L2 state is off-chain.

```text
l1PendingUsdc = Lighter.getPendingBalance(fund, uint16(3))
// 0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7
```

`getPendingBalance` is L1 USDC after an L2 withdraw, not the trading balance. For L2 USDC / LIT / LLP shares / `accountIndex` / `poolIndex`, query Lighter REST account `by=l1_address`, `value=fund` (hlp-internal-be host: `https://mainnet.zklighter.elliot.ai`). Cap `withdraw` and `burnShares` from that response.

What that backend already has vs what SimpleFund UI must add:

- Has: aToken `balanceOf`, Nest `balanceOf` + `pendingRedeemRequest` + `maxWithdraw`, Lighter `DetailedAccount`, `getPendingBalance` on TVL only.
- Missing for this fund: any SimpleFund-keyed API; manager Nest `claimableRedeemRequest`; manager Lighter `getPendingBalance`; `accountIndex` as a first-class field.

Refresh after each successful batch.

### 7.7 Admin decoder setup

Aave and Nest have no setters. Only Lighter has on-decoder config.

1. Deploy `SimpleFund(admin, operator, passwordSigner)`.
2. Deploy each decoder with the fund address:
   - `AaveDecoderAndSanitizer(fund)`
   - `NestDecoderAndSanitizer(fund)`
   - `LighterDecoderAndSanitizer(fund)` — constructor already allows deposit/withdraw asset `3` and withdraw route `(3, 1)`.
3. Read `nonce`. Sign `setLighterDecoder` payload. Admin calls `setLighterDecoder(lighterDecoder, passwordSig)` (or relay). Skip this and Lighter whitelist setters revert `Not lighter decoder`.
4. Optional: change Lighter whitelist. As `fund.admin()`, call the decoder:
   - read fund `nonce`
   - sign the matching Lighter hash from 5.8
   - `lighterDecoder.setDepositAssetAllowed(assetIndex, allowed, passwordSig)`
   - or `setWithdrawAssetAllowed` / `setWithdrawRouteAllowed`
   - each success increments fund `nonce`
5. Build the 13 leaves from 6.3 with the live fund and decoder addresses. Compute root.
6. Read `nonce`. Sign `setManageRoot`. Admin calls `setManageRoot(root, passwordSig)`.

Do not call `consumeDecoderPassword` from the backend. There is no relay path on the Lighter decoder. Changing fund or decoder addresses requires a new tree and `setManageRoot`.

## 8) Error handling strategy for agents

### Common reverts and actions

- `Invalid password sig`
  - Re-read nonce, rebuild hash, re-sign.
- `Invalid admin sig`
  - Ensure admin signed same payload and current nonce.
- `Input length mismatch`
  - Repair execute arrays to equal lengths, including proofs and decoders.
- `Invalid manage proof`
  - Rebuild the leaf from decoder, target, value-is-nonzero, selector, and packed addresses.
- `Manage root not set`
  - Admin must set `manageRoot` first.
- `Not lighter decoder`
  - Call `setLighterDecoder` before Lighter whitelist setters.
- `FunctionNotImplemented`
  - Calldata selector is missing on that decoder. Use the catalog signatures.
- `*DecoderAndSanitizer_OnlyFund`
  - Recipient / onBehalfOf / controller is not the fund.
- `LighterDecoderAndSanitizer_InvalidAssetIndex` / `_InvalidRouteType`
  - Update the Lighter whitelist, or use constructor defaults (asset `3`, route `1`).
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

## 9) Agent implementation notes

- Do not pre-sign too early; nonce can change from any protected call.
- Serialize signing and submission steps when possible.
- Keep payload builders centralized per action to avoid field-order bugs.
- For execute batches, pre-simulate each target call where possible.
- Prefer deterministic ordering of calls in arrays for reproducibility.

## 10) Security notes

- Operator can only call leaves in `manageRoot`. Amounts are not pinned in the leaf. The same proofs can be reused until the root changes.
- Admin `executeByAdmin` can call any target and skips the Merkle root.
- Keep operator key operationally separated from admin and password keys.
- Store password key material in hardened signer infrastructure.
- For relay operations, verify both signatures are from expected identities.
- Cross-chain and cross-contract replay is mitigated by chain id and contract address in signed payload.

## 11) Project references

- Contract: `src/SimpleFund.sol`
- Decoders: `src/decoders/`
- Merkle hasher: `script/merkle/MerkleTreeLib.sol`
- Leaf generator: `script/CreateMerkleRoot.s.sol`
- Unit tests: `test/SimpleFund.t.sol`
- Fork tests: `test/SimpleFundEthereum.t.sol`
- Deploy script: `script/DeploySimpleFund.s.sol`
- Make targets: `Makefile` (`deploy-fund`, `merkle-tree`)
