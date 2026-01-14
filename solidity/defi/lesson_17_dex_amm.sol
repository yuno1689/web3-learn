// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Lesson 17: DEX 原理 - AMM (自动做市商)
 * @notice 本合约实现了一个简化的 Uniswap V2 风格的 AMM 去中心化交易所
 * @dev 实现核心功能：添加流动性、移除流动性、代币交换
 *
 * 学习目标：
 * 1. 理解 AMM (自动做市商) 的核心原理
 * 2. 掌握恒定乘积公式 (x * y = k)
 * 3. 学习流动性提供者 (LP) 代币机制
 * 4. 实现滑点保护和最小输出量计算
 * 5. 理解流动性添加/移除的数学原理
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @dev AMM 代币对合约
 * @notice 管理两个 ERC20 代币之间的流动性池和交换
 */
contract AMMPair is ERC20, ReentrancyGuard, Ownable {
    // ========== 自定义错误 ==========

    error ZeroAmount();
    error InsufficientLiquidity();
    error InvalidAmount();
    error SlippageExceeded();

    // ========== 状态变量 ==========

    /// @notice 交易对中的两个代币
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    /// @notice 储备金数量（用于计算恒定乘积）
    uint256 public reserve0;
    uint256 public reserve1;

    /// @notice 最小流动性（防止下溢问题）
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    // ========== 事件 ==========

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);

    // ========== 构造函数 ==========

    /**
     * @notice 构造函数，创建新的交易对
     * @param _token0 第一个代币地址
     * @param _token1 第二个代币地址
     * @param _name LP 代币名称
     * @param _symbol LP 代币符号
     */
    constructor(
        address _token0,
        address _token1,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_token0 != address(0) && _token1 != address(0), unicode"无效的代币地址");
        require(_token0 != _token1, unicode"代币地址不能相同");

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    // ========== 核心功能：流动性管理 ==========

    /**
     * @notice 添加流动性
     * @dev 用户存入两种代币，获得 LP 代币作为凭证
     * @param amount0Desired 期望存入的 token0 数量
     * @param amount1Desired 期望存入的 token1 数量
     * @param amount0Min 可接受的 token0 最小数量（滑点保护）
     * @param amount1Min 可接受的 token1 最小数量（滑点保护）
     * @return amount0 实际存入的 token0 数量
     * @return amount1 实际存入的 token1 数量
     * @return liquidity 获得的 LP 代币数量
     *
     * 关键概念：
     * - 首次添加流动性：自由定价，按比例分配
     * - 后续添加：必须按当前储备金比例，否则会套利
     * - LP 代币数量 = (实际存入数量 / 总储备金) * LP 总供应量
     */
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        nonReentrant
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 liquidity
        )
    {
        if (amount0Desired == 0 || amount1Desired == 0) revert ZeroAmount();

        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            // ========== 首次添加流动性 ==========
            // 自由定价，直接使用转入的数量
            amount0 = amount0Desired;
            amount1 = amount1Desired;

            // 计算 LP 代币数量
            // liquidity = sqrt(amount0 * amount1)
            liquidity = sqrt(amount0 * amount1);
            if (liquidity > MINIMUM_LIQUIDITY) {
                liquidity = liquidity - MINIMUM_LIQUIDITY;
            } else {
                liquidity = 0;
            }

            // 将锁定的流动性永久保留在合约地址
            _mint(address(this), MINIMUM_LIQUIDITY);
        } else {
            // ========== 后续添加流动性 ==========
            // 按比例计算需要的数量
            amount1 = (amount0Desired * reserve1) / reserve0;

            if (amount1 <= amount1Desired) {
                amount0 = amount0Desired;
            } else {
                amount1 = amount1Desired;
                amount0 = (amount1 * reserve0) / reserve1;
            }

            // 注意：不做使用率检查，允许用户提供任意比例的代币
            // 多余的代币会被退还

            // 计算 LP 代币数量
            liquidity = (amount0 * _totalSupply) / reserve0;
        }

        // 转入代币到合约（全部转入，稍后退还多余部分）
        require(
            token0.transferFrom(msg.sender, address(this), amount0Desired),
            unicode"Token0 转账失败"
        );
        require(
            token1.transferFrom(msg.sender, address(this), amount1Desired),
            unicode"Token1 转账失败"
        );

        // 退还多余的代币
        if (amount0 < amount0Desired) {
            token0.transfer(msg.sender, amount0Desired - amount0);
        }
        if (amount1 < amount1Desired) {
            token1.transfer(msg.sender, amount1Desired - amount1);
        }

        // 滑点保护：确保实际数量在可接受范围内
        require(amount0 >= amount0Min, unicode"Token0 滑点过大");
        require(amount1 >= amount1Min, unicode"Token1 滑点过大");

        // 更新储备金
        _update(balance0Internal(), balance1Internal());

        // 铸造 LP 代币给用户
        _mint(msg.sender, liquidity);

        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @notice 移除流动性
     * @dev 销毁 LP 代币，按比例赎回两种代币
     * @param liquidity 要移除的 LP 代币数量
     * @param amount0Min 可接受的 token0 最小数量（滑点保护）
     * @param amount1Min 可接受的 token1 最小数量（滑点保护）
     * @return amount0 赎回的 token0 数量
     * @return amount1 赎回的 token1 数量
     *
     * 计算逻辑：
     * - amount0 = (liquidity / LP总供应量) * reserve0
     * - amount1 = (liquidity / LP总供应量) * reserve1
     * - 确保用户按其在池子中的份额赎回
     */
    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < liquidity) revert InsufficientLiquidity();

        // 计算应赎回的代币数量
        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * reserve0) / _totalSupply;
        amount1 = (liquidity * reserve1) / _totalSupply;

        // 滑点保护
        if (amount0 < amount0Min) revert SlippageExceeded();
        if (amount1 < amount1Min) revert SlippageExceeded();

        // 销毁 LP 代币
        _burn(msg.sender, liquidity);

        // 更新储备金（先更新，防止重入）
        _update(balance0Internal() - amount0, balance1Internal() - amount1);

        // 转出代币
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        emit Burn(msg.sender, amount0, amount1, msg.sender);
    }

    // ========== 核心功能：代币交换 ==========

    /**
     * @notice 用 token0 交换 token1
     * @param amount0In 存入的 token0 数量
     * @param amount1Min 最少收到的 token1 数量（滑点保护）
     * @return amount1Out 实际收到的 token1 数量
     *
     * 恒定乘积公式：x * y = k
     * - 交换前：reserve0 * reserve1 = k
     * - 交换后：(reserve0 + amount0In) * (reserve1 - amount1Out) = k
     * - 计算得出：amount1Out = (reserve1 * amount0In) / (reserve0 + amount0In)
     *
     * 实际计算中扣除 0.3% 手续费：
     * - amount0InWithFee = amount0In * 997 / 1000
     * - amount1Out = (reserve1 * amount0InWithFee) / (reserve0 + amount0InWithFee)
     */
    function swap0For1(uint256 amount0In, uint256 amount1Min)
        external
        nonReentrant
        returns (uint256 amount1Out)
    {
        if (amount0In == 0) revert ZeroAmount();

        uint256 balance0Before = balance0Internal();
        if (balance0Before < amount0In) revert InsufficientLiquidity();

        // 计算输出数量（扣除 0.3% 手续费）
        // fee = 0.3%，所以输入有效部分 = 997/1000
        uint256 amount0InWithFee = amount0In * 997 / 1000;
        amount1Out = (reserve1 * amount0InWithFee) / (reserve0 + amount0InWithFee);

        if (amount1Out == 0) revert InsufficientLiquidity();
        if (amount1Out >= reserve1) revert InsufficientLiquidity();
        if (amount1Out < amount1Min) revert SlippageExceeded();

        // 更新储备金
        _update(balance0Before + amount0In, balance1Internal() - amount1Out);

        // 转账
        token0.transferFrom(msg.sender, address(this), amount0In);
        token1.transfer(msg.sender, amount1Out);

        emit Swap(msg.sender, amount0In, 0, 0, amount1Out, msg.sender);
    }

    /**
     * @notice 用 token1 交换 token0
     * @param amount1In 存入的 token1 数量
     * @param amount0Min 最少收到的 token0 数量（滑点保护）
     * @return amount0Out 实际收到的 token0 数量
     *
     * 计算公式与 swap0For1 对称：
     * - amount0Out = (reserve0 * amount1InWithFee) / (reserve1 + amount1InWithFee)
     */
    function swap1For0(uint256 amount1In, uint256 amount0Min)
        external
        nonReentrant
        returns (uint256 amount0Out)
    {
        if (amount1In == 0) revert ZeroAmount();

        uint256 balance1Before = balance1Internal();
        if (balance1Before < amount1In) revert InsufficientLiquidity();

        // 计算输出数量（扣除 0.3% 手续费）
        uint256 amount1InWithFee = amount1In * 997 / 1000;
        amount0Out = (reserve0 * amount1InWithFee) / (reserve1 + amount1InWithFee);

        if (amount0Out == 0) revert InsufficientLiquidity();
        if (amount0Out >= reserve0) revert InsufficientLiquidity();
        if (amount0Out < amount0Min) revert SlippageExceeded();

        // 更新储备金
        _update(balance0Internal() - amount0Out, balance1Before + amount1In);

        // 转账
        token1.transferFrom(msg.sender, address(this), amount1In);
        token0.transfer(msg.sender, amount0Out);

        emit Swap(msg.sender, 0, amount1In, amount0Out, 0, msg.sender);
    }

    // ========== 价格查询功能 ==========

    /**
     * @notice 计算用 token0 交换 token1 可得到的数量（包含手续费）
     * @param amountIn 输入的 token0 数量
     * @return amountOut 可得到的 token1 数量
     * @dev 这是一个纯函数，不执行实际交换，仅用于价格查询
     */
    function getAmount0Out(uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        require(amountIn > 0, unicode"数量必须大于零");

        uint256 amountInWithFee = amountIn * 997 / 1000;
        amountOut = (reserve1 * amountInWithFee) / (reserve0 + amountInWithFee);

        require(amountOut <= reserve1, unicode"流动性不足");
    }

    /**
     * @notice 计算用 token1 交换 token0 可得到的数量（包含手续费）
     * @param amountIn 输入的 token1 数量
     * @return amountOut 可得到的 token0 数量
     */
    function getAmount1Out(uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        require(amountIn > 0, unicode"数量必须大于零");

        uint256 amountInWithFee = amountIn * 997 / 1000;
        amountOut = (reserve0 * amountInWithFee) / (reserve1 + amountInWithFee);

        require(amountOut <= reserve0, unicode"流动性不足");
    }

    /**
     * @notice 获取当前储备金
     * @return _reserve0 Token0 储备金
     * @return _reserve1 Token1 储备金
     */
    function getReserves()
        external
        view
        returns (uint256 _reserve0, uint256 _reserve1)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    // ========== 内部函数 ==========

    /**
     * @notice 更新储备金
     * @dev 使用 checks-effects-interactions 模式防止重入攻击
     * @param newBalance0 新的 token0 余额
     * @param newBalance1 新的 token1 余额
     */
    function _update(uint256 newBalance0, uint256 newBalance1) private {
        require(newBalance0 <= type(uint256).max && newBalance1 <= type(uint256).max, unicode"溢出");

        // 更新储备金状态
        reserve0 = newBalance0;
        reserve1 = newBalance1;

        emit Sync(newBalance0, newBalance1);
    }

    /**
     * @notice 获取合约当前 token0 余额
     * @return token0 余额
     */
    function balance0Internal() private view returns (uint256) {
        return token0.balanceOf(address(this));
    }

    /**
     * @notice 获取合约当前 token1 余额
     * @return token1 余额
     */
    function balance1Internal() private view returns (uint256) {
        return token1.balanceOf(address(this));
    }

    /**
     * @notice 计算平方根（使用牛顿迭代法）
     * @param x 输入值
     * @return 平方根
     */
    function sqrt(uint256 x) private pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @notice 计算流动性份额对应的代币数量
     * @param liquidity LP 代币数量
     * @return amount0 对应的 token0 数量
     * @return amount1 对应的 token1 数量
     */
    function getLiquidityValue(uint256 liquidity)
        external
        view
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 _totalSupply = totalSupply();
        require(_totalSupply > 0, unicode"无流动性");
        require(liquidity <= _totalSupply, unicode"超出总供应量");

        amount0 = (liquidity * reserve0) / _totalSupply;
        amount1 = (liquidity * reserve1) / _totalSupply;
    }
}
