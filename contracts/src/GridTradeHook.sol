// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

// import "forge-std/console.sol";
import {BaseHook} from "./forks/BaseHook.sol";
import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract GridTradeHook is BaseHook, ERC1155 {
  using PoolIdLibrary for PoolKey;
  using CurrencyLibrary for Currency;
  using FixedPointMathLib for uint256;

  bytes internal constant ZERO_BYTES = new bytes(0);

  mapping(PoolId poolId => mapping(
    int24 tick => mapping(bool zeroForOne => int256 amount)
  )) public positions;

  mapping(uint256 tokenId => bool exists) public tokenIdExists;
  mapping(uint256 tokenId => uint256 claimable) public tokenIdClaimable;
  mapping(uint256 tokenId => uint256 supply) public tokenIdTotalSupply;
  mapping(uint256 tokenId => TokenData) public tokenIdData;

  mapping(PoolId poolId => int24 tickLower) public tickLowerLasts;
  mapping(PoolId poolId => mapping(
    int24 tick => uint32 roundId
  )) public tickRoundIds;

  struct TokenData {
    PoolKey poolKey;
    int24 tickLower;
    uint32 roundId;
    bool zeroForOne;
  }

  constructor(
    IPoolManager _poolManager,
    string memory _uri
  ) BaseHook(_poolManager) ERC1155(_uri) {
  }

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
      accessLock: true
    });
  }

  function afterInitialize(
    address,
    PoolKey calldata key,
    uint160,
    int24 tick,
    bytes calldata
  ) external override poolManagerOnly returns (bytes4) {
    int24 tickLower = _getTickLower(tick, key.tickSpacing);
    tickLowerLasts[key.toId()] = tickLower;
    tickRoundIds[key.toId()][tickLower]++;
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

    bool swapZeroForOne = !params.zeroForOne;
    int256 swapAmountIn;

    // If tick has increased (i.e. if price for Token 1 has increased)
    if (lastTickLower < currentTickLower) {
      // [lastTickLower, currentTickLower]
      // Loop through all ticks between the lastTickLower and currentTickLower
      // and execute all orders that are oneForZero
      for (int24 tick = lastTickLower; tick < currentTickLower; ) {
        swapAmountIn = positions[key.toId()][tick][swapZeroForOne];
        if (swapAmountIn > 0) {
          fillOrder(key, tick, swapZeroForOne, swapAmountIn);
        }
        unchecked {
          tick += key.tickSpacing;
        }
      }
    } else {
      // Else if tick has decreased (i.e. price of Token 0 has increased)
      // [currentTickLower, lastTickLower]
      for (int24 tick = lastTickLower; currentTickLower < tick; ) {
        swapAmountIn = positions[key.toId()][tick][swapZeroForOne];
        if (swapAmountIn > 0) {
          fillOrder(key, tick, swapZeroForOne, swapAmountIn);
        }
        unchecked {
          tick -= key.tickSpacing;
        }
      }
    }

    tickLowerLasts[key.toId()] = currentTickLower;

    return GridTradeHook.afterSwap.selector;
  }

  function placeOrder(
    PoolKey calldata key,
    uint256 amountIn,
    bool zeroForOne,
    uint24 gridInterval,
    uint24 gridNum
  ) external returns (uint256[] memory) {
    require(gridInterval != 0, "gridInterval should not be zero");
    require(gridNum != 0, "gridNum should not be zero");
    int24 tickLower = tickLowerLasts[key.toId()];
    uint256 positionAmount = uint256(amountIn / gridNum);

    uint256[] memory tokenIds = new uint256[](gridNum);
    int24 nextTickLower;
    uint32 roundId;
    uint256 tokenId;

    for (uint24 i = 0; i < gridNum; i++) {
      if (zeroForOne) {
        nextTickLower = _getTickLower(tickLower - int24(gridInterval * (i + 1)), key.tickSpacing);
      } else {
        nextTickLower = _getTickLower(tickLower + int24(gridInterval * (i + 1)), key.tickSpacing);
      }
      positions[key.toId()][nextTickLower][zeroForOne] += int256(positionAmount);
      roundId = tickRoundIds[key.toId()][nextTickLower];
      tokenId = getTokenId(key, nextTickLower, roundId, zeroForOne);
      tokenIds[i] = tokenId;

      if (!tokenIdExists[tokenId]) {
        tokenIdExists[tokenId] = true;
        tokenIdData[tokenId] = TokenData(
          key,
          nextTickLower,
          roundId,
          zeroForOne
        );
      }

      // Mint ERC-1155 tokens to the user
      _mint(msg.sender, tokenId, positionAmount, "");
      tokenIdTotalSupply[tokenId] += positionAmount;

    }

    address tokenToBeSoldContract = zeroForOne
      ? Currency.unwrap(key.currency0)
      : Currency.unwrap(key.currency1);

    IERC20Minimal(tokenToBeSoldContract).transferFrom(
      msg.sender,
      address(this),
      amountIn
    );

    return tokenIds;
  }

  function cancelOrder(
    uint256 tokenId
  ) external {

    uint256 amountIn = balanceOf(msg.sender, tokenId);
    require(amountIn > 0, "No orders to cancel.");

    TokenData memory tokenData = tokenIdData[tokenId];

    positions[tokenData.poolKey.toId()][tokenData.tickLower][tokenData.zeroForOne] -= int256(
      amountIn
    );

    tokenIdTotalSupply[tokenId] -= amountIn;
    _burn(msg.sender, tokenId, amountIn);

    address tokenToBeSoldContract = tokenData.zeroForOne
            ? Currency.unwrap(tokenData.poolKey.currency0)
            : Currency.unwrap(tokenData.poolKey.currency1);
    IERC20Minimal(tokenToBeSoldContract).transfer(msg.sender, amountIn);
  }

  function fillOrder(
    PoolKey calldata key,
    int24 tick,
    bool zeroForOne,
    int256 amountIn
  ) internal {
    // Setup the swapping parameters
    IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
      zeroForOne: zeroForOne,
      amountSpecified: amountIn,
      sqrtPriceLimitX96: zeroForOne
        ? TickMath.MIN_SQRT_RATIO + 1
        : TickMath.MAX_SQRT_RATIO - 1
    });

    // Swap
    BalanceDelta delta = abi.decode(
      poolManager.lock(
        address(this),
        abi.encodeCall(this.handleSwap, (key, swapParams))
      ),
      (BalanceDelta)
    );

    // Update mapping to reflect that `amountIn` worth of tokens have been swapped from this order
    positions[key.toId()][tick][zeroForOne] -= amountIn;

    // Current tick roundId
    uint32 roundId = tickRoundIds[key.toId()][tick];
    uint256 tokenId = getTokenId(key, tick, roundId, zeroForOne);

    uint256 amountOfTokensReceivedFromSwap = zeroForOne
      ? uint256(int256(-delta.amount1()))
      : uint256(int256(-delta.amount0()));

    tokenIdClaimable[tokenId] += amountOfTokensReceivedFromSwap;
    // Increase the tick roundId
    tickRoundIds[key.toId()][tick]++;
  }

  function handleSwap(
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params
  ) external returns (BalanceDelta delta) {
    delta = poolManager.swap(key, params, ZERO_BYTES);

    if (params.zeroForOne) {
      if (delta.amount0() > 0) {
        if (key.currency0.isNative()) {
          poolManager.settle{value: uint128(delta.amount0())}(key.currency0);
        } else {
          IERC20Minimal(Currency.unwrap(key.currency0)).transfer(
            address(poolManager), uint128(delta.amount0())
          );
          poolManager.settle(key.currency0);
        }
      }

      if (delta.amount1() < 0) {
        poolManager.take(
          key.currency1,
          address(this),
          uint128(-delta.amount1())
        );
      }
    } else {
      if (delta.amount1() > 0) {
        if (key.currency1.isNative()) {
          poolManager.settle{value: uint128(delta.amount1())}(key.currency1);
        } else {
          IERC20Minimal(Currency.unwrap(key.currency1)).transfer(
              address(poolManager), uint128(delta.amount1())
          );
          poolManager.settle(key.currency1);
        }
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
  }

  function executeNext(
    uint256 tokenId,
    uint24 gridInterval
  ) external returns (uint256) {
    require(
      tokenIdClaimable[tokenId] > 0,
      "No token for next round"
    );

    uint256 balance = balanceOf(msg.sender, tokenId);
    require(
      balance > 0,
      "Insufficient balance"
    );

    TokenData memory tokenData = tokenIdData[tokenId];

    uint256 nextAmountIn = balance.mulDivDown(
      tokenIdClaimable[tokenId],
      tokenIdTotalSupply[tokenId]
    );

    tokenIdClaimable[tokenId] -= nextAmountIn;
    tokenIdTotalSupply[tokenId] -= balance;
    _burn(msg.sender, tokenId, balance);

    // Place next order
    int24 tickLower = tickLowerLasts[tokenData.poolKey.toId()];
    bool nextZeroForOne = !tokenData.zeroForOne;
    int24 nextTickLower;

    if (nextZeroForOne) {
      nextTickLower = _getTickLower(tickLower - int24(gridInterval), tokenData.poolKey.tickSpacing);
    } else {
      nextTickLower = _getTickLower(tickLower + int24(gridInterval), tokenData.poolKey.tickSpacing);
    }
    positions[tokenData.poolKey.toId()][nextTickLower][nextZeroForOne] += int256(nextAmountIn);
    uint32 nextRoundId = tickRoundIds[tokenData.poolKey.toId()][nextTickLower];
    uint256 nextTokenId = getTokenId(tokenData.poolKey, nextTickLower, nextRoundId, nextZeroForOne);
    if (!tokenIdExists[nextTokenId]) {
      tokenIdExists[nextTokenId] = true;
      tokenIdData[nextTokenId] = TokenData(
        tokenData.poolKey,
        nextTickLower,
        nextRoundId,
        nextZeroForOne
      );
    }
    _mint(msg.sender, nextTokenId, nextAmountIn, "");
    tokenIdTotalSupply[nextTokenId] += nextAmountIn;

    return nextTokenId;

  }

  function redeem(
    uint256 tokenId,
    uint256 amountIn,
    address destination
  ) external {
    require(
      tokenIdClaimable[tokenId] > 0,
      "No token to redeem"
    );

    uint256 balance = balanceOf(msg.sender, tokenId);
    require(
      balance >= amountIn,
      "Not enough ERC-1155 tokens to redeem requested amount"
    );

    TokenData memory tokenData = tokenIdData[tokenId];

    address tokenToSendContract = tokenData.zeroForOne
      ? Currency.unwrap(tokenData.poolKey.currency1)
      : Currency.unwrap(tokenData.poolKey.currency0);

    uint256 amountToSend = amountIn.mulDivDown(
      tokenIdClaimable[tokenId],
      tokenIdTotalSupply[tokenId]
    );

    tokenIdClaimable[tokenId] -= amountToSend;
    tokenIdTotalSupply[tokenId] -= amountIn;
    _burn(msg.sender, tokenId, amountIn);

    IERC20Minimal(tokenToSendContract).transfer(destination, amountToSend);
  }

  function getTokenId(
    PoolKey memory key,
    int24 tickLower,
    uint32 roundId,
    bool zeroForOne
  ) public pure returns (uint256) {
    return
      uint256(
        keccak256(abi.encodePacked(
          key.toId(),
          tickLower,
          roundId,
          zeroForOne
        ))
      );
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
