# AAVE V3 Long and short

Aave allows you to earn if we have an assumption about what the price of the asset will be in the future. You can make a profit not only if the price rises (long), but even if the price falls (short). Tests are being conducted on the fork of the ethereum mainnet.

### Run tests
```
forge test --fork-block-number 23063700  --fork-url https://eth-mainnet.g.alchemy.com/v2/{YOURAPIKEY}  -vvv
```

### test_long_weth
We have WETH and we are bet that price goes up.

* Supply 1000 WETH and debt 1000 DAI
* Swap DAI to WETH
* We are waiting for the price to go up
* We exchange the WETH received from the dai exchange back into DAI and repay the debt.
* Withdraw collateral - WETH
* Swap collateral (WETH) to DAI
* It turns out that we have DAI from the exchange of collater + the remainder from the exchange of 1000 DAI for WETH after repay the debt

```
[PASS] test_long_weth() (gas: 1180143)
Logs:
  --- open ---
  Supply 1 WETH, borrow 1000 DAI, swap to 0.284850470408384925 WETH
  WETH price goes up
  --- Close ---
  Swap WETH to 3975.488163028351724714 DAI
  Collateral withdrawn:  1 WETH
  Borrowed leftover:  2975.488163028351724714 DAI
  Swap 1 WETH(Collateral) to DAI
  Final DAI balance - 16914.5087552685390477 DAI
```

### test_long_without_debt
We dont use AAVE. Just waiting high WETH price and swap it to DAI. Price will be the same as in previous test.

```
[PASS] test_long_without_debt() (gas: 259655)
Logs:
  We have 1 WETH
  WETH price goes up
  Swap 1 WETH to DAI
  Final DAI balance - 13942.860691540700287643 DAI
```

### test_short_weth
We assume that the price of VETH will fall, and we want to make money on this. We only have DAI now.

* Supply DAI and borrow WETH
* Swap WETH to DAI
* We are waiting for the price of WETH to go down
* Swap DAI to WETH for repay the debt.
* Withdraw DAI (collateral)
* Swap WETH to DAI.
* It turns out that we have additional DAI from the exchange of borrowed WETH
```
[PASS] test_short_weth() (gas: 1349156)
Logs:
  --- open ---
  Supply 1000 DAI, borrow 0.1 WETH, swap to 348.892866420388435039 DAI
  WETH price dropped down
  --- Close ---
  Swap DAI to 0.397584424469843032 WETH
  Repay debt
  Borrowed leftover: 0.297584424469843032 WETH
  Collateral withdrawn:  1000 DAI
  Swap 0.297584424469843032 WETH to DAI
  Final DAI balance - 1259.581598817232251832 DAI
```
