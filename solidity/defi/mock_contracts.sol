// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./lesson_19_yield_aggregator.sol";

/**
 * @title MockStrategy
 * @dev 模拟策略合约(用于收益聚合器测试)
 */
contract MockStrategy is IStrategy {
    IERC20 public asset;
    uint256 public profit;
    address public vault;

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function setVault(address _vault) external {
        vault = _vault;
    }

    function setProfit(uint256 _profit) external {
        profit = _profit;
    }

    function totalAssets() external view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function deposit(uint256 amount) external override returns (uint256) {
        require(asset.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        return amount;
    }

    function withdraw(uint256 amount) external override returns (uint256) {
        require(asset.transfer(msg.sender, amount), "Transfer failed");
        return amount;
    }

    function harvest() external override returns (uint256) {
        if (profit > 0) {
            // 模拟收益：需要确保合约有足够的代币
            // 测试时需要先向策略转入代币作为收益
            uint256 profitAmount = profit;
            profit = 0;

            // 检查余额是否足够
            uint256 balance = asset.balanceOf(address(this));
            if (balance < profitAmount) {
                // 如果余额不足，返回实际可转移的数量
                profitAmount = balance;
            }

            if (profitAmount > 0) {
                require(asset.transfer(msg.sender, profitAmount), "Transfer failed");
                return profitAmount;
            }
        }
        return 0;
    }

    function exit(uint256 amount) external override {
        // exit 应该将所有资产转回 vault
        // 这里直接调用 transfer 而不是 withdraw，避免 msg.sender 问题
        require(asset.transfer(msg.sender, amount), "Transfer failed");
    }

    function getName() external pure override returns (string memory) {
        return "Mock Strategy";
    }
}
