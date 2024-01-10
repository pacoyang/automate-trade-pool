# Automate Trade Pool

## Idea
In some centralized exchanges, they provide users with features for strategic trading, such as grid trading, dollar-cost averaging, dynamic take-profit, and stop-loss. These trading features facilitate an increase in the number of transactions, especially with grid trading strategies, making CEX which primarily profit from transaction fees, prefer users to engage in strategic trading. Comparatively, looking at some decentralized exchanges (DEX) like Uniswap and SushiSwap, their DApps are still in the swapping phase.

Now Uniswap v4 Hooks functionality allows us to implement strategic trading features based on the afterSwap function in the Hooks contract. A pool with strategic trading capabilities not only attracts more traders but also increases the frequency of transactions, enabling liquidity providers to earn more profits.

## Features
* Implement a Hook with grid trading functionality.
* Users can choose a Pool with grid trading capabilities within the DApp, and create a grid trading order.
* After canceling an order, users can redeem their tokens.

## Demo Video
https://github.com/pacoyang/automate-trade-pool/assets/8675900/85f41861-2284-44fe-be0e-e9edc2537944

## More Thoughts
* Implement Hooks for more trading strategies, such as dollar-cost averaging and Martingale.
* Is it possible to dynamically add trading strategies to a Pool through proxy contracts?
* Can we integrate with Phat Contract to allow users to write their own strategies in JavaScript, such as custom trade criteria?
