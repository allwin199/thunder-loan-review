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
- So he bought `1 NFT` for `0.01 WETH`
- previously `1 NFT` was `1 WETH`
- This user has manipulated the price and got the NFT for `0.01 WETH`
- This user bought bunch of NFT and went to a differnt NFT marketplace 
- and sold 1 NFT for `1 WETH` and made bunch of money

- Now the user went back to TSwap and withdrew all the USDC
- This user withdrew all `900 USDC`
- Therfore USDC to WETH ratio came back to normal
- `10 USDC` == `1 WETH`  
- Then the user repaid the flash loan with fees

- tldr The user bought bunch of NFT for cheap price and sold it at actual price and made money

### Mock TSwap

  