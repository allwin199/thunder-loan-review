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
- 

