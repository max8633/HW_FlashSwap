// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import { IUniswapV2Factory } from "v2-core/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router01 } from "v2-periphery/interfaces/IUniswapV2Router01.sol";
import { IWETH } from "v2-periphery/interfaces/IWETH.sol";
import { IFakeLendingProtocol } from "./interfaces/IFakeLendingProtocol.sol";

// This is liquidator contract for testing,
// all you need to implement is flash swap from uniswap pool and call lending protocol liquidate function in uniswapV2Call
// lending protocol liquidate rule can be found in FakeLendingProtocol.sol
contract Liquidator is IUniswapV2Callee, Ownable {
    address internal immutable _FAKE_LENDING_PROTOCOL;
    address internal immutable _UNISWAP_ROUTER;
    address internal immutable _UNISWAP_FACTORY;
    address internal immutable _WETH9;
    uint256 internal constant _MINIMUM_PROFIT = 0.01 ether;

    constructor(address lendingProtocol, address uniswapRouter, address uniswapFactory) {
        _FAKE_LENDING_PROTOCOL = lendingProtocol;
        _UNISWAP_ROUTER = uniswapRouter;
        _UNISWAP_FACTORY = uniswapFactory;
        _WETH9 = IUniswapV2Router01(uniswapRouter).WETH();
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        // TODO
        require(sender == address(this), "Sender must be this contract");
        require(amount0 == 0 || amount1 == 0, "One of the amount must be 0");

        // 1. decode data and get pair address
        (address[] memory path) = abi.decode(data, (address[]));
        address pair = IUniswapV2Factory(_UNISWAP_FACTORY).getPair(path[0], path[1]);
        require(msg.sender == pair, "Sender must be uniswap pair");

        address WETHContract = path[0];
        address USDCContract = path[1];

        // 2. liquidatePosition() will use usdc to Lend and get eth,so we need to approve usdc to lending protocol
        IERC20(USDCContract).approve(_FAKE_LENDING_PROTOCOL, amount1);
        IFakeLendingProtocol(_FAKE_LENDING_PROTOCOL).liquidatePosition();

        // 3. calculate repay amount
        uint256[] memory repayAmount = IUniswapV2Router01(_UNISWAP_ROUTER).getAmountsIn(amount1, path);
        // 4. cause pair is WETH/USDC, we need to convert eth to weth
        IWETH(WETHContract).deposit{value: repayAmount[0]}();
        // 5. repay eth to uniswap pool
        IERC20(WETHContract).transfer(pair, repayAmount[0]);
    }

    // we use single hop path for testing
    function liquidate(address[] calldata path, uint256 amountOut) external {
        require(amountOut > 0, "AmountOut must be greater than 0");
        // TODO
        // 1. use IUniswapV2Factory to get Pool address -> pair
        address pair = IUniswapV2Factory(_UNISWAP_FACTORY).getPair(path[0], path[1]);

        bytes memory data = abi.encode(path);

        IUniswapV2Pair(pair).swap(0, amountOut, address(this), data);
    }

    receive() external payable {}
}
