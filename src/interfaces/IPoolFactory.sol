// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// since this protocol is working with TSwap
// `IPoolFactory` will be the interface for working with `TSwap` poolFactory
// in the `poolFactory` of `Tswap` there is a `getPool` fn
// q why are we using `TSwap` for calculating the fee??
interface IPoolFactory {
    function getPool(address tokenAddress) external view returns (address);
}
