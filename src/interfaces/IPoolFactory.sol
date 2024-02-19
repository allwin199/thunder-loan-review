// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// e this is probably the interface to work with poolfactory.sol from tswap
// q why are we using tswap? what does that have to do with flash loans
interface IPoolFactory {
    function getPool(address tokenAddress) external view returns (address);
}
