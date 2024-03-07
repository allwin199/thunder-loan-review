## ThunderLoan

### Deposit
- When deposit is called, the underlying token from Liquidity Provider will be sent to the AssetToken contract
- Now the Asset Token will `mint` the `LP` some `asset` tokens 

### Flash Loan
- When a user calls the flash loan with an amount (let's say USDC)
- Thunder loan will `calculateFee` and `updateExchangeRate` and they give the flash loan to the caller
- It will also execute whatever contract call, the caller want to do
  - 1. Take this flash loan and go to one exchange get `eth` for this flash loan amount (USDC)
  - 2. Then go to different exchange and sell the `eth` for little bit of higher cost and get back the (USDC)
  - 3. Repay the original flash loan amount with fee back to the protocol

### Flash Loan Attack Vectors 
- Since thunder loan is using Tswap for oracle
- We can think of an attack vector
- Let's say a user takes out a flash loan of `900 USDC`
- Using this flash loan, the user went to TSwap protocol to `USDC` to `WETH` pool
- Which already has `100 USDC` and `10 WETH`
- weth to usdc ratio is `1:10`
- Now the user
- Dump this `900 USDC` into this `USDC` to `WETH` pool
- He got almost all the `WETH`
- now the pool has got `100 + 900 USDC`
- almost `1 WETH`
- weth to usdc ratio is `1:1000`

- Let's say there is an NFT protocol also uses this TSwap as Oracle to mint/buy an NFT
- `1 NFT == 10 USDC` or whatever the equvialnt for weth is! because ""weth to usdc ratio is `1:10`""
- `10 USDC` == `1 WETH`  
- If a user pays `10 USDC` or `1 WETH` they will get back `1 NFT`
- since the pool is changed by this user
- pool ratio will be `1:1000`
- Now `10 USDC` == `0.01 WETH` (10/1000) == 0.01
- So the user bought `1 NFT` for `0.01 WETH`
- previously `1 NFT` was `1 WETH`
- This user has manipulated the price and got the NFT for `0.01 WETH`
- This user bought bunch of NFT and went to a differnt NFT marketplace 
- and sold 1 NFT for `1 WETH` and made bunch of money

- Now the user went back to TSwap and withdrew all the USDC
- This user withdrew all `900 USDC`
- Therfore USDC to WETH ratio came back to normal
- `10 USDC` == `1 WETH`  
- Then the user repaid the flash loan with fees

- Since the NFT protocol is using TSwap as price Oracle
- By manipulating the TSwap, we can screw the price of NFT

- tldr The user bought bunch of NFT for cheap price and sold it at actual price and made bunch of money

### Mock TSwap

- We have create a Mock Tswap to check whether we can tank the price and get cheaper fee.


### Thunder Loan Upgraded

- Thunder Loan will be eventually upgraded to ThunderLoan Upgraded
- To check the differnce between 2 files
  
```js
  diff ./src/protocol/ThunderLoan.sol ./src/upgradedProtocol/ThunderLoanUpgraded.sol
  // < will point to ThunderLoan
  // > will point to ThunderLoanUpgraded
```
- Run this command before writing all the comments
  
### Storage Collison

```js
  forge inspect ThunderLoan storage
```
- Output:

```js
    {
      "astId": 48042,
      "contract": "src/protocol/ThunderLoan.sol:ThunderLoan",
      "label": "s_feePrecision",
      "offset": 0,
      "slot": "2",
      "type": "t_uint256"
    },
    {
      "astId": 48044,
      "contract": "src/protocol/ThunderLoan.sol:ThunderLoan",
      "label": "s_flashLoanFee",
      "offset": 0,
      "slot": "3",
      "type": "t_uint256"
    },
```

- `s_feePrecision` is at `slot2`
- `s_flashLoanFee` is at `slot3`

---

```js
  forge inspect ThunderLoanUpgraded storage
```

- Output:

```js
    {
      "astId": 48815,
      "contract": "src/upgradedProtocol/ThunderLoanUpgraded.sol:ThunderLoanUpgraded",
      "label": "s_flashLoanFee",
      "offset": 0,
      "slot": "2",
      "type": "t_uint256"
    },
```

- `s_flashLoanFee` is at `slot2`
- but `s_flashLoanFee` was at `slot3` before upgrade
- """storage_collison"""
  
- They swapped the storage spots
- `s_feePrecision` is converted to constant `FEE_PRECISION`
- which means `FEE_PRECISION` will not have a storage spot.
- It will be in the contract byte code.
- Therfore `s_flashLoanFee` is bumped up one slot

- Since all the storage is stored in proxy contract
- whatever the the value present at `slot2` previously
- will be updated with `s_flashLoanFee` new value when called
- This will mess up the storage