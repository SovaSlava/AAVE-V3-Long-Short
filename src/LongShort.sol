// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "./lib/Math.sol";
import {ISwapRouter} from "./interfaces/uniswap-v3/ISwapRouter.sol";
import {IPool} from "./interfaces/aave-v3/IPool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test} from "forge-std/Test.sol";
contract LongShort is Test{

    using SafeERC20 for IERC20;
    struct OpenParams {
        address collateralToken;
        uint256 collateralAmount;
        address borrowToken;
        uint256 borrowAmount;
        uint256 minHealthFactor;
        uint256 minSwapAmountOut;
        // Arbitrary data to be passed to the swap function
        bytes swapData;
    }

    struct CloseParams {
        address collateralToken;
        uint256 collateralAmount;
        uint256 maxCollateralToWithdraw;
        address borrowToken;
        uint256 maxDebtToRepay;
        uint256 minSwapAmountOut;
        // Arbitrary data to be passed to the swap function
        bytes swapData;
    }

    IPool private immutable pool;
    ISwapRouter private immutable router;
    constructor(address poolAddress, address routerAddress) {
        pool = IPool(poolAddress);
        router = ISwapRouter(routerAddress);
    }

    function open(OpenParams memory params) external returns (uint256 collateralAmountOut) {
        // Check that params.minHealthFactor is greater than 1e18
        require(params.minHealthFactor > 1 ether, "helth factor");
        // Transfer collateral from user
        IERC20(params.collateralToken).safeTransferFrom(msg.sender, address(this), params.collateralAmount);
        // Approve and supply collateral to Aave
        // Send aToken to user
        IERC20(params.collateralToken).forceApprove(address(pool), params.collateralAmount);

        pool.supply({
            asset: params.collateralToken,
            amount: params.collateralAmount,
            onBehalfOf: msg.sender,
            referralCode: 0
        });

        pool.borrow({
            asset: params.borrowToken,
            amount: params.borrowAmount,
            // 1 = Stable interest rate
            // 2 = Variable interest rate
            interestRateMode: 2,
            referralCode: 0,
            onBehalfOf: msg.sender
        });
        // Check that health factor of msg.sender is > params.minHealthFactor
        (,,,,,uint256 helfthFactor) = pool.getUserAccountData(msg.sender);
        require(helfthFactor > params.minHealthFactor, "min helth factor");
        // Swap borrowed token to collateral token
        // Send swapped token to msg.sender
        IERC20(params.borrowToken).forceApprove(address(router), params.borrowAmount);

        uint24 fee = abi.decode(params.swapData, (uint24));
        uint256 amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: params.borrowToken,
                tokenOut: params.collateralToken,
                fee: fee,
                recipient: msg.sender,
                amountIn: params.borrowAmount,
                amountOutMinimum: params.minSwapAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        return amountOut;
    }

    function close(CloseParams memory params) external returns(uint256 collateralWithdrawn, uint256 debtRepaidFromMsgSender, uint256 borrowedLeftover, uint256 amountOut) {
        // Transfer collateral from user into this contract
        IERC20(params.collateralToken).safeTransferFrom(msg.sender, address(this), params.collateralAmount);
        IERC20(params.collateralToken).forceApprove(address(router), params.collateralAmount);
        // Swap collateral to borrowed token
        uint24 fee = abi.decode(params.swapData, (uint24));
        amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: params.collateralToken,
                tokenOut: params.borrowToken,
                fee: fee,
                recipient: address(this),
                amountIn: params.collateralAmount,
                amountOutMinimum: params.minSwapAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
    
        // Repay borrowed token
        // Amount to repay is the minimum of current debt and params.maxDebtToRepay
        // If the amount to repay is greater that the amount swapped,
        // then transfer the difference from user
        IPool.ReserveData memory reserve = pool.getReserveData(params.borrowToken);
        uint256 variableDebt = IERC20(reserve.variableDebtTokenAddress).balanceOf(msg.sender);
        uint256 debtBalance = Math.min(variableDebt, params.maxDebtToRepay);
        uint256 repayAmount;
 
        if(debtBalance > amountOut) {
           
            IERC20(params.borrowToken).safeTransferFrom(msg.sender,address(this), debtBalance-amountOut);
            repayAmount = debtBalance-amountOut;
        }

        IERC20(params.borrowToken).forceApprove(address(pool), type(uint256).max);
    
        // Repay all the debt to Aave V3
        // All the debt can be repaid by setting the amount to repay to a number
        // greater than or equal to the current debt
      
        uint256 repaid = pool.repay({
            asset: params.borrowToken,
            amount: debtBalance,
            interestRateMode: 2,
            onBehalfOf: msg.sender
        });
        // Withdraw collateral to msg.sender

        reserve = pool.getReserveData(params.collateralToken);
        address aToken = reserve.aTokenAddress;
        IERC20(aToken).safeTransferFrom(msg.sender, address(this), 
            Math.min(IERC20(aToken).balanceOf(msg.sender), 
                     params.maxCollateralToWithdraw
                    )
        );

       uint256 withdrawn = pool.withdraw({asset: params.collateralToken, amount: params.maxCollateralToWithdraw, to: msg.sender});
        // Transfer profit = swapped amount - repaid amount
        uint256 balance = IERC20(params.borrowToken).balanceOf(address(this));
        if(balance > 0) {
             IERC20(params.borrowToken).safeTransfer(msg.sender, balance);
        }
      
        // Return amount of collateral withdrawn,
        // debt repaid and profit from closing this position
        return(withdrawn, repayAmount, balance, amountOut );
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
