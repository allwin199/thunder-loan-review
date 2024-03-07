<!DOCTYPE html>
<html>
<head>
<style>
    .full-page {
        width:  100%;
        height:  100vh; /* This will make the div take up the full viewport height */
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: center;
    }
    .full-page img {
        max-width:  200;
        max-height:  200;
        margin-bottom: 5rem;
    }
    .full-page div{
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: center;
    }
</style>
</head>
<body>

<div class="full-page">
    <img src="./logo.svg" alt="Logo">
    <div>
    <h1>Thunder Loan Protocol Audit Report</h1>
    <h3>Prepared by: Prince Allwin</h3>
    </div>
</div>

</body>
</html>

<!-- Your report starts here! -->

# Table of Contents
- [Table of Contents](#table-of-contents)
- [Protocol Summary](#protocol-summary)
- [Disclaimer](#disclaimer)
- [Risk Classification](#risk-classification)
- [Audit Details](#audit-details)
  - [Scope](#scope)
  - [Roles](#roles)
- [Executive Summary](#executive-summary)
  - [Issues found](#issues-found)
- [Findings](#findings)
  - [High](#high)
    - [\[H-1\] Erroneous `ThunderLoan::updateExchangeRate` in the `deposit` function causes protocol to think it has more fees that it really does, which blocks redemption and incorrectly sets the exchange rate.](#h-1-erroneous-thunderloanupdateexchangerate-in-the-deposit-function-causes-protocol-to-think-it-has-more-fees-that-it-really-does-which-blocks-redemption-and-incorrectly-sets-the-exchange-rate)
    - [\[H-3\] By calling a flashloan and then `ThunderLoan::deposit` instead of `ThunderLoan::repay` users can steal all funds from the protocol](#h-3-by-calling-a-flashloan-and-then-thunderloandeposit-instead-of-thunderloanrepay-users-can-steal-all-funds-from-the-protocol)
    - [\[H-3\] Mixing up variable location causes storage collisons in `ThunderLoan::s_flashLoanFee` and `ThunderLoan::s_currentlyFlashLoaning`, freesing protocol.](#h-3-mixing-up-variable-location-causes-storage-collisons-in-thunderloans_flashloanfee-and-thunderloans_currentlyflashloaning-freesing-protocol)
  - [Medium](#medium)
    - [\[M-2\] Using TSwap as price oracle leads to price and oracle manipulation attacks](#m-2-using-tswap-as-price-oracle-leads-to-price-and-oracle-manipulation-attacks)

# Protocol Summary


# Disclaimer

Prince Allwin and team makes all effort to find as many vulnerabilities in the code in the given time period, but holds no responsibilities for the findings provided in this document. A security audit by the team is not an endorsement of the underlying business or product. The audit was time-boxed and the review of the code was solely on the security aspects of the Solidity implementation of the contracts.

# Risk Classification

|            |        | Impact |        |     |
| ---------- | ------ | ------ | ------ | --- |
|            |        | High   | Medium | Low |
|            | High   | H      | H/M    | M   |
| Likelihood | Medium | H/M    | M      | M/L |
|            | Low    | M      | M/L    | L   |

We use the [CodeHawks](https://docs.codehawks.com/hawks-auditors/how-to-evaluate-a-finding-severity) severity matrix to determine severity. See the documentation for more details.

# Audit Details 

Commit Hash:
```
```

## Scope 

./src/

## Roles

# Executive Summary

## Issues found

| Severity | Number of issues found |
| -------- | ---------------------- |
| High     | 3                      |
| Medium   | 1                      |
| Low      | 0                      |
| Gas      | 0                      |
| Info     | 0                      |
|          |                        |
| Total    | 4                      |


# Findings

## High

### [H-1] Erroneous `ThunderLoan::updateExchangeRate` in the `deposit` function causes protocol to think it has more fees that it really does, which blocks redemption and incorrectly sets the exchange rate.

**Description:** In the ThunderLoan system, the `exchangeRate` is responsible for calculating the excahnge rate between assetTokens and underlying tokens. In a way, it's responsible for keeping track of how many fees to give to liquidity providers.

However, the `deposit` function, updates this rate, without collecting any fees.

```js
  function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token]; // e represent the shares of the pool
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);

@>      uint256 calculatedFee = getCalculatedFee(token, amount);
@>      assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

**Impact:**  There are several impacts to this bug.

1. The `redeem` function is blocked, because the protocol think the owed tokens is more than it has.
2. Rewards are incorrectly calculated, leading to liquidity providers potentialy getting way more or less than deserved.

**Proof of Concept:**

1. LP deposits
2. User takes out a flash loan
3. It is now impossible for LP to redeem.


<details>

<summary>Proof of Code</summary>

Place the following into `ThunderLoanTest.t.sol`

```js
	function testRedeemAfterLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), calculatedFee);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 amountToRedeem = type(uint256).max;
        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, amountToRedeem);
        vm.stopPrank();
    }
```

</details>

**Recommended Mitigation:** Remove the incorrectly updated exchange rate lines from `deposit`

```diff
	function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);

-      uint256 calculatedFee = getCalculatedFee(token, amount);
-      assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

### [H-3] By calling a flashloan and then `ThunderLoan::deposit` instead of `ThunderLoan::repay` users can steal all funds from the protocol

**Description:** Malicious user can call `ThunderLoan::flashloan` and take out a flashloan for the entire balance of the borrowed token then call `ThunderLoan::deposit` and desposit the entire balance with fee and then call `ThunderLoan::redeem` to redeem the entire balance.

**Impact:** Lost in funds deposited by the liquidity providers.

<details>

<summary>Proof of Code</summary>

- Test `testUseDepositInsteadOfRepayToStealFunds` from `ThunderLoanTest.t.sol`
- Which will drain the entire balance of the borrwed asset

<details>

**Recommended Mitigation:** Add a check in `deposit()` to make it impossible to use it in the same block of the flash loan. For example registring the `block.number` in a variable in flashloan() and checking it in deposit().

### [H-3] Mixing up variable location causes storage collisons in `ThunderLoan::s_flashLoanFee` and `ThunderLoan::s_currentlyFlashLoaning`, freesing protocol.

**Description:** `ThunderLoan.sol` has two variables in the following order.

```js
	uint256 private s_feePrecision;
    uint256 private s_flashLoanFee;
```

However, the upgraded contract `ThunderLoanUpgraded.sol` has them in a different order.

```js
	uint256 private s_flashLoanFee; 
    uint256 public constant FEE_PRECISION = 1e18;
```

Due to how Solidity storage works, after the upgrade the `s_flashLoanFee` will have the value of `s_feePrecision`. You cannot adjust the position of storage variables, and removing storage variables for constant variables, breaks the storage locations as well.

**Impact:** After the upgrade, the `s_flashLoanFee` will have the value of `s_feePrecision`. This means that users who take out flash loans right after an upgrade will be charged the wrong fee.

More importantly, the `s_currentlyFlashLoaning` mapping with storage in the wrong stoage slot.

**Proof of Concept:**

<details>
<summary>Proof of Code</summary>

Place the following into `ThunderLoanTest.t.sol`.

```js

	import { ThunderLoanUpgraded } from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";
	.
	.
	.

	function test_UpgradeBreaks() public {
        uint256 feeBeforeUpgrade = thunderLoan.getFee();
        vm.startPrank(thunderLoan.owner());
        ThunderLoanUpgraded upgraded = new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgraded), "");
        uint256 feeAfterUpgrade = thunderLoan.getFee();
        vm.stopPrank();

        console2.log("Fee Before: ", feeBeforeUpgrade);
        console2.log("Fee After: ", feeAfterUpgrade);

        assert(feeBeforeUpgrade != feeAfterUpgrade);
    }
```

You can also see the storage layout difference by running `forge inspect ThunderLoan storage` and `forge inspect ThunderLoanUpgraded storage`.

</details>

**Recommended Mitigation:** If you must remove the storage variable, leave it as blank as to not mess up the storage slots

```diff
-	uint256 private s_feePrecision;
-	uint256 public constant FEE_PRECISION = 1e18;
+	uint256 private s_blank;
+	uint256 private s_flashLoanFee; 
+   uint256 public constant FEE_PRECISION = 1e18;
```


## Medium

### [M-2] Using TSwap as price oracle leads to price and oracle manipulation attacks

**Description:** The TSwap protocol is a constant product formula based AMM (automated market maker). The price of a token is determined by how many reserves are on either side of the pool. Because of this, it is easy for malicious users to manipulate the price of a token by buying or selling a large amount of the token in the same transaction, essentially ignoring protocol fees. 

**Impact:** Liquidity providers will drastically reduced fees for providing liquidity. 

**Proof of Concept:** 

The following all happens in 1 transaction. 

1. User takes a flash loan from `ThunderLoan` for 1000 `tokenA`. They are charged the original fee `fee1`. During the flash loan, they do the following:
   1. User sells 1000 `tokenA`, tanking the price. 
   2. Instead of repaying right away, the user takes out another flash loan for another 1000 `tokenA`. 
      1. Due to the fact that the way `ThunderLoan` calculates price based on the `TSwapPool` this second flash loan is substantially cheaper. 
```javascript
    function getPriceInWeth(address token) public view returns (uint256) {
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
@>      return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }
```
    3. The user then repays the first flash loan, and then repays the second flash loan.

I have created a proof of code located in my `audit-data` folder. It is too large to include here. 

Test name is `testOracleManipulation` inside `ThunderLoanTest.t.sol`

**Recommended Mitigation:** Consider using a different price oracle mechanism, like a Chainlink price feed with a Uniswap TWAP fallback oracle. 

