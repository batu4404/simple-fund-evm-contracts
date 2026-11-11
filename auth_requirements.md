
contract: `SimpleMorphoVault`

I want to implement a **password-based second factor** for sensitive contract functions, so that even if the user’s wallet private key is compromised, the attacker still can’t execute those functions without the password.

The functions I want to protect are:
- `withdraw()`
- `lockFunds()`
- `setOperator()`

And, I want to make contract to non-upgradable, so no one can’t add new functions later if the private key of the deployer is compromised.

Furthermore, there is a case the private key of the admin is compromised and attacker remove all native tokens from the admin wallet, so we can't use admin wallet to pay gas fee for the protected functions. Therefore, I want to make the protected functions can be called by anyone, but require a valid signature from the signature of admin and password-derived private keys.

Requirements:
- Use ECDSA signatures (ecrecover)
- Include a nonce to prevent replay attacks
- Bind the signature to the msg.sender, contract address, and chainId to prevent cross-contract replay
- Use a strong KDF (e.g. scrypt or pbkdf2) to derive the password key, not just keccak(password)
- Write comprehensive tests covering:
  - Valid calls with correct wallet + password
  - Invalid calls with compromised wallet but wrong password
  - Replay attack attempts
  - Edge cases (e.g. empty password, very long password)



Here’s a clean, no-noise summary of the solution you’re building 👇

---

# 🔐 Goal

Protect sensitive contract functions even if the user’s **wallet private key is compromised**, by adding a **password-based second factor**.

---

# 🧠 Core Idea (2FA on-chain)

Require **TWO things at the same time**:

1. ✅ Transaction sent from user wallet (`msg.sender`)
2. ✅ Valid signature from **password-derived private key**

👉 Equivalent to a **2-of-2 multisig**:

* Wallet key = “something you have”
* Password key = “something you know”

---

# ⚙️ How It Works

## 1. Setup

* User chooses a password (off-chain)
* Derive a private key from password (using KDF)
* Compute its address → store in contract as `passwordSigner`

---

## 2. When calling a protected function

### Off-chain (JS/TS)

* Derive private key from password
* Sign a message containing:

  * `msg.sender`
  * `nonce`
  * `contract address`
  * `chainId`

---

### On-chain (Solidity)

* Verify:

  * `msg.sender == owner`
  * `ecrecover(signature) == passwordSigner`
* Increment nonce (prevent replay)
* Execute function

---

# 🔒 Security Properties

### ✅ Protected against:

* Stolen wallet private key
  → attacker cannot execute protected functions without password

---

### ❌ Not protected against:

* Weak password (brute-force)
* Malware / phishing (user leaks password + signature)

---

# ⚠️ Critical Requirements (Don’t Skip)

* Use **ECDSA (`ecrecover`)**
* Include **nonce** (anti-replay)
* Bind signature to:

  * `msg.sender`
  * `contract address`
  * `chainId`
* Use **strong KDF** (e.g. scrypt / pbkdf2), NOT `keccak(password)`
* Require **both wallet + password signature**

---

# 🧩 Minimal Solidity Pattern

```solidity
require(msg.sender == owner);

bytes32 hash = keccak256(
    abi.encode(msg.sender, nonce, address(this), block.chainid)
);

require(recover(hash, sig) == passwordSigner);

nonce++;
```

---

# 🧠 TL;DR

👉 You’re building:

> 🔐 “Wallet + Password = required to execute sensitive actions”

It’s a **simple, effective 2FA model for smart contracts**, as long as you:

* use proper signature verification
* prevent replay
* and derive keys securely

---

If you want, I can turn this into a **production-ready template (Solidity + ethers + EIP-712)** so you can plug it directly into your system.
