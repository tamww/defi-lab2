//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "hardhat/console.sol";

// ----------------------INTERFACES ------------------------------
interface ILendingPool {
    function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) external;
    function getUserAccountData(address user) external view returns (uint256,uint256,uint256,uint256,uint256,uint256);
}

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 value) external;
    function transfer(address to, uint256 value) external returns (bool);
}

interface IWETH is IERC20 { function withdraw(uint256) external; }

interface IUniswapV2Callee { 
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

interface IUniswapV2Factory { 
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112,uint112,uint32);
}

interface IPriceOracleGetter { 
    function getAssetPrice(address _asset) external view returns (uint256);
}

// ----------------------OPTIMIZED CONTRACT------------------------------
contract LiquidationOperator is IUniswapV2Callee {
    address constant TARGET_USER = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    address constant LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IWETH constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    
    // ====================== 动态变量 ======================
    ILendingPool private immutable lendingPool;
    IPriceOracleGetter private immutable priceOracle;
    address private owner;

    constructor() {
        owner = msg.sender;
        lendingPool = ILendingPool(LENDING_POOL);
        priceOracle = IPriceOracleGetter(0xA50ba011c48153De246E5192C8f9258A2ba79Ca9);
    }

    receive() external payable {}

    // ====================== 主入口函数 ======================
    function operate() external {
        require(msg.sender == owner, "Unauthorized");
        
        // 1. 获取实时清算数据
        (,,,uint256 liquidationThreshold,,uint256 healthFactor) = lendingPool.getUserAccountData(TARGET_USER);
        require(healthFactor < 1e18, "Not liquidatable");
        
        // 2. 动态计算最大可清算金额
        (uint112 reserveWETH, uint112 reserveUSDT,) = IUniswapV2Pair(_getPair()).getReserves();
        uint256 maxUSDT = (reserveUSDT * 997) / 1000; // 考虑0.3%手续费后的最大可借量
        uint256 debtToCover = _calculateOptimalDebt(maxUSDT);
        
        // 3. 触发闪电贷
        bytes memory data = abi.encode(debtToCover);
        IUniswapV2Pair(_getPair()).swap(0, debtToCover, address(this), data);
    }

    // ====================== 闪电贷回调 ======================
    function uniswapV2Call(address, uint256, uint256 amount1, bytes calldata data) external override {
        require(msg.sender == _getPair(), "Invalid caller");
        
        // 1. 解析参数
        uint256 debtToCover = abi.decode(data, (uint256));
        
        // 2. 执行清算（循环直到无法清算）
        _executeLiquidation(debtToCover);
        
        // 3. 多级资产兑换优化
        _optimizedAssetSwap();
        
        // 4. 归还闪电贷
        _repayFlashLoan(amount1);
        
        // 5. 提取最终利润
        _withdrawProfit();
    }

    function _calculateOptimalDebt(uint256 maxAvailable) internal view returns (uint256) {
        (,uint256 totalDebtETH,,,,) = lendingPool.getUserAccountData(TARGET_USER);
        uint256 maxLiquidation = (totalDebtETH * 50e18) / 100e18; // 最多清算50%
        uint256 priceUSDT = priceOracle.getAssetPrice(address(USDT));
        return (maxLiquidation < (maxAvailable * priceUSDT / 1e18)) 
               ? maxLiquidation 
               : (maxAvailable * priceUSDT / 1e18);
    }

    function _executeLiquidation(uint256 debtToCover) internal {
        uint256 healthFactor;
        do {
            lendingPool.liquidationCall(address(WBTC), address(USDT), TARGET_USER, debtToCover, false);
            (,,,,,healthFactor) = lendingPool.getUserAccountData(TARGET_USER);
        } while (healthFactor < 1e18);
    }

    function _optimizedAssetSwap() internal {
        uint256 wbtcBalance = WBTC.balanceOf(address(this));
        
        // 三级兑换路径：WBTC → DAI → USDC → ETH
        address[] memory path = new address[](3);
        path[0] = address(WBTC);
        path[1] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        path[2] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        
        // 滑点保护：使用预言机价格计算最小输出
        uint256 minOut = (priceOracle.getAssetPrice(address(WBTC)) * wbtcBalance * 95) / 100;
        
        IUniswapV2Router(UNISWAP_ROUTER).swapExactTokensForETH(
            wbtcBalance,
            minOut,
            path,
            address(this),
            block.timestamp
        );
    }

    function _repayFlashLoan(uint256 amount1) internal {
        // 计算需归还金额（本金 + 0.3% 手续费）
        uint256 repayAmount = (amount1 * 1000) / 997 + 1;
        USDT.transfer(_getPair(), repayAmount);
    }

    function _withdrawProfit() internal {
        uint256 balance = address(this).balance;
        payable(owner).transfer(balance);
        console.log("Final Profit: %s ETH", balance / 1e18);
    }

    // ====================== 工具函数 ======================
    function _getPair() internal view returns (address) {
        return IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(address(WETH), address(USDT));
    }
}
