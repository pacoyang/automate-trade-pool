// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {BaseHook} from "./forks/BaseHook.sol";
import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract GridTradeHook is BaseHook, ERC1155 {
  using PoolIdLibrary for PoolKey;
  using CurrencyLibrary for Currency;
  using FixedPointMathLib for uint256;

  bytes internal constant ZERO_BYTES = bytes("");

  mapping(PoolId poolId => int24 tickLower) public tickLowerLasts;

  mapping(PoolId poolId => mapping(
    int24 tick => mapping(bool zeroForOne => uint256[])
  )) public gridPositions;

  mapping(uint256 tokenId => bool exists) public tokenIdExists;
  mapping(uint256 tokenId => uint256 supply) public tokenIdTotalSupply;
  mapping(uint256 tokenId => TokenData) public tokenIdData;

  struct Claimables {
    uint256 claimable0;
    uint256 claimable1;
  }

  mapping(uint256 tokenId => Claimables) public tokenIdClaimables;

  struct TokenData {
    PoolKey poolKey;
    int24 minTickLower;
    int24 maxTickLower;
    uint24 gridStep;
    uint24 gridNum;
    uint256 gridToken0Amount;
    uint256 gridToken1Amount;
    bool zeroForOne;
  }

  constructor(
    IPoolManager _poolManager,
    string memory _uri
  ) BaseHook(_poolManager) ERC1155(_uri) {}

  function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
      beforeInitialize: false,
      afterInitialize: true,
      beforeAddLiquidity: false,
      afterAddLiquidity: false,
      beforeRemoveLiquidity: false,
      afterRemoveLiquidity: false,
      beforeSwap: false,
      afterSwap: true,
      beforeDonate: false,
      afterDonate: false,
      noOp: false,
      accessLock: false
    });
  }

  // Hooks
  function afterInitialize(
    address,
    PoolKey calldata key,
    uint160,
    int24 tick,
    bytes calldata
  ) external override poolManagerOnly returns (bytes4) {
    _setTickLowerLast(key.toId(), _getTickLower(tick, key.tickSpacing));
    return GridTradeHook.afterInitialize.selector;
  }

  function afterSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta,
    bytes calldata
  ) external override poolManagerOnly returns (bytes4) {
    int24 lastTickLower = tickLowerLasts[key.toId()];

    (, int24 currentTick,) = poolManager.getSlot0(key.toId());
    int24 currentTickLower = _getTickLower(currentTick, key.tickSpacing);

    // Execute orders in the opposite direction
    bool swapZeroForOne = !params.zeroForOne;

    // If tick has increased (i.e. if price for Token 1 has increased)
    if (lastTickLower < currentTickLower) {
      // [lastTickLower, currentTickLower]
      // Loop through all ticks between the lastTickLower and currentTickLower
      // and execute all orders that are oneForZero
      for (int24 tick = lastTickLower; tick < currentTickLower; ) {
        uint256[] storage tokenIds = gridPositions[key.toId()][tick][swapZeroForOne];
        for (uint256 i = 0; i < tokenIds.length; i++) {
          fillOrder(key, tick, swapZeroForOne, tokenIds[i]);
        }
        tick += key.tickSpacing;
      }
    }
    // Else if tick has decreased (i.e. price of Token 0 has increased)
    else {
      // [currentTickLower, lastTickLower]
      for (int24 tick = lastTickLower; currentTickLower < tick; ) {
        uint256[] storage tokenIds = gridPositions[key.toId()][tick][swapZeroForOne];
        for (uint256 i = 0; i < tokenIds.length; i++) {
          fillOrder(key, tick, swapZeroForOne, tokenIds[i]);
        }
        tick -= key.tickSpacing;
      }
    }

    tickLowerLasts[key.toId()] = currentTickLower;

    return GridTradeHook.afterSwap.selector;
  }

  function placeOrder(
    PoolKey calldata key,
    int24 minTick,
    int24 maxTick,
    uint24 gridStep,
    uint24 gridNum,
    uint256 gridAmount,
    uint256 amountIn,
    bool zeroForOne
  ) external returns (uint256) {
    require(gridAmount <= amountIn / gridNum, "gridAmount require <= amountIn / gridNum");
    int24 minTickLower = _getTickLower(minTick, key.tickSpacing);
    int24 maxTickLower = _getTickLower(maxTick, key.tickSpacing);
    int24 lastTickLower = tickLowerLasts[key.toId()];

    uint256 tokenId = getTokenId(
      key,
      minTickLower,
      maxTickLower,
      gridStep,
      gridNum,
      gridAmount,
      zeroForOne
    );

    if (!tokenIdExists[tokenId]) {
      tokenIdExists[tokenId] = true;
      tokenIdData[tokenId] = TokenData(
        key,
        minTickLower,
        maxTickLower,
        gridStep,
        gridNum,
        zeroForOne ? gridAmount : 0,
        zeroForOne ? 0 : gridAmount,
        zeroForOne
      );
    }

    int24 nextTickLower;

    for (uint24 i = 1; i <= gridNum; i++) {
      if (zeroForOne) {
        nextTickLower = _getTickLower(lastTickLower - int24(gridStep * i), key.tickSpacing);
        if (nextTickLower < minTickLower) {
          continue;
        }
      } else {
        nextTickLower = _getTickLower(lastTickLower + int24(gridStep * i), key.tickSpacing);
        if (nextTickLower > maxTickLower) {
          continue;
        }
      }
      gridPositions[key.toId()][nextTickLower][zeroForOne].push(tokenId);
    }

    _mint(msg.sender, tokenId, amountIn, "");
    tokenIdTotalSupply[tokenId] += amountIn;

    if (zeroForOne) {
      tokenIdClaimables[tokenId].claimable0 += amountIn;
    } else {
      tokenIdClaimables[tokenId].claimable1 += amountIn;
    }

    address tokenToBeSoldContract = zeroForOne
      ? Currency.unwrap(key.currency0)
      : Currency.unwrap(key.currency1);

    IERC20(tokenToBeSoldContract).transferFrom(
      msg.sender,
      address(this),
      amountIn
    );

    return tokenId;
  }

  function cancelOrder(
    PoolKey calldata key,
    int24 minTick,
    int24 maxTick,
    uint24 gridStep,
    uint24 gridNum,
    uint256 gridAmount,
    bool zeroForOne
  ) external {
    int24 minTickLower = _getTickLower(minTick, key.tickSpacing);
    int24 maxTickLower = _getTickLower(maxTick, key.tickSpacing);
    uint256 tokenId = getTokenId(
      key,
      minTickLower,
      maxTickLower,
      gridStep,
      gridNum,
      gridAmount,
      zeroForOne
    );

    uint256 amountIn = balanceOf(msg.sender, tokenId);
    require(amountIn > 0, "No orders to cancel.");

    uint256 amountToSendToken0 = amountIn.mulDivDown(
      tokenIdClaimables[tokenId].claimable0,
      tokenIdTotalSupply[tokenId]
    );

    uint256 amountToSendToken1 = amountIn.mulDivDown(
      tokenIdClaimables[tokenId].claimable1,
      tokenIdTotalSupply[tokenId]
    );

    tokenIdTotalSupply[tokenId] -= amountIn;
    _burn(msg.sender, tokenId, amountIn);

    if (amountToSendToken0 > 0) {
      tokenIdClaimables[tokenId].claimable0 -= amountToSendToken0;
      IERC20(Currency.unwrap(key.currency0)).transfer(
        msg.sender,
        amountToSendToken0
      );
    }

    if (amountToSendToken1 > 0) {
      tokenIdClaimables[tokenId].claimable1 -= amountToSendToken1;
      IERC20(Currency.unwrap(key.currency1)).transfer(
        msg.sender,
        amountToSendToken1
      );
    }
  }

  function fillOrder(
    PoolKey calldata key,
    int24 tick,
    bool zeroForOne,
    uint256 tokenId
  ) internal {
    TokenData storage tokenData = tokenIdData[tokenId];

    if (
      tick > tokenData.maxTickLower ||
      tick < tokenData.minTickLower ||
      (zeroForOne && tokenData.gridToken0Amount == 0) ||
      (!zeroForOne && tokenData.gridToken1Amount == 0) ||
      (zeroForOne && tokenIdClaimables[tokenId].claimable0 < tokenData.gridToken0Amount) ||
      (!zeroForOne && tokenIdClaimables[tokenId].claimable1 < tokenData.gridToken1Amount)
    ) {
      return;
    }

    // Setup the swapping parameters
    IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
      zeroForOne: zeroForOne,
      amountSpecified: int256(zeroForOne ? tokenData.gridToken0Amount : tokenData.gridToken1Amount),
      // Set the price limit to be the least possible if swapping from Token 0 to Token 1
      // or the maximum possible if swapping from Token 1 to Token 0
      // i.e. infinite slippage allowed
      sqrtPriceLimitX96: zeroForOne
        ? TickMath.MIN_SQRT_RATIO + 1
        : TickMath.MAX_SQRT_RATIO - 1
    });

    // Swap
    BalanceDelta delta = abi.decode(
      poolManager.lock(
        address(this),
        abi.encodeCall(this._handleSwap, (key, swapParams))
      ),
      (BalanceDelta)
    );

    uint256 amountOfTokensReceivedFromSwap = zeroForOne
      ? uint256(int256(-delta.amount1()))
      : uint256(int256(-delta.amount0()));

    int24 nextTickLower;

    if (zeroForOne) {
      tokenIdClaimables[tokenId].claimable0 -= tokenData.gridToken0Amount;
      tokenIdClaimables[tokenId].claimable1 += amountOfTokensReceivedFromSwap;
      if (tokenData.gridToken1Amount == 0) {
        tokenData.gridToken1Amount = amountOfTokensReceivedFromSwap;
      }
      nextTickLower = _getTickLower(tick + int24(tokenData.gridStep), key.tickSpacing);
    } else {
      tokenIdClaimables[tokenId].claimable0 += amountOfTokensReceivedFromSwap;
      tokenIdClaimables[tokenId].claimable1 -= tokenData.gridToken1Amount;
      nextTickLower = _getTickLower(tick - int24(tokenData.gridStep), key.tickSpacing);
      if (tokenData.gridToken0Amount == 0) {
        tokenData.gridToken0Amount = amountOfTokensReceivedFromSwap;
      }
    }

    gridPositions[key.toId()][nextTickLower][!zeroForOne].push(tokenId);
  }

  function _handleSwap(
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params
  ) external returns (BalanceDelta) {
    // delta is the BalanceDelta struct that stores the delta balance changes
    // i.e. Change in Token 0 balance and change in Token 1 balance
    BalanceDelta delta = poolManager.swap(key, params, ZERO_BYTES);

    if (params.zeroForOne) {
      if (delta.amount0() > 0) {
        // Send Token 0 to Uniswap
        IERC20(Currency.unwrap(key.currency0)).transfer(
          address(poolManager),
          uint128(delta.amount0())
        );
        poolManager.settle(key.currency0);
      }

      if (delta.amount1() < 0) {
        poolManager.take(
          key.currency1,
          address(this),
          uint128(-delta.amount1())
        );
      }
    }
    else {
      if (delta.amount1() > 0) {
        IERC20(Currency.unwrap(key.currency1)).transfer(
          address(poolManager),
          uint128(delta.amount1())
        );
        poolManager.settle(key.currency1);
      }

      // If we are owed Token 0, we take it from the Pool Manager
      if (delta.amount0() < 0) {
        poolManager.take(
          key.currency0,
          address(this),
          uint128(-delta.amount0())
        );
      }
    }

    return delta;
  }

  function redeem(
    uint256 tokenId,
    uint256 amountIn,
    address destination
  ) external {
    TokenData memory data = tokenIdData[tokenId];
    uint256 claimable = data.zeroForOne
      ? tokenIdClaimables[tokenId].claimable0
      : tokenIdClaimables[tokenId].claimable1;

    require(
      claimable > 0,
      "No token to redeem"
    );

    uint256 balance = balanceOf(msg.sender, tokenId);
    require(
      balance >= amountIn,
      "Not enough ERC-1155 tokens to redeem requested amount"
    );

    address tokenToSendContract = data.zeroForOne
      ? Currency.unwrap(data.poolKey.currency0)
      : Currency.unwrap(data.poolKey.currency1);

    // multiple people could have added tokens to the same order, so we need to calculate the amount to send
    // total supply = total amount of tokens that were part of the order to be sold
    // therefore, user's share = (amountIn / total supply)
    // therefore, amount to send to user = (user's share * total claimable)

    // amountToSend = amountIn * (total claimable / total supply)
    // We use FixedPointMathLib.mulDivDown to avoid rounding errors
    uint256 amountToSend = amountIn.mulDivDown(
      claimable,
      tokenIdTotalSupply[tokenId]
    );

    if (data.zeroForOne) {
      tokenIdClaimables[tokenId].claimable0 -= amountToSend;
    } else {
      tokenIdClaimables[tokenId].claimable1 -= amountToSend;
    }
    tokenIdTotalSupply[tokenId] -= amountIn;
    _burn(msg.sender, tokenId, amountIn);

    IERC20(tokenToSendContract).transfer(destination, amountToSend);
  }

  function getTokenId(
    PoolKey calldata key,
    int24 minTickLower,
    int24 maxTickLower,
    uint24 gridStep,
    uint24 gridNum,
    uint256 gridAmount,
    bool zeroForOne
  ) public pure returns (uint256) {
    return
      uint256(
        keccak256(abi.encodePacked(
          key.toId(),
          minTickLower,
          maxTickLower,
          gridStep,
          gridNum,
          gridAmount,
          zeroForOne
        ))
      );
  }

  // Helper Functuons
  function _setTickLowerLast(PoolId poolId, int24 tickLower) private {
    tickLowerLasts[poolId] = tickLower;
  }

  function _getTickLower(
    int24 actualTick,
    int24 tickSpacing
  ) private pure returns (int24) {
    int24 intervals = actualTick / tickSpacing;
    if (actualTick < 0 && (actualTick % tickSpacing) != 0) {
      intervals--;
    }
    return intervals * tickSpacing;
  }

}
