// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

import {HookMiner} from "./utils/HookMiner.sol";
import {GridTradeHook} from "../src/GridTradeHook.sol";

contract GridTradeHookTest is Test, Deployers {
  using PoolIdLibrary for PoolKey;
  using CurrencyLibrary for Currency;

  GridTradeHook hook;
  PoolId poolId;

  function setUp() public {
    // Create the pool manager, utility routers, and test tokens
    Deployers.deployFreshManagerAndRouters();
    (currency0, currency1) = Deployers.deployMintAndApprove2Currencies();

    // Deploy the hook to an address with the correct flags
    uint160 flags = uint160(
      Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.ACCESS_LOCK_FLAG
    );
    (address hookAddress, bytes32 salt) =
        HookMiner.find(address(this), flags, type(GridTradeHook).creationCode, abi.encode(address(manager), ""));
    hook = new GridTradeHook{salt: salt}(IPoolManager(address(manager)), "");
    require(address(hook) == hookAddress, "GridTradeHookTest: hook address mismatch");

    // Create the pool
    key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
    poolId = key.toId();
    initializeRouter.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

    // Provide liquidity to the pool
    modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 10 ether), ZERO_BYTES);
    modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-120, 120, 10 ether), ZERO_BYTES);
    modifyLiquidityRouter.modifyLiquidity(
      key,
      IPoolManager.ModifyLiquidityParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 100 ether),
      ZERO_BYTES
    );
  }

  function testPlaceOrder() public {
    uint256 amountIn = 1 ether;
    bool zeroForOne = true;

    uint256 originalBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));

    // Place the order
    IERC20Minimal(Currency.unwrap(currency0)).approve(address(hook), amountIn);
    uint256[] memory tokenIds = hook.placeOrder(
      key,
      amountIn,
      zeroForOne,
      500,
      5
    );

    uint256 newBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));

    assertEq(originalBalance - newBalance, amountIn);

    uint256 totalTokenBalance;
    for (uint i = 0; i < tokenIds.length; i++) {
      totalTokenBalance += hook.balanceOf(address(this), tokenIds[i]);
    }

    assertEq(tokenIds.length, 5);
    assertEq(totalTokenBalance, amountIn);
  }

  function testCancelOrder() public {
    // Place an order similar as earlier, but cancel it later
    uint256 amountIn = 1 ether;
    bool zeroForOne = true;

    uint256 originalBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));

    IERC20Minimal(Currency.unwrap(currency0)).approve(address(hook), amountIn);
    uint256[] memory tokenIds = hook.placeOrder(
      key,
      amountIn,
      zeroForOne,
      500,
      5
    );

    uint256 newBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));

    assertEq(originalBalance - newBalance, amountIn);

    // Check the balance of ERC-1155 tokens we received
    uint256 totalTokenBalance;
    for (uint i = 0; i < tokenIds.length; i++) {
      totalTokenBalance += hook.balanceOf(address(this), tokenIds[i]);
    }
    assertEq(totalTokenBalance, amountIn);

    // Cancel the order
    for (uint i = 0; i < tokenIds.length; i++) {
      hook.cancelOrder(tokenIds[i]);
    }

    uint256 finalBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));
    assertEq(finalBalance, originalBalance);

    totalTokenBalance = 0;
    for (uint i = 0; i < tokenIds.length; i++) {
      totalTokenBalance += hook.balanceOf(address(this), tokenIds[i]);
    }
    assertEq(totalTokenBalance, 0);
  }

  function testExecuteOrderZeroForOne() public {
    uint256 amountIn = 1 ether;
    bool zeroForOne = true;
    uint24 gridInterval = 100;
    uint24 gridNum = 5;
    uint256 positionAmount = uint256(amountIn / gridNum);

    IERC20Minimal(Currency.unwrap(currency0)).approve(address(hook), amountIn);
    uint256[] memory tokenIds = hook.placeOrder(
      key,
      amountIn,
      zeroForOne,
      gridInterval,
      gridNum
    );
    assertEq(tokenIds.length, gridNum);

    // Make token1 price up
    IPoolManager.SwapParams memory params1 = IPoolManager.SwapParams({
      zeroForOne: zeroForOne,
      amountSpecified: 1 ether,
      sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
    });
    PoolSwapTest.TestSettings memory testSettings1 = PoolSwapTest.TestSettings({
      withdrawTokens: true,
      settleUsingTransfer: true,
      currencyAlreadySent: false
    });
    swapRouter.swap(key, params1, testSettings1, ZERO_BYTES);

    // Make token1 price down
    IPoolManager.SwapParams memory params2 = IPoolManager.SwapParams({
      zeroForOne: !zeroForOne,
      amountSpecified: 1 ether,
      sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
    });
    PoolSwapTest.TestSettings memory testSettings2 = PoolSwapTest.TestSettings({
      withdrawTokens: true,
      settleUsingTransfer: true,
      currencyAlreadySent: false
    });
    swapRouter.swap(key, params2, testSettings2, ZERO_BYTES);

    // Check one of the orders have been executed
    int256 tokensLeftToSell = hook.positions(key.toId(), -120, zeroForOne);
    assertEq(tokensLeftToSell, 0);

    // Check the hook has the expected amount of token1 to redeem
    uint256 claimableTokens;
    for (uint i = 0; i < tokenIds.length; i++) {
      claimableTokens += hook.tokenIdClaimable(tokenIds[i]);
    }
    uint256 hookContractToken1Balance = IERC20Minimal(Currency.unwrap(currency1)).balanceOf(address(hook));
    assertEq(claimableTokens, hookContractToken1Balance);

    // Ensure we can redeem the token1
    uint256 originalToken1Balance = IERC20Minimal(Currency.unwrap(currency1)).balanceOf(address(this));
    for (uint i = 0; i < tokenIds.length; i++) {
      if (hook.tokenIdClaimable(tokenIds[i]) > 0) {
        hook.redeem(tokenIds[i], positionAmount, address(this));
      }
    }
    uint256 newToken1Balance = IERC20Minimal(Currency.unwrap(currency1)).balanceOf(address(this));
    assertEq(newToken1Balance - originalToken1Balance, claimableTokens);

  }

  // Add a couple of constant functions to
  // make sure the Test smart contract can receive ERC-1155 tokens
  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) external pure returns (bytes4) {
    return
      bytes4(
        keccak256(
          "onERC1155Received(address,address,uint256,uint256,bytes)"
        )
      );
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external pure returns (bytes4) {
    return
      bytes4(
        keccak256(
          "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"
        )
      );
  }
}

