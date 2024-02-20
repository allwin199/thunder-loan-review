---
title: Protocol Audit Report
author: Prince Allwin
date: February 20, 2024
header-includes:
  - \usepackage{titling}
  - \usepackage{graphicx}
---

\begin{titlepage}
    \centering
    \begin{figure}[h]
        \centering
    \end{figure}
    \vspace*{2cm}
    {\Huge\bfseries Protocol Audit Report\par}
    \vspace{1cm}
    {\Large Version 1.0\par}
    \vspace{2cm}
    {\Large\itshape Prince Allwin\par}
    \vfill
    {\large \today\par}
\end{titlepage}

\maketitle

<!-- Your report starts here! -->

Prepared by: [Prince Allwin]()
Lead Security Researches: 
- Prince Allwin

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
		- [\[H-2\] User can steal funds.](#h-2-user-can-steal-funds)
	- [Medium](#medium)
		- [\[M-1\] Using Tswap as price oracle leads to price and oracle manipulation attacks.](#m-1-using-tswap-as-price-oracle-leads-to-price-and-oracle-manipulation-attacks)
	- [Informational](#informational)

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
| High     | 0                      |
| Medium   | 0                      |
| Low      | 0                      |
| Gas      | 0                      |
| Info     | 0                      |
|          |                        |
| Total    | 0                      |


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

### [H-2] User can steal funds.

<!-- Complete the writeup -->

## Medium

### [M-1] Using Tswap as price oracle leads to price and oracle manipulation attacks.

<!-- Complete the writeup -->

## Informational