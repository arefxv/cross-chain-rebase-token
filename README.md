# RebaseToken Project

## Overview

RebaseToken is an ERC20-based token with a rebase mechanism that adjusts token balances over time based on an interest rate. It integrates with a Vault for deposits and withdrawals and a RebaseTokenPool for cross-chain interoperability.

## Features

* **Interest Rate Adjustment**: Token balances increase based on a user-specific interest rate

* **Mint and Burn**: Only authorized addresses can mint and burn tokens.

* **Vault System**: Allows users to deposit and redeem tokens.

* **Cross-Chain Support**: RebaseTokenPool enables cross-chain transactions.

* **Access Control**: Uses Ownable and AccessControl to restrict actions.

## Smart Contracts

1. ### RebaseToken

**Overview**

RebaseToken is an ERC20-compliant token that incorporates a rebasing mechanism, adjusting user balances based on an interest rate set by the contract owner. This allows token balances to grow over time.

**Key Functions**

* `setInterestRate(uint256 newInterestRate)`:

    * **Description**: Sets a new interest rate for rebasing.

    * **Access Control**: Only callable by the contract owner.

    * **Constraints**: The new interest rate can only be decreased.

* `mint(address to, uint256 amount, uint256 userInterestRate)`:

    * **Description**: Mints new tokens for a user with a specific interest rate.

    * **Access Control**: Only authorized addresses can call this function.

    * **Parameters**:

        * `to`: The recipient address.

        * `amount`: Number of tokens to mint.

        * `userInterestRate`: The interest rate applicable to the user.

* `burn(address from, uint256 amount)`:

    * **Description**: Burns tokens from a user's balance, reducing the total supply.

    * **Access Control**: Only authorized addresses can call this function.

    * **Parameters**:

        * `from`: The address whose tokens will be burned.

        * `amount`: Number of tokens to burn.

* `balanceOf(address user)`:

    * **Description**: Returns the user's token balance, considering accumulated interest.

    * **Parameters**:

        * `user`: Address to check the balance of.

    * **Returns**: Updated token balance with interest.

2. ### Vault

**Overview**

The Vault contract acts as a staking system where users can deposit ETH and receive RebaseTokens. When withdrawing, tokens are burned, and ETH is returned.

**Key Functions**

* `deposit()`:

   * **Description**: Allows users to deposit ETH and receive RebaseTokens in return.

   * **Process**:

       1. sends ETH.

       2. Equivalent RebaseTokens are minted to their address.

    * **Security Considerations**:

        * Prevents deposits from unauthorized addresses.

        * Ensures proper ETH-to-token conversion.

* `redeem(uint256 amount)`:

    * **Description**: Burns RebaseTokens and allows users to redeem ETH.

    * **Parameters**:

        * `amount`: Number of tokens to redeem.

    * **Security Considerations**:

        * Ensures users have sufficient balance before redemption.

        * Prevents potential overflows and reentrancy attacks.

3. ### RebaseTokenPool

**Overview**

The RebaseTokenPool contract facilitates cross-chain transactions using Chainlink CCIP. It locks or burns tokens on one chain and releases or mints them on another.

**Key Functions**

* `lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)`:

    * **Description**: Burns tokens before sending them cross-chain.

    * **Parameters**:

        * `lockOrBurnIn`: Encapsulated data structure for cross-chain operations.

    * **Security Considerations**:

        * Ensures only authorized operations are performed.

        * Prevents unauthorized token burning.

* `releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)`:

    * **Description**: Mints tokens on the destination chain after verifying cross-chain transfer.

    * **Parameters**:

        * `releaseOrMintIn`: Encapsulated data structure for receiving tokens on another chain.

    * **Security Considerations**:

        * Ensures authenticity of cross-chain transactions.

        * Prevents unauthorized token minting.

4. ### IRebaseToken (Interface)

**Overview**

Defines the standard interface for interacting with the RebaseToken contract

---

# NOTICE

add your RPC URLs in foundry.toml

---

# THANKS!# cross-chain-rebase-token
