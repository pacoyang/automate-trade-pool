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
      Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG
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
      IPoolManager.ModifyLiquidityParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether),
      ZERO_BYTES
    );
  }

  function test_placeOrder() public {
    int24 minTick = TickMath.MIN_TICK;
    int24 maxTick = TickMath.MAX_TICK;
    uint24 gridStep = 500;
    uint24 gridNum = 5;
    uint256 gridAmount = 1 ether;
    uint256 amountIn = 10 ether;
    bool zeroForOne = true;

    uint256 originalBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));

    // Place the order
    IERC20Minimal(Currency.unwrap(currency0)).approve(address(hook), amountIn);
    uint256 tokenId = hook.placeOrder(
      key,
      minTick,
      maxTick,
      gridStep,
      gridNum,
      gridAmount,
      amountIn,
      zeroForOne
    );

    uint256 newBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));

    assertEq(originalBalance - newBalance, amountIn);

    uint256 tokenBalance = hook.balanceOf(address(this), tokenId);

    assertTrue(tokenId != 0);
    assertEq(tokenBalance, amountIn);
  }

  function test_cancelOrder() public {
    // Place an order similar as earlier, but cancel it later
    int24 minTick = TickMath.MIN_TICK;
    int24 maxTick = TickMath.MAX_TICK;
    uint24 gridStep = 500;
    uint24 gridNum = 5;
    uint256 gridAmount = 1 ether;
    uint256 amountIn = 10 ether;
    bool zeroForOne = true;

    uint256 originalBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));

    IERC20Minimal(Currency.unwrap(currency0)).approve(address(hook), amountIn);
    uint256 tokenId = hook.placeOrder(
      key,
      minTick,
      maxTick,
      gridStep,
      gridNum,
      gridAmount,
      amountIn,
      zeroForOne
    );

    uint256 newBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));

    assertEq(originalBalance - newBalance, amountIn);

    // Check the balance of ERC-1155 tokens we received
    uint256 tokenBalance = hook.balanceOf(address(this), tokenId);
    assertEq(tokenBalance, amountIn);

    // Cancel the order
    hook.cancelOrder(
      key,
      minTick,
      maxTick,
      gridStep,
      gridNum,
      gridAmount,
      zeroForOne
    );

    uint256 finalBalance = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));
    assertEq(finalBalance, originalBalance);

    tokenBalance = hook.balanceOf(address(this), tokenId);
    assertEq(tokenBalance, 0);
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

