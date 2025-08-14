// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {
    POOL,
    ORACLE,
    WETH,
    DAI,
    UNISWAP_V3_POOL_FEE_DAI_WETH,
    UNISWAP_V3_SWAP_ROUTER_02,
    UNISWAP_V3_FACTORY
} from "../src/Constants.sol";
import {IPool} from "../src/interfaces/aave-v3/IPool.sol";
import {IVariableDebtToken} from"../src/interfaces/aave-v3/IVariableDebtToken.sol";
import {IAaveOracle} from "../src/interfaces/aave-v3/IAaveOracle.sol";
import {LongShort} from "../src/LongShort.sol";
import {IUniswapV3Factory} from "../src/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import {IUniswapV3PoolState} from "../src/interfaces/uniswap-v3/IUniswapV3PoolState.sol";
import {ISwapRouter} from "../src/interfaces/uniswap-v3/ISwapRouter.sol";
contract LongShortTest is Test {
    IERC20 private constant weth = IERC20(WETH);
    IERC20 private constant dai = IERC20(DAI);
    IPool private constant pool = IPool(POOL);
    IAaveOracle private constant oracle = IAaveOracle(ORACLE);
    LongShort private target;

    function setUp() public {
        target = new LongShort(POOL, UNISWAP_V3_SWAP_ROUTER_02);
        deal(WETH, address(this),0);
    }

    function test_long_weth() public {
        IPool.ReserveData memory debtReserve = pool.getReserveData(DAI);

        // Test open
        console.log("--- open ---");
        IVariableDebtToken debtToken =
            IVariableDebtToken(debtReserve.variableDebtTokenAddress);
        debtToken.approveDelegation(address(target), type(uint256).max);

        uint256 collateralAmount = 1e18;
        uint256 borrowAmount = 1000 * 1e18;

        deal(WETH, address(this), collateralAmount);
        weth.approve(address(target), collateralAmount);

        bytes memory swapData = abi.encode(UNISWAP_V3_POOL_FEE_DAI_WETH);

        uint256 collateralAmountOut = target.open(
            LongShort.OpenParams({
                collateralToken: WETH,
                collateralAmount: collateralAmount,
                borrowToken: DAI,
                borrowAmount: borrowAmount,
                minHealthFactor: 1.5 * 1e18,
                minSwapAmountOut: 1,
                swapData: swapData
            })
        );
        console.log("Supply 1 WETH, borrow 1000 DAI, swap to", formatDecimals(collateralAmountOut,18),"WETH");
       

        assertGt(collateralAmountOut, 0, "collateral amount out = 0");
        assertEq(
            weth.balanceOf(address(this)),
            collateralAmountOut,
            "WETH balance of this contract"
        );
        assertEq(weth.balanceOf(address(target)), 0, "WETH balance of target");
        
        console.log('WETH price goes up');
        // Test close
        console.log("--- Close ---");
        IPool.ReserveData memory collateralReserve = pool.getReserveData(WETH);
        IERC20 aToken = IERC20(collateralReserve.aTokenAddress);
        aToken.approve(address(target), type(uint256).max);

       // deal(DAI, address(this), 100 * 1e18);
        dai.approve(address(target), 100 * 1e18);
        
        uint256 wethBal = weth.balanceOf(address(this));
        weth.approve(address(target), wethBal);
        uint256[2] memory balsBefore =
            [weth.balanceOf(address(this)), dai.balanceOf(address(this))];

        
        address uniswapPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, DAI, UNISWAP_V3_POOL_FEE_DAI_WETH);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3PoolState(uniswapPool).slot0();
        bytes32 s = vm.load(address(uniswapPool), 0);
        uint256 originalSlotValue = uint256(s);
        // price increase
        uint160 newSqrt = sqrtPriceX96 / 2; 
        uint256 maskLow160 = (uint256(1) << 160) - 1;
        uint256 newSlot = (originalSlotValue & (~maskLow160)) | uint256(uint160(newSqrt));

        vm.store(address(uniswapPool), bytes32(uint256(0)), bytes32(newSlot));
      
        
    
        (
            uint256 collateralWithdrawn,
            uint256 debtRepaidFromMsgSender,
            uint256 borrowedLeftover,
            uint256 closeAmountOut
        ) = target.close(
            LongShort.CloseParams({
                collateralToken: WETH,
                collateralAmount: wethBal,
                maxCollateralToWithdraw: type(uint256).max,
                borrowToken: DAI,
                maxDebtToRepay: type(uint256).max,
                minSwapAmountOut: 1,
                swapData: swapData
            })
        );

        uint256[2] memory balsAfter =
            [weth.balanceOf(address(this)), dai.balanceOf(address(this))];
        console.log("Swap WETH to",formatDecimals(closeAmountOut,18) , "DAI");
        console.log("Collateral withdrawn: ", formatDecimals(collateralWithdrawn,18),"WETH");
      
        console.log("Borrowed leftover: ", formatDecimals(borrowedLeftover,18), "DAI");
        
        assertGe(balsAfter[0], collateralAmount, "WETH balance");
        
        assertGe(collateralWithdrawn, collateralAmount, "WETH withdrawn");
        assertEq(
            balsAfter[1],
            balsBefore[1] - debtRepaidFromMsgSender + borrowedLeftover,
            "DAI balance"
        );
        

        console.log("Swap 1 WETH(Collateral) to DAI");
        IERC20(WETH).approve(UNISWAP_V3_SWAP_ROUTER_02, 1 ether);
          uint256 amountOut = ISwapRouter(UNISWAP_V3_SWAP_ROUTER_02).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: DAI,
                fee: UNISWAP_V3_POOL_FEE_DAI_WETH,
                recipient: address(this),
                amountIn: 1 ether,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            }));
   
     console.log('Final DAI balance -',IERC20(DAI).balanceOf(address(this)), "DAI");
    }


    function test_long_without_debt() public {
        deal(WETH, address(this), 1 ether);
        console.log("We have 1 WETH");
        IERC20(WETH).approve(UNISWAP_V3_SWAP_ROUTER_02, 1 ether);
        console.log("WETH price goes up");
        // increase price
        address uniswapPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, DAI, UNISWAP_V3_POOL_FEE_DAI_WETH);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3PoolState(uniswapPool).slot0();
        bytes32 s = vm.load(address(uniswapPool), 0);
        uint256 originalSlotValue = uint256(s);
        uint160 newSqrt = sqrtPriceX96 / 2; 
        uint256 maskLow160 = (uint256(1) << 160) - 1;
        uint256 newSlot = (originalSlotValue & (~maskLow160)) | uint256(uint160(newSqrt));
        vm.store(address(uniswapPool), bytes32(uint256(0)), bytes32(newSlot));
        // swap
        console.log("Swap 1 WETH to DAI");
        uint256 amountOut = ISwapRouter(UNISWAP_V3_SWAP_ROUTER_02).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: DAI,
                fee: UNISWAP_V3_POOL_FEE_DAI_WETH,
                recipient: address(this),
                amountIn: 1 ether,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            }));

      console.log('Final DAI balance -',IERC20(DAI).balanceOf(address(this)), "DAI");
      
    }
    function test_short_weth() public {
        IPool.ReserveData memory debtReserve = pool.getReserveData(WETH);
        // Test open
        console.log("--- open ---");
        IVariableDebtToken debtToken =
            IVariableDebtToken(debtReserve.variableDebtTokenAddress);
        debtToken.approveDelegation(address(target), type(uint256).max);

        uint256 collateralAmount = 1000 * 1e18;
        uint256 borrowAmount = 0.1 * 1e18;
    
        deal(DAI, address(this), collateralAmount);
        dai.approve(address(target), collateralAmount);

        bytes memory swapData = abi.encode(UNISWAP_V3_POOL_FEE_DAI_WETH);
        uint256 collateralAmountOut = target.open(
            LongShort.OpenParams({
                collateralToken: DAI,
                collateralAmount: collateralAmount,
                borrowToken: WETH,
                borrowAmount: borrowAmount,
                minHealthFactor: 1.5 * 1e18,
                minSwapAmountOut: 1,
                swapData: swapData
            })
        );
       
        console.log("Supply 1000 DAI, borrow 0.1 WETH, swap to", formatDecimals(collateralAmountOut,18),"DAI");
         console.log("WETH price dropped down");
      
          // decrease price
        address uniswapPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, DAI, UNISWAP_V3_POOL_FEE_DAI_WETH);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3PoolState(uniswapPool).slot0();
        bytes32 s = vm.load(address(uniswapPool), 0);
        uint256 originalSlotValue = uint256(s);
        uint160 newSqrt = sqrtPriceX96*2; 
        uint256 maskLow160 = (uint256(1) << 160) - 1;
        uint256 newSlot = (originalSlotValue & (~maskLow160)) | uint256(uint160(newSqrt));
        vm.store(address(uniswapPool), bytes32(uint256(0)), bytes32(newSlot));
        assertGt(collateralAmountOut, 0, "collateral amount out = 0");
        assertEq(
            dai.balanceOf(address(this)),
            collateralAmountOut,
            "DAI balance of this contract"
        );
        assertEq(dai.balanceOf(address(target)), 0, "DAI balance of target");

        // Test close
        console.log("--- Close ---");
        IPool.ReserveData memory collateralReserve = pool.getReserveData(DAI);
        IERC20 aToken = IERC20(collateralReserve.aTokenAddress);
        aToken.approve(address(target), type(uint256).max);

      
        weth.approve(address(target), 1e18);

        uint256 daiBal = dai.balanceOf(address(this));
        dai.approve(address(target), daiBal);

        uint256[2] memory balsBefore =
            [dai.balanceOf(address(this)), weth.balanceOf(address(this))];

        (
            uint256 collateralWithdrawn,
            uint256 debtRepaidFromMsgSender,
            uint256 borrowedLeftover,
            uint256 closeAmountOut
        ) = target.close(
            LongShort.CloseParams({
                collateralToken: DAI,
                collateralAmount: daiBal,
                maxCollateralToWithdraw: type(uint256).max,
                borrowToken: WETH,
                maxDebtToRepay: type(uint256).max,
                minSwapAmountOut: 1,
                swapData: swapData
            })
        );

        uint256[2] memory balsAfter =
            [dai.balanceOf(address(this)), weth.balanceOf(address(this))];

      
      console.log("Swap DAI to",formatDecimals(closeAmountOut,18) , "WETH");
      console.log("Repay debt");
        console.log("Borrowed leftover:", formatDecimals(borrowedLeftover,18) , "WETH");
        console.log("Collateral withdrawn: ", formatDecimals(collateralWithdrawn,18),"DAI");
      
        


       
        assertGe(balsAfter[0], collateralAmount, "DAI balance");
        assertGe(collateralWithdrawn, collateralAmount, "DAI withdrawn");
        assertEq(
            balsAfter[1],
            balsBefore[1] - debtRepaidFromMsgSender + borrowedLeftover,
            "WETH balance"
        );

        IERC20(WETH).approve(UNISWAP_V3_SWAP_ROUTER_02, balsAfter[1]);
        uint256 amountOut = ISwapRouter(UNISWAP_V3_SWAP_ROUTER_02).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: DAI,
                fee: UNISWAP_V3_POOL_FEE_DAI_WETH,
                recipient: address(this),
                amountIn: balsAfter[1],
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            }));

      console.log('Final DAI balance -',formatDecimals(IERC20(DAI).balanceOf(address(this)),18), "DAI");
    }
    
     function formatDecimals(uint256 value, uint8 decimals) internal pure returns (string memory) {
        uint256 integerPart = value / (10 ** decimals);
        uint256 fractionalPart = value % (10 ** decimals);

        while (fractionalPart > 0 && fractionalPart % 10 == 0) {
            fractionalPart /= 10;
        }

        if (fractionalPart == 0) {
            return string(abi.encodePacked(vm.toString(integerPart)));
        } else {
            return string(
                abi.encodePacked(
                    vm.toString(integerPart),
                    ".",
                    vm.toString(fractionalPart)
                )
            );
        }
    }
}
