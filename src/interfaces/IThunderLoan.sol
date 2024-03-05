// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @audit-info this interface should be implemented by the `ThunderLoan.sol` contract
interface IThunderLoan {
    // @audit-low/info
    function repay(address token, uint256 amount) external;
}
